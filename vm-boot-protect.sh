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
defdir=/etc/default/vms
version="0.8.5"

# Define sh, bash, X and desktop init scripts in /home/user
# to be protected
chfiles=${chfiles:-".bashrc .bash_profile .bash_login .bash_logout .profile \
.xprofile .xinitrc .xserverrc .xsession"}
chfiles_add=""
chdirs=${chdirs:-"bin .local/bin .config/autostart .config/plasma-workspace/env \
.config/plasma-workspace/shutdown .config/autostart-scripts .config/systemd"}
chdirs_add=""

# Define dirs to apply quarrantine / whitelists
privdirs=${privdirs:-"/rw/config /rw/usrlocal /rw/bind-dirs"}
privdirs_add=""

# Run rc file commands if they exist
if [ -e $defdir/vms.all.rc ]; then
    . $defdir/vms.all.rc
fi
if [ -e $defdir/$vmname.rc ]; then
    . $defdir/$vmname.rc
fi


# Remount fs as read-write
remount_rw() {
    # Begin write operations
    if [ -e $dev ] && mount -o remount,rw $dev $rw ; then
        echo Good rw remount.
    else
        abort_startup RELOCATE "Remount failed!"
    fi
}


# Function: Make user scripts immutable.
make_immutable() {
    remount_rw
    #initialize_home $rw/home ifneeded
    cd $rw/home/user
    su user -c "mkdir -p $chdirs $chdirs_add; touch $chfiles $chfiles_add"
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

if qsvc vm-boot-protect || qsvc vm-boot-protect-root; then
    # Mount private volume in temp location
    mkdir -p $rw
    if [ -e $dev ] && mount -o ro $dev $rw ; then
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

    # Don't bother with root protections in template or standalone
    if ! is_rwonly_persistent; then
        make_immutable
        exit 0
    fi

fi


# Protection measures for /rw dirs:
# Activated by presence of vm-boot-protect-root Qubes service.
#   * Hashes in vms/vms.all.SHA and vms/$vmname.SHA files will be checked.
#   * Remove /rw root startup files (config, usrlocal, bind-dirs).
#   * Contents of vms/vms.all and vms/$vmname folders will be copied.

if qsvc vm-boot-protect-root && is_rwonly_persistent; then

    # Check hashes
    checkcode=0
    if [ -e $defdir/$vmname.SHA ]; then
        # remove padding and add number field
        sed 's/^ *//; s/ *$//; /^$/d; s/^/1 /' $defdir/$vmname.SHA \
          >/tmp/vm-boot-protect-sha
    fi
    if [ -e $defdir/vms.all.SHA ]; then
        sed 's/^ *//; s/ *$//; /^$/d; s/^/2 /' $defdir/vms.all.SHA \
          >>/tmp/vm-boot-protect-sha
    fi
    if [ -e /tmp/vm-boot-protect-sha ]; then
        echo "Checking file hashes." |tee $errlog
        # Get unique paths, remove field and switch path to $rw before check;
        # this allows hashes in $vmname.SHA to override ones in vms.all.SHA.
        sort --unique --key=3 /tmp/vm-boot-protect-sha  \
        | sed -r 's|^[1-2] (.*[[:space:]]*)/rw|\1'$rw'|' \
        | sha256sum --strict -c >>$errlog; checkcode=$?
    fi

    # Divert startup on hash mismatch:
    if [ $checkcode != 0 ]; then
        abort_startup RELOCATE "Hash check failed!"
    fi

    remount_rw

    # Files mutable for del/copy operations
    cd $rw/home/user
    chattr -R -f -i $chfiles $chfiles_add $chdirs $chdirs_add $privdirs $privdirs_add
    cd /root


    # Deactivate private.img config dirs
    mkdir -p $rwbak
    for dir in $privdirs $privdirs_add; do # maybe use 'eval' for privdirs quotes/escaping
        echo "Deactivate $dir"
        subdir=`echo $dir |sed -r 's|^/rw/||'`
        bakdir="$rwbak/BAK-$subdir"
        origdir="$rwbak/ORIG-$subdir"
        if [ -e "$bakdir" ] && [ ! -e "$origdir" ]; then
            mv "$bakdir" "$origdir"
        fi
        if [ -e "$bakdir" ]; then
            chattr -R -i "$bakdir"
            rm -rf "$bakdir"
        fi
        mv "$rw/$subdir" "$bakdir"
        mkdir -p "$rw/$subdir"

        # Populate /home/user w skel files if it was in privdirs
        case "$subdir" in
            "home"|"home/"|"home/user"|"home/user/")
                echo "Populating home dir"
                #chown user:user $rw/home/user
                rm -rf /home/user $rw/home/user
                mkhomedir_helper user
                mv /home/user $rw/home
                ;;
        esac
    done

    for vmset in vms.all $vmname; do

        # Process whitelists...
        cat $defdir/$vmset.whitelist \
        | while read wlfile; do
            # Must begin with '/rw/'
            if echo $wlfile |grep -q "^\/rw\/"; then
                srcfile="`echo $wlfile |sed -r \"s|^/rw/(.+)$|$rwbak/BAK-\1|\"`"
                dstfile="`echo $wlfile |sed -r \"s|^/rw/(.+)$|$rw/\1|\"`"
                dstdir="`dirname \"$dstfile\"`"
                if [ ! -e "$srcfile" ]; then
                    echo "Whitelist entry not present in filesystem:"
                    echo "$srcfile"
                    continue
                # For very large dirs: mv whole dir when entry ends with '/'
                elif echo $wlfile |grep -q "\/$"; then
                    echo "Whitelist mv $srcfile"
                    echo "to $dstfile"
                    mkdir -p "$dstdir"
                    mv -T "$srcfile" "$dstfile"
                else
                    echo "Whitelist cp $srcfile"
                    mkdir -p "$dstdir"
                    cp -a --link "$srcfile" "$dstdir"
                fi
            elif [ -n "$wlfile" ]; then
                echo "Whitelist path must begin with /rw/. Skipped."
            fi
        done

        # Copy default files...
        if [ -d $defdir/$vmset/rw ]; then
            echo "Copy files from $defdir/$vmset/rw"
            cp -af $defdir/$vmset/rw/* $rw
        fi
    done

fi

# Keep configs invisible at runtime...
rm -rf "$defdir"

if qsvc vm-boot-protect || qsvc vm-boot-protect-root; then
    make_immutable
    umount $rw
fi

exit 0
