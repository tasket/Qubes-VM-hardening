#!/bin/sh

# Define sh, bash, X and desktop init scripts
# to be protected
chfiles=".bashrc .bash_profile .bash_login .bash_logout .profile \
.xprofile .xinitrc .xserverrc .xsession"
chdirs=".config/autostart .config/plasma-workspace/env .config/plasma-workspace/shutdown \
.config/autostart-scripts"

mkdir -p /rw
if [ -e /dev/xvdb ] && mount /rw ; then
  echo Good rw mount.
else
  exit 0
fi

# Experimental: Remove /rw root startup files and copy defaults.
# Activated by presence of /etc/defaults/vms/vms.all dir.
# Contents of vms/vms.all and vms/hostname will be copied.
defdir="/etc/default/vms"
rootdirs="/rw/config /rw/usrlocal /rw/bind-dirs"
if [ -d $defdir/vms.all ] && [ `qubesdb-read /qubes-vm-persistence` = "rw-only" ]; then
  rm -rf $rootdirs
  # make user scripts temporarily mutable, in case 'rw/home/user'
  # files exist in defdir...
  cd /rw/home/user
  chattr -R -f -i $chfiles $chdirs || true
  # copy..
  cp -af $defdir/vms.all/* / || true
  if [ -d $defdir/$(hostname) ]; then
    cp -af $defdir/$(hostname)/* / || true
  fi
fi

# Make user scripts immutable
cd /rw/home/user
mkdir -p $chdirs ||true
touch $chfiles || true
chattr -R -f +i $chfiles $chdirs || true
touch /rw/home/user/FIXED || true

cd /
umount /rw
