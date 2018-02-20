# Qubes-VM-hardening
Enhancing Qubes VM security and privacy

   
---


## vm-sudo-protect.service
   * Protect /home (user) executable files as immutable
   * Deactivate /rw (root) executables
   * Whitelisting for specifying persistent files
   * SHA256 checksumming guards against unwanted changes
   * Deploy custom defaut files
   * Runs at VM start before /rw mounts

## Installing
### Pre-requisites:
   Re-enable sudo authentication (see notes below).

1. In a template VM, install the two service files
```
$ sudo sh ./install
```
2. Activate by specifying as a Qubes service for each VM; There are two levels...
   - `vm-sudo-protect` - Protects executables/scripts within /home/user and may be used with wide array of Qubes VMs including standalone, netVMs and Whonix.
   - `vm-sudo-protect-root` -  Protects /home/user as above, automatic /rw executable deactivation, whitelisting, checksumming, deployment. Works with appVMs, netVMs, etc. that are _template-based_.

   
   **removes** dirs specified in $privdirs. Default is /rw/config, /rw/usrlocal and /rw/bind-dirs. Use with caution! This feature can also replace files on a global or per-VM basis... see script for details. Not recommended for standalone or VMs that rely on /rw root dirs such as netVMs or Whonix.

---

## Releases
- v0.2.0  Protects /home/user files and dirs only

### Description:
Placed in /etc/rc.local (or equivalent) of a template VM, this makes the shell init files immutable so PATH and alias cannot be used to hijack commands like su and sudo, nor can impostor apps autostart whenever a VM starts. I combed the dash and bash docs -- as well as Gnome, KDE, Xfce and X11 docs -- to address all the user-writable startup files that apply. Feel free to comment or create an issue if you see an omission or other problem.

Although protecting init/autostart files should result in Qubes template-based VMs that boot 'cleanly' with much less chance of being affected by malware initially, it should be noted that subsequent running of some apps such as Firefox could conceivably allow malware to persist in a VM; this is because not only of the complexity of the formats handled by apps like Firefox and other browsers, but also because of settings contained in javascript code. Even if malware persists in a VM, it should be possible to run other apps and terminals without interference if sudo authentication is enabled and malware has not escalated to root via an exploit (admittedly, a big 'if').

All in all, this is one of the easy steps a Qubes user can take to make their VMs much less hospitable to intrusion and malware. Security can be further enhanced by enabling AppArmor or similar controls.

Note this sets the Linux immutable flag on files and directories, so intended modifications to the target files and dirs will require the extra step of disabling the flag using `sudo chattr -i`. Immutable is necessary because normal read-write permissions cannot prevent a normal user from removing other users' files (even root) from a dir they own; once removed, an init file like .bashrc can be re-created by the user process which opens the door to hijacking.
 
 
 
## See also:

[Enabling dom0 prompt for sudo](https://www.qubes-os.org/doc/vm-sudo/#replacing-password-less-root-access-with-dom0-user-prompt)

[AppArmor Profiles](https://github.com/tasket/AppArmor-Profiles)
