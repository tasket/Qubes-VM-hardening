## Qubes VM hardening

Leverage Qubes template non-persistence to fend off malware at VM startup: Lock-down, quarantine and check contents of /rw private storage that affect the execution environment.


### vm-boot-protect.service
   * Acts at VM startup before private volume /rw mounts
   * User: Protect /home desktop & shell startup executables
   * Root: Quarantine all /rw configs & scripts, with whitelisting
   * Re-deploy custom or default files to /rw on each boot
   * SHA256 hash checking against unwanted changes
   * Provides rescue shell on error or request
   * Works with template-based AppVMs, sys-net and sys-vpn


### Installing

1. In a template VM, install the service files
   ```
   cd Qubes-VM-hardening
   sudo sh ./install
   ```

2. Activate by specifying one of the following Qubes services for your VM(s)...
   - `vm-boot-protect` - Protects executables/scripts within /home/user and may be used with wide array of Qubes VMs including standalone, appVMs, netVMs, Whonix, etc.
   - `vm-boot-protect-root` -  Protects /home/user as above, automatic /rw executable deactivation, whitelisting, checksumming, deployment. Works with appVMs, netVMs, etc. that are _template-based_.

   CAUTION: The -root option by default **removes** prior copies of /rw/config, /rw/usrlocal and /rw/bind-dirs. This can delete data!

3. Disable Qubes default passwordless-root. This is necessary for the above measures to work effectively...

   For Debian-based templates the installer will launch `configure-sudo-prompt` automatically to enable a sudo [yes/no prompt](https://www.qubes-os.org/doc/vm-sudo/#replacing-password-less-root-access-with-dom0-user-prompt) that appears in dom0. This handles the template configuration then displays several commands to manually configure dom0 (the dom0 step is required only once, regardless of how many templates you configure). You may test the `configure-sudo-prompt` script in a regular template-based appVM to see if it works, although the effect will be temporary.

   Alternately, you can uninstall the `qubes-core-agent-passwordless-root` package from the template. After doing this, you will have to use `qvm-run -u root` from dom0 to run any VM commands as root.
   
---

### Usage

   Operation is automatic and will result in either a normal boot process with full access to the private volume at /rw, or a rescue service mode providing an xterm shell and the private volume quarantined at /dev/badxvdb.

   At the `vm-boot-protect` level, certain executable files in /home will be made immutable so PATH and `alias` cannot be used to hijack commands like `su` and `sudo`, nor can impostor apps autostart whenever a VM starts. This can be added to virtually any Debian or Fedora VM and prevents unprivileged attacks from gaining persistence at startup. 

   At the `vm-boot-protect-root` level, the $privdirs paths will be renamed as backups, effectively removing them from the VM startup. Then whitelisting, hash/checksumming and deployment are done (if configured). This protects VM startup from attacks that had previously achieved privilege escalation.

   The special `vm-boot-protect-cli` level unconditionally runs an xterm rescue shell.


### Configuration

   Files can be added to /etc/default/vms in the template to enable the following features...

   **Hashes/Checksums** are checked in ../vms/vms.all.SHA and ../vms/$vmname.SHA files. File paths contained in them must be absolute, and references to '/home' must be prefixed with '/rw/'. Hashes in $vmname.SHA will override hashes specified for the same paths in vms.all.SHA. See also man page for `sha256sum -c`.

   **Whitelists** are checked in ../vms/vms.all.whitelist and ../vms/$vmname.whitelist files, and file paths contained in them must start with `/rw/`. A default is provided in ..vms/sys-net.whitelist to preserve Network Manager connections and sleep module list in sys-net.

   **Deployment** files are copied _recursively_ from ../vms/vms.all/rw/ and ../vms/$vmname/rw/ dirs. Example is to place the .bashrc file in /etc/default/vms/vms.all/rw/home/user/.bashrc for deployment to /rw/home/user/.bashrc. Once copying is complete,
the /etc/defaults/vms folder is deleted from the running VM (this has no effect on the original in the template).

### Where to use: Basic examples

After installing into a template, simply enable `vm-boot-protect-root` service without configuration. Recommended for the following types of VMs:
  * Service VMs: sys-usb and sys-net.
  * App VMs: untrusted, personal, banking, vault, etc. This assumes using regular Linux apps without tailored Qubes-specific settings in /rw such as *Firefox, Chromium, Thunderbird, KeePassX, office apps, media playback & editing*, etc. For these and many more, no configuration should be necessary.

Examples where `vm-boot-protect-root` requires configuration: sys-vpn (see Notes), Martus and Whonix (needs testing). Note that VMs sys-vpn and sys-firewall are fairly low-risk VMs so there may not be a compelling reason to use the service with them.

Examples where -root should *not* be enabled:
  * DispVMs. Sensible option is to enable sudo security for DispVM templates; service can be installed into template and left unused.
  * Whonix VMs. Plain `vm-boot-protect` is best used until Whonix persistence files can be mapped.
  * Standalone VMs. Plain `vm-boot-protect` makes more sense for these.
  * Non-Linux VMs (currently unsupported for any mode)


### Scope and Limitations

   The *vm-boot-protect* concept enhances the guest operating system's own defenses by using the *root volume non-persistence* provided by the Qubes template system; thus a relatively pristine startup state may be achieved if the *private* volume is brought online in a controlled manner. Protecting the init/autostart files should result in Qubes template-based VMs that boot 'cleanly' with much less chance of being affected by malware initially. Even if malware persists in a VM, it should be possible to run other apps and terminals without interference if the malware has not escalated to root (admittedly, a big 'if').

   Conversely, attacks which damage/exploit the Ext4 private filesystem itself or quickly re-exploit network vulnerabilities could conceivably still persist at startup. Further, repeated running of some apps such as Firefox, Chrome, LibreOffice, PDF viewers, online games, etc. may reactivate malware; this is not only because of the complexity of the formats handled by such apps, but also because of settings contained in javascript or which specify commands to be executed by the app. Therefore, setting apps to autostart can diminish protection of the startup environment.
   
   Note that as vulnerabilities are patched via system updates, malware that used those vulns to gain entry may cease to function without the kind of loopholes that *vm-boot-protect* closes.

### Notes

   * The service name has been changed from `vm-sudo-protect` in pre-release to `vm-boot-protect`. The install script will automatically try to disable the old service.

   * All the user-writable startup files in /home should be protected by the immutable flag; See issue #9 if you notice an omission or other problem. An extra step of disabling the flag using `sudo chattr -i` is required whenever the user wants to modify these startup files.

   * Adding /home or subdirs of it to $privdirs is possible. This would quarantine everything there to set the stage for applying whitelists on /home contents. The $privdirs variable can be changed via the service file, for example adding a .conf file in /lib/systemd/system/vm-boot-protect.d.

   * The sys-net VM should work 'out of the box' with the vm-boot-protect-root service via the included whitelist file. Additional network VMs may require configuration, such as `cp sys-net.whitelist sys-net2.whitelist`.
   
   * Using the -root service with a [VPN VM](https://github.com/tasket/Qubes-vpn-support) requires manual configuration in the template and can be approached different ways: Whitelist (optionally with SHA) can be made for the appropriate files. Alternately, all VPN configs can be added under /etc/default/vms/vmname/rw so they'll be automatically deployed.

   * Currently the service cannot seamlessly handle 'first boot' when the private volume must be initialized. If you enabled the service on a VM before its first startup, on first start the shell will display a notice telling you to restart the VM. Subsequent starts will proceed normally.
   
## Releases
   - v0.8.4  Add protection to /home/user/.config/systemd
   - v0.8.3  Fix for install script copying to /etc/default/vms
   - v0.8.2  Working rescue shell. Add sys-net whitelist, sudo config, fixes.
   - v0.8.0  Adds protection to /rw, file SHA checksums, whitelists, deployment
   - v0.2.0  Protects /home/user files and dirs


