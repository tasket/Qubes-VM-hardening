#!/bin/sh

##  Protect startup of Qubes VMs from /rw scripts    ##
##  https://github.com/tasket/Qubes-VM-hardening     ##
##  Copyright 2017-2018 Christopher Laprise          ##
##                      tasket@protonmail.com        ##

#   This is part of Qubes-VM-hardening.
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
#   along with Foobar.  If not, see <http://www.gnu.org/licenses/>.


# Source Qubes library.
. /usr/lib/qubes/init/functions

# Define sh, bash, X and desktop init scripts in /home/user
# to be protected
chfiles=".bashrc .bash_profile .bash_login .bash_logout .profile \
.xprofile .xinitrc .xserverrc .xsession"
chdirs="bin .local/bin .config/autostart .config/plasma-workspace/env \
.config/plasma-workspace/shutdown .config/autostart-scripts"

vmname=`qubesdb-read /name`
rw=/mnt/rwtmp
rwbak=$rw/vm-boot-protect
errlog=/var/run/vm-protect-error
defdir=/etc/default/vms


# Function: Make user scripts immutable.
make_immutable() {
    #initialize_home $rw/home ifneeded
    cd $rw/home/user
    mkdir -p $chdirs
    touch $chfiles
    chattr -R -f +i $chfiles $chdirs
    cd /root
    #touch $rw/home/user/FIXED #debug
}

# Start rescue shell then exit/fail
abort_startup() {
    echo "$1" >>$errlog
    cat $errlog

    umount /dev/xvdb
    mv -f /dev/xvdb /dev/badxvdb
    truncate --size=500M /root/dev-xvdb
    loop=`losetup --find --show /root/dev-xvdb`
    mv -f $loop /dev/xvdb

    cat /etc/bashrc /etc/bash.bashrc >/etc/bashrc-insert
    echo "echo '** VM-BOOT-PROTECT SERVICE SHELL'" >/etc/bashrc
    echo "echo '** Private volume is located at /dev/badxvdb'" >>/etc/bashrc
    echo "cat $errlog" >>/etc/bashrc
    echo ". /etc/bashrc-insert" >>/etc/bashrc
    ln -f /etc/bashrc /etc/bash.bashrc
    echo '/usr/bin/nohup /usr/bin/xterm /bin/bash 0<&- &>/dev/null &' \
        >/etc/X11/Xsession.d/98rescue
    exit 1
}


# Don't bother with root protections in template or standalone
if ! is_rwonly_persistent; then
    if qsvc vm-boot-protect; then
        make_immutable
    fi
    exit 0
fi

echo >$errlog # Clear

if qsvc vm-boot-protect-cli; then
    abort_startup "CLI requested."
fi

# Mount private volume in temp location
mkdir -p $rw
if [ -e /dev/xvdb ] && mount -o ro /dev/xvdb $rw ; then
    echo "Good read-only mount."
else
    abort_startup "Mount failed!"
fi



# Protection measures for /rw dirs:
# Activated by presence of vm-boot-protect-root Qubes service.
#   * Hashes in vms/vms.all.SHA and vms/$vmname.SHA files will be checked.
#   * Remove /rw root startup files (config, usrlocal, bind-dirs).
#   * Contents of vms/vms.all and vms/$vmname folders will be copied.
privdirs=${privdirs:-"/rw/config /rw/usrlocal /rw/bind-dirs"}

if qsvc vm-boot-protect-root && is_rwonly_persistent; then

    # Check hashes
    checkcode=0
    echo "File hash checks:" >/tmp/vm-protect-sum-error
    for vmset in vms.all $vmname; do
        if [ -f $defdir/$vmset.SHA ]; then
            sha256sum --strict -c $defdir/$vmset.SHA >>$errlog 2>&1
            checkcode=$((checkcode+$?))
        fi
    done

    # Stop system startup on checksum mismatch:
    if [ $checkcode != 0 ]; then
        abort_startup "Hash check failed!"
    fi

    # Begin write operations
    if [ -e /dev/xvdb ] && mount -o remount,rw /dev/xvdb $rw ; then
        echo Good rw remount.
    else
        abort_startup "Remount failed!"
    fi

    # Files mutable for del/copy operations
    cd $rw/home/user
    chattr -R -f -i $chfiles $chdirs $privdirs
    cd /root


    # Deactivate private.img config dirs
    mkdir -p $rwbak
    for dir in $privdirs; do # maybe use 'eval' for privdirs quotes/escaping
        echo "Deactivate $dir"
        subdir=`echo $dir |sed -r 's|^/rw/||'`
        bakdir="$rwbak/BAK-$subdir"
        origdir="$rwbak/ORIG-$subdir"
        if [ -d "$bakdir" ] && [ ! -d "$origdir" ]; then
            mv "$bakdir" "$origdir"
        fi
        rm -rf  "$bakdir"
        mv "$rw/$subdir" "$bakdir"
        mkdir -p "$rw/$subdir"
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

    # Keep configs invisible at runtime...
    rm -rf "$defdir"

fi

make_immutable
umount $rw
exit 0
