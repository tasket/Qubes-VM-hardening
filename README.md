# Qubes-VM-hardening
Fends off malware at VM startup by locking-down or removing scripts in /rw private storage that affect the execution environment.

   
---


## vm-boot-protect.service
   * Protect /home (user) executable files as immutable
   * Deactivate /rw (root) executables
   * Whitelisting for specifying persistent files
   * SHA256 checksumming guards against unwanted changes
   * Deploy custom defaut files
   * Runs at VM start before /rw mounts


## Installing
### Pre-requisites
   Disable default passwordless-root access for VMs (see notes below).

1. In a template VM, install the two service files
   ```
   sudo sh ./install
   ```
2. Activate by specifying as a Qubes service for each VM; There are two levels...
   - `vm-boot-protect` - Protects executables/scripts within /home/user and may be used with wide array of Qubes VMs including standalone, netVMs and Whonix.
   - `vm-boot-protect-root` -  Protects /home/user as above, automatic /rw executable deactivation, whitelisting, checksumming, deployment. Works with appVMs, netVMs, etc. that are _template-based_.

   
   CAUTION: The root option **removes** dirs specified in $privdirs; Default is /rw/config, /rw/usrlocal and /rw/bind-dirs.

---

### Usage



### FIXME Description

Placed in /etc/rc.local (or equivalent) of a template VM, this makes the shell init files immutable so PATH and alias cannot be used to hijack commands like su and sudo, nor can impostor apps autostart whenever a VM starts. I combed the dash and bash docs -- as well as Gnome, KDE, Xfce and X11 docs -- to address all the user-writable startup files that apply. Feel free to comment or create an issue if you see an omission or other problem.

Although protecting init/autostart files should result in Qubes template-based VMs that boot 'cleanly' with much less chance of being affected by malware initially, it should be noted that subsequent running of some apps such as Firefox could conceivably allow malware to persist in a VM; this is because not only of the complexity of the formats handled by apps like Firefox and other browsers, but also because of settings contained in javascript code. Even if malware persists in a VM, it should be possible to run other apps and terminals without interference if sudo authentication is enabled and malware has not escalated to root via an exploit (admittedly, a big 'if').

All in all, this is one of the easy steps a Qubes user can take to make their VMs much less hospitable to intrusion and malware. Security can be further enhanced by enabling AppArmor or similar controls.

Note this sets the Linux immutable flag on files and directories, so intended modifications to the target files and dirs will require the extra step of disabling the flag using `sudo chattr -i`. Immutable is necessary because normal read-write permissions cannot prevent a normal user from removing other users' files (even root) from a dir they own; once removed, an init file like .bashrc can be re-created by the user process which opens the door to hijacking.


### Limitations

vm-boot-protect relies mostly on the guest operating system's own defenses, with one added advantage of root volume non-persistence provided by the Qubes template system. This means that attacks which can profoundly undermine the guest OS, i.e. by damaging the private filesystem itself or quickly re-exploiting network vulnerabilities, could conceivably still persist at startup.

Further, if the user configures a vulnerable app to run at startup, this introduces a malware risk -- although not to the VM's whole execution environment if no privilege escalation is available to the attacker.

### Notes
* Disabling the Qubes default passwordless-root is necessary for this project to have a meaningful impact. Here are two recommended ways:
   1. [Enabling dom0 prompt for sudo](https://www.qubes-os.org/doc/vm-sudo/#replacing-password-less-root-access-with-dom0-user-prompt)
   2. Uninstall the `qubes-core-agent-passwordless-root` package from the template. After doing this, you will have to use `qvm-run -u root` from dom0 to run VM commands as root.

* The service name has been changed from `vm-sudo-protect` in pre-release to `vm-boot-protect`. The install script will automatically try to disable the old service.

* Currently if a vm-boot-protect check fails there is no immediate way to alert the user at startup. The VM will attempt to shutdown instead. See issue #7 for discussion.
 
## Releases
- v0.8.0  Adds protection to /rw, file SHA checksums, whitelists, deployment
- v0.2.0  Protects /home/user files and dirs


## See also:

[AppArmor Profiles](https://github.com/tasket/AppArmor-Profiles)
