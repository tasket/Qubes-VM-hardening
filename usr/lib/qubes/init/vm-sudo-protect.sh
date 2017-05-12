#!/bin/sh

## Protect startup of Qubes VMs from /rw scripts    ##
## https://github.com/tasket/Qubes-VM-hardening     ##


# Source Qubes library.
. /usr/lib/qubes/init/functions

# Define sh, bash, X and desktop init scripts in /home/user
# to be protected
chfiles=".bashrc .bash_profile .bash_login .bash_logout .profile \
.xprofile .xinitrc .xserverrc .xsession"
chdirs=".config/autostart .config/plasma-workspace/env .config/plasma-workspace/shutdown \
.config/autostart-scripts"
vmname=`qubesdb-read /name`
rw=/mnt/rwtmp

# Make user scripts immutable:
make_immutable() {
    cd $rw/home/user
    mkdir -p $chdirs
    touch $chfiles
    chattr -R -f +i $chfiles $chdirs
    touch $rw/home/user/FIXED #debug
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

# Protection measures for /rw dirs:
# Activated by presence of vm-sudo-protect-root Qubes service.
#   * Hashes in vms/vms.all.SHA and vms/$vmname.SHA files will be checked.
#   * Remove /rw root startup files (config, usrlocal, bind-dirs).
#   * Contents of vms/vms.all and vms/$vmname folders will be copied.
defdir="/etc/default/vms"
privdirs=${privdirs:-"$rw/config $rw/usrlocal $rw/bind-dirs"}

if qsvc vm-sudo-protect-root && is_rwonly_persistent; then

    # Check hashes
    checkcode=0
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

    # Deactivate private.img config dirs
    for dir in $privdirs; do
        rm -rf BAK-$dir
        mv $dir BAK-$dir
    done
    mkdir -p $privdirs

    for vmset in vms.all $vmname; do

        # Process whitelists...
        while read wlfile; do
            # Must begin with '/rw/'
            if echo $wlfile |grep -q "^\/rw\/"; then #Was [ $wlfile =~ ^\/rw\/ ];
                srcfile="`sed -r \"s|^/rw/(.+)$|$rw/BAK-\1|\" <<<\"$wlfile\"`"
                # For large dirs: instant mv whole dir when entry ends with '/'
                if echo $wlfile |grep -q "\/$"; then #Was [ $wlfile =~ .+\/$ ];
                    mkdir -p "`dirname \"$wlfile\"`"
                    mv "$srcfile" "`dirname \"$wlfile\"`"
                else
                    cp -al --parents "$srcfile" /
                fi
            else
                echo "Whitelist path must begin with /rw/."
            fi
        done <$defdir/$vmset.whitelist

        # Copy default files...
        if [ -d $defdir/$vmset/rw ]; then
            cp -af $defdir/$vmset/rw/* $rw
        fi
    done

fi

make_immutable
cd /
umount $rw && rmdir $rw
exit 0
