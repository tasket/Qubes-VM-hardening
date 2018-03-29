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

# Mount private volume in temp location
mkdir -p $rw
if [ -e /dev/xvdb ] && mount /dev/xvdb $rw ; then
    echo Good rw mount.
else
    echo Mount failed!
    xterm -hold -display :0 -title "VM PROTECTION: MOUNT FAILED!" \
-e "bash -i"
    exit 1
fi
if qsvc vm-boot-protect-cli; then
    xterm -hold -display :0 -title "VM PROTECTION: SERVICE PROMPT" \
-e "echo Private volume is mounted at $rw; bash -i"
fi


# Protection measures for /rw dirs:
# Activated by presence of vm-boot-protect-root Qubes service.
#   * Hashes in vms/vms.all.SHA and vms/$vmname.SHA files will be checked.
#   * Remove /rw root startup files - except whitelist.
#   * Contents of vms/vms.all and vms/$vmname folders will be copied.
defdir="/etc/default/vms"
privdirs=${privdirs:-"$rw/config $rw/usrlocal $rw/bind-dirs"}

if qsvc vm-boot-protect-root && is_rwonly_persistent; then

    # Check hashes
    checkcode=0
    echo >/tmp/vm-protect-sum-error
    echo "File hash checks:" >/tmp/vm-protect-sum-error
    for vmset in vms.all $vmname; do
        if [ -f $defdir/$vmset.SHA ]; then
            sha256sum --strict -c $defdir/$vmset.SHA >>/tmp/vm-protect-sum-error 2>&1
            checkcode=$((checkcode+$?))
        fi
    done
    cat /tmp/vm-protect-sum-error # For logging

    # Stop system startup on checksum mismatch:
    if [ $checkcode != 0 ]; then
        xterm -hold -display :0 -title "VM PROTECTION: CHECKSUM MISMATCH!" \
-e "cat /tmp/vm-protect-sum-error; echo Private volume is mounted at $rw; bash -i"
        exit 1
    fi

    # Files mutable for del/copy operations
    cd $rw/home/user
    chattr -R -f -i $chfiles $chdirs $privdirs
    cd /root

    # Deactivate private.img config dirs
    mkdir -p $rw/vm-boot-protect
    for dir in $privdirs; do
        bakdir=$rw/vm-boot-protect/BAK-`basename $dir`
        origdir=$rw/vm-boot-protect/ORIG-`basename $dir`
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
                srcfile="`echo $wlfile |sed -r \"s|^/rw/(.+)$|$rw/vm-boot-protect/BAK-\1|\"`"
                dstfile="`echo $wlfile |sed -r \"s|^/rw/(.+)$|$rw/\1|\"`"
                dstdir="`dirname \"$dstfile\"`"
                if [ ! -e "$srcfile" ]; then
                    echo "Whitelist entry not present in filesystem."
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
                echo "Whitelist path must begin with /rw/."
            fi
        done

        # Copy default files...
        if [ -d $defdir/$vmset/rw ]; then
            cp -af $defdir/$vmset/rw/* $rw
        fi
        
    done

    # Keep configs invisible at runtime...
    rm -rf $defdir/*

fi

make_immutable
umount $rw
exit 0
