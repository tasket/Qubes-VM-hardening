#!/bin/sh

##  Protect startup of Qubes VMs from /rw content    ##
##  https://github.com/tasket/Qubes-VM-hardening     ##
##  Copyright 2017-2019 Christopher Laprise          ##
##                      tasket@protonmail.com        ##

#   This file is part of Qubes-VM-hardening.
#   Qubes-VM-hardening is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   Qubes-VM-hardening is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with Qubes-VM-hardening. If not, see <http://www.gnu.org/licenses/>.


# Source Qubes library.
. /usr/lib/qubes/init/functions

vmname=`qubesdb-read /name`
dev=/dev/xvdb
rw=/mnt/rwtmp
rwbak=$rw/vm-boot-protect
errlog=/var/run/vm-protect-error
servicedir=/var/run/qubes-service
defdir=/etc/default/vms
version=0.9.3

# Define sh, bash, X and desktop init scripts in /home/user
# to be protected
chfiles=${chfiles:-".bashrc .bash_profile .bash_login .bash_logout .profile \
.pam_environment .xprofile .xinitrc .xserverrc .Xsession .xsession .xsessionrc"}
chfiles_add=${chfiles_add:-""}
chdirs=${chdirs:-"bin .local/bin .config/autostart .config/plasma-workspace/env \
.config/plasma-workspace/shutdown .config/autostart-scripts .config/systemd"}
chdirs_add=${chdirs_add:-""}

# Define dirs to apply quarantine / whitelists
privdirs=${privdirs:-"/rw/config /rw/usrlocal /rw/bind-dirs"}
privdirs_add=${privdirs_add:-""}
save_backup=${save_backup:-1}

if is_rwonly_persistent; then
    rwonly_pers=1
else
    rwonly_pers=0
fi


# Placeholder function: Runs at end
vm_boot_finish() { return; }


# Remount fs as read-write
remount_rw() {
    # Begin write operations
    if [ -e $dev ] && mount -o remount,rw,nosuid,nodev $dev $rw ; then
        echo Good rw remount.
    else
        abort_startup RELOCATE "Remount failed!"
    fi
}


# Function: Make user scripts immutable.
make_immutable() {
    echo "Making files IMMUTABLE"
    remount_rw
    #initialize_home $rw/home ifneeded
    cd $rw/home/user
    su user -c "mkdir -p $chdirs $chdirs_add; touch $chfiles $chfiles_add 2>/dev/null"
    chattr -R -f +i $chfiles $chfiles_add $chdirs $chdirs_add
    cd /root
}


# Start rescue shell then exit/fail
abort_startup() {
    type="$1"
    msg="$2"
    echo "$msg" >>$errlog
    cat $errlog

    rc=1
    if [ $type = "RELOCATE" ]; then
    # quarantine private volume
        umount $dev
        mv -f $dev /dev/badxvdb
        truncate --size=500M /root/dev-xvdb
        loop=`losetup --find --show /root/dev-xvdb`
        mv -f $loop $dev
    elif [ $type = "OK" ]; then
    # allow normal start with private vol
        rc=0
    fi

    # insert status msg and run xterm
    cat /etc/bashrc /etc/bash.bashrc >/etc/bashrc-insert
    echo "echo '** VM-BOOT-PROTECT SERVICE SHELL'" >/etc/bashrc
    if [ $type = "RELOCATE" ]; then
        echo "echo '** Private volume is located at /dev/badxvdb'" >>/etc/bashrc
    fi
    echo "cat $errlog" >>/etc/bashrc
    echo ". /etc/bashrc-insert" >>/etc/bashrc
    ln -f /etc/bashrc /etc/bash.bashrc
    echo '/usr/bin/nohup /usr/bin/xterm /bin/bash 0<&- &>/dev/null &' \
        >/etc/X11/Xsession.d/98rescue

    exit $rc
}


echo >$errlog # Clear
if qsvc vm-boot-protect-cli; then
    abort_startup RELOCATE "CLI requested."
fi


# Run rc file commands if they exist
if qsvc vm-boot-protect-root && [ $rwonly_pers = 1 ]; then
    # Get list of enabled tags from Qubes services
    tags=`find $servicedir -name 'vm-boot-tag-*' -type f -printf '%f\n' \
          | sort | sed -E 's|^vm-boot-tag-|\@tags/|'`

    for rcbase in vms.all $tags $vmname; do
        if [ -e "$defdir/$rcbase.rc" ]; then
            . "$defdir/$rcbase.rc"
        fi
    done
fi


if qsvc vm-boot-protect || qsvc vm-boot-protect-root; then
    # Mount private volume in temp location
    mkdir -p $rw
    if [ -e $dev ] && mount -o ro,nosuid,nodev $dev $rw ; then
        echo "Good read-only mount."
    else
        echo "Mount failed."
        # decide if this is initial boot or a bad volume
        private_size_512=$(blockdev --getsz "$dev")
        if head -c $(( private_size_512 * 512 )) /dev/zero | diff "$dev" - >/dev/null; then
            touch /var/run/qubes/VM-BOOT-PROTECT-INITIALIZERW
            abort_startup OK "FIRST BOOT INITIALIZATION: PLEASE RESTART VM!"
        else
            abort_startup RELOCATE "Mount failed; BAD private volume!"
        fi
    fi

    # Begin exit if in template or standalone
    if [ $rwonly_pers = 0 ]; then
        make_immutable
        umount $rw
    fi

fi
# Exit if in template or standalone
if [ $rwonly_pers = 0 ]; then
    exit 0
fi


# Protection measures for /rw dirs:
# Activated by presence of vm-boot-protect-root Qubes service.
#   * Hashes in vms/vms.all.SHA and vms/$vmname.SHA files will be checked.
#   * Remove /rw root startup files (config, usrlocal, bind-dirs).
#   * Contents of vms/vms.all and vms/$vmname folders will be copied.

if qsvc vm-boot-protect-root && [ $rwonly_pers = 1 ]; then

    # Check hashes
    checkcode=0
    for sha_base in $vmname $tags vms.all; do
        if [ -e "$defdir/$sha_base.SHA" ]; then
            cat "$defdir/$sha_base.SHA" >>/tmp/vm-boot-protect-sha
        fi
    done
    if [ -e /tmp/vm-boot-protect-sha ]; then
        echo "Checking file hashes." |tee $errlog
        # Strip padding, get unique paths and switch path to $rw before check;
        # this allows hashes in $vmname.SHA to override ones in vms.all.SHA.
        sed 's/^ *//; s/ *$//; /^$/d;' /tmp/vm-boot-protect-sha \
        | sort -u -k2,2 \
        | sed -r 's|^(\S+\s+)/rw|\1'$rw'|' \
        | sha256sum --strict -c >>$errlog; checkcode=$?
    fi

    # Divert startup on hash mismatch:
    if [ $checkcode != 0 ]; then
        abort_startup RELOCATE "Hash check failed!"
    fi

    remount_rw

    # Files mutable for del/copy operations
    cd $rw/home/user
    chattr -R -f -i $chfiles $chfiles_add $chdirs $chdirs_add $privdirs $privdirs_add \
                    $rwbak/BAK-*
    cd /root


    # Deactivate private.img config dirs
    mkdir -p $rwbak
    for dir in $privdirs $privdirs_add; do # maybe use 'eval' for privdirs quotes/escaping
        # echo "Deactivate $dir"
        subdir=`echo $dir |sed -r 's|^/rw/||'`
        bakdir="$rwbak/BAK-$subdir"
        origdir="$rwbak/ORIG-$subdir"
        if [ -e "$bakdir" ] && [ ! -e "$origdir" ]; then
            mv "$bakdir" "$origdir"
        fi
        if [ -e "$bakdir" ]; then
            #chattr -R -i "$bakdir"
            rm -rf "$bakdir"
        fi
        mv "$rw/$subdir" "$bakdir"
        mkdir -p "$rw/$subdir"

        # Populate /home/user w skel files if it was in privdirs
        case "$subdir" in
            "home"|"home/"|"home/user"|"home/user/")
                # echo "Populating home dir"
                rm -rf /home/user $rw/home/user
                mount --bind -o nosuid,nodev $rw/home /home
                mkhomedir_helper user
                umount /home
                ;;
        esac
    done

    for vmset in vms.all $tags $vmname; do

        # Process whitelists...
        if [ -e $defdir/$vmset.whitelist ]; then
            cat $defdir/$vmset.whitelist \
            | while read wlfile; do
                # Must begin with '/rw/'
                if echo $wlfile |grep -q "^\/rw\/"; then
                    srcfile="`echo $wlfile |sed -r \"s|^/rw/(.+)$|$rwbak/BAK-\1|\"`"
                    dstfile="`echo $wlfile |sed -r \"s|^/rw/(.+)$|$rw/\1|\"`"
                    dstdir="`dirname \"$dstfile\"`"
                    if [ ! -e "$srcfile" ]; then
                        # echo "Whitelist entry not present in filesystem:"
                        # echo "$srcfile"
                        continue
                    # For very large dirs: mv whole dir when entry ends with '/'
                    elif echo $wlfile |grep -q "\/$"; then
                        # echo "Whitelist mv $srcfile"
                        # echo "to $dstfile"
                        mkdir -p "$dstdir"
                        mv -T "$srcfile" "$dstfile"
                    else
                        # echo "Whitelist cp $srcfile"
                        mkdir -p "$dstdir"
                        cp -a --link "$srcfile" "$dstdir"
                    fi
                elif [ -n "$wlfile" ]; then
                    echo "Whitelist path must begin with /rw/. Skipped."
                fi
            done
        fi

        # Copy default files...
        if [ -d $defdir/$vmset/rw ]; then
            # echo "Copy files from $defdir/$vmset/rw"
            cp -af $defdir/$vmset/rw/* $rw
        fi
    done

    vm_boot_finish

fi

# Remove backups if indicated
if [ $save_backup = 0 ]; then
    chattr -R -f -i $rwbak
    rm -rf $rwbak
fi

if qsvc vm-boot-protect || qsvc vm-boot-protect-root; then
    echo "Preparing for unmount"
    make_immutable
    umount $rw
fi

# Keep configs invisible at runtime...
if ! is_templatevm; then
    rm -rf "$defdir" $servicedir/vm-boot-tag* $servicedir/vm-boot-protect* $errlog
fi
exit 0
