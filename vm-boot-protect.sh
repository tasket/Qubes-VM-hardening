#!/bin/sh

## Protect startup of Qubes VMs from /rw scripts    ##
## https://github.com/tasket/Qubes-VM-hardening     ##


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
errlog=/var/run/vm-protect-error

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
    mount -o ro /dev/badxvdb $rw
    truncate --size=500M /root/dev-xvdb
    loop=`losetup --find --show /root/dev-xvdb`
    mv -f $loop /dev/xvdb

    cat /etc/bashrc /etc/bash.bashrc >/etc/bashrc-insert
    echo "echo '** VM-BOOT-PROTECT SERVICE SHELL'" >/etc/bashrc
    echo "echo '** Private volume is located at' $rw" >>/etc/bashrc
    echo "cat $errlog" >>/etc/bashrc
    echo ". /etc/bashrc-insert" >>/etc/bashrc
    ln -f /etc/bashrc /etc/bash.bashrc
    echo '/usr/bin/nohup /usr/bin/xterm /bin/bash 0<&- &>/dev/null &' \
        >/etc/X11/Xsession.d/98rescue
    exit 1
}


# Don't bother with root protections in template or standalone
if ! is_rwonly_persistent; then
###    make_immutable
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
defdir="/etc/default/vms"
privdirs=${privdirs:-"$rw/config $rw/usrlocal $rw/bind-dirs"}

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
    mkdir -p $rw/vm-boot-protect
    for dir in $privdirs; do
        echo "Deactivate $dir"
        bakdir=`dirname $dir`/vm-boot-protect/BAK-`basename $dir`
        origdir=`dirname $dir`/vm-boot-protect/ORIG-`basename $dir`
        if [ -d $bakdir ] && [ ! -d $origdir ]; then
            mv $bakdir $origdir
        fi
        rm -rf  $bakdir
        mv $dir $bakdir
    done
    mkdir -p $privdirs

    for vmset in vms.all $vmname; do

        # Process whitelists...
        cat $defdir/$vmset.whitelist \
        | while read wlfile; do
            # Must begin with '/rw/'
            if echo $wlfile |grep -q "^\/rw\/"; then #Was [ $wlfile =~ ^\/rw\/ ];
                srcfile="`echo $wlfile |sed -r \"s|^/rw/(.+)$|$rw/BAK-\1|\"`"
                dstfile="`echo $wlfile |sed -r \"s|^/rw/(.+)$|$rw/\1|\"`"
                dstdir="`dirname \"$dstfile\"`"
                if [ ! -e "$srcfile" ]; then
                    echo "Whitelist entry not present in filesystem:"
                    echo "$srcfile"
                    continue
                # For very large dirs: mv whole dir when entry ends with '/'
                elif echo $wlfile |grep -q "\/$"; then
                    echo "Whitelist mv $srcfile"
                    mkdir -p "$dstdir"
                    mv "$srcfile" "$dstdir"
                else
                    echo "Whitelist cp $srcfile"
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
    rm -rf $defdir/*

fi

make_immutable
umount $rw
exit 0
