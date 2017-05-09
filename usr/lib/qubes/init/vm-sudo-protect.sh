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
    touch $rw/home/user/FIXED
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
            sha256sum --strict -c $defdir/$vmset.SHA &>>/tmp/vm-protect-sum-error
            checkcode=$((checkcode+$?))
        fi
    done
    # Stop system startup if checksum mismatched
    if [ $checkcode != 0 ]; then
        cat /tmp/vm-protect-sum-error # For logging
        xterm -hold -display :0 -title "VM PROTECTION: CHECKSUM MISMATCH!" \
-e "cat /tmp/vm-protect-sum-error; echo Private volume is mounted at $rw; bash -i"
        exit 1
    fi




    # Make user scripts temporarily mutable, in case 'rw/home/user'
    # files exist in defdir -- Copy default files
    cd $rw/home/user
    chattr -R -f -i $chfiles $chdirs

    # Deactivate config dirs
    for dir in $rootdirs; do
        if [ -d $dir ]; then
            chattr -R -f -i $dir
            cp -a --link $dir $dir-BAK
#            rm -rf $dir-BAK
#            mv $dir $dir-BAK
            find $dir -type f | cat - $defdir/$HOSTNAME.whitelist $defdir/vms.all.whitelist \
| sed -r "s|^\ */rw(.+)\ *$|$rw\1|" | sort | uniq -u | xargs -I fpath rm -f "fpath"
        fi

        for vmset in vms.all $HOSTNAME; do
            # Process whitelists -- FIX FIX FIX
            while false; do
#            while read srcfile; do
                if [[ $srcfile =~ ^$dir\/ ]]; then
                    cp -a --link --parents `sed -r "s|^/rw/|$rw/BAK-|" <<<$srcfile` /
                else
                    echo "Cannot use relative or non-rw whitelist path."
                fi
            done <$defdir/$vmset.whitelist

            # Copy default files
            if [ -d $defdir/$vmset ]; then
                cp -af $defdir/$vmset/* /
            fi
        done
    done

fi

make_immutable
cd /
umount $rw && rmdir $rw
exit 0
