#!/bin/sh

## Protect startup of Qubes VMs from /rw scripts    ##
## https://github.com/tasket/Qubes-VM-hardening     ##


# Source Qubes library.
. /usr/lib/qubes/init/functions

# Define sh, bash, X and desktop init scripts
# to be protected
chfiles=".bashrc .bash_profile .bash_login .bash_logout .profile \
.xprofile .xinitrc .xserverrc .xsession"
chdirs=".config/autostart .config/plasma-workspace/env .config/plasma-workspace/shutdown \
.config/autostart-scripts"

# Make user scripts immutable:
make_immutable() {
    cd $rw/home/user
    mkdir -p $chdirs
    touch $chfiles
    chattr -R -f +i $chfiles $chdirs
    touch $rw/home/user/FIXED #debug
}

# Mount private volume in temp location
rw=/mnt/rwtmp
mkdir -p $rw
if [ -e /dev/xvdb ] && mount /dev/xvdb $rw ; then
    echo Good rw mount.
else
    exit 0
fi

# Protection measures for /rw dirs:
# Activated by presence of vm-sudo-protect-root Qubes service.
#   * Hashes in vms/vms.all.SHA and vms/$HOSTNAME.SHA files will be checked.
#   * Remove /rw root startup files.
#   * Contents of vms/vms.all and vms/$HOSTNAME folders will be copied.
defdir="/etc/default/vms"
rootdirs="$rw/config $rw/usrlocal $rw/bind-dirs"
HOSTNAME=`hostname`

if qsvc vm-sudo-protect-root && is_rwonly_persistent; then

    # Check hashes
    checkcode=0
    echo "File hash checks:" >/tmp/vm-protect-sum-error
    for vmset in vms.all $HOSTNAME; do
        if [ -f $defdir/$vmset.SHA ]; then
            sha256sum --strict -c $defdir/$vmset.SHA >>/tmp/vm-protect-sum-error 2>&1
            checkcode=$((checkcode+$?))
        fi
    done
    cat /tmp/vm-protect-sum-error # For logging
    # Stop system startup if checksum mismatched
    if [ $checkcode != 0 ]; then
        xterm -hold -display :0 -title "VM PROTECTION: CHECKSUM MISMATCH!" \
-e "cat /tmp/vm-protect-sum-error; echo Private volume is mounted at $rw; bash -i"
        exit 1
    fi


    # Files mutable for del/copy operations
    cd $rw/home/user
    chattr -R -f -i $chfiles $chdirs $rootdirs

    # Deactivate config dirs
    for dir in $rootdirs; do
        if [ -d $dir ]; then
            if [ ! -d $dir-BAK ]; then
                cp -a --link $dir $dir-BAK
            fi
            find $dir/* -depth | cat - $defdir/$HOSTNAME.whitelist $defdir/vms.all.whitelist \
| sed -r "s|^\ */rw(.+)\ *$|$rw\1|" | sort | uniq -u | xargs -I fpath rm -fd 'fpath'
        fi
    done

    # Copy default files
    for vmset in vms.all $HOSTNAME; do
        if [ -d $defdir/$vmset ]; then
            cp -af $defdir/$vmset/* /
        fi
    done

fi

make_immutable
cd /
umount $rw && rmdir $rw
exit 0
