## Qubes VM hardening

Leverage Qubes template non-persistence to fend off malware at VM startup: Lock-down, quarantine and check contents of /rw private storage that affect the execution environment.


### vm-boot-protect.service
   * Acts at VM startup before private volume /rw mounts
   * User: Protect /home desktop & shell startup executables
   * Root: Quarantine all /rw configs & scripts, with whitelisting
   * Organize configurations with named tags
   * Deploy trusted custom files to /rw on each boot
   * SHA256 hash checking against unwanted changes
   * Provides rescue shell on error or request
   * Works with template-based AppVMs, sys-net and sys-vpn


### Installing

1. In a template VM, install the service files
   ```
   cd Qubes-VM-hardening
   sudo bash install
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

   Files can be added to /etc/default/vms in the template to configure the following `vm-boot-protect-root` features...

   **Hashes/Checksums** are checked in ../vms/vms.all.SHA and ../vms/$vmname.SHA files. File paths contained in them must be absolute, and references to '/home' must be prefixed with '/rw/'. Hashes in $vmname.SHA will override hashes specified for the same paths in vms.all.SHA. See also man page for `sha256sum -c`.

   **Whitelists** are checked in ../vms/vms.all.whitelist and ../vms/$vmname.whitelist files, and file paths contained in them must start with `/rw/`. A default is provided in ..vms/sys-net.whitelist to preserve Network Manager connections and sleep module list in sys-net.

   **Deployment** files are copied _recursively_ from ../vms/vms.all/rw/ and ../vms/$vmname/rw/ dirs. Example is to place the .bashrc file in /etc/default/vms/vms.all/rw/home/user/.bashrc for deployment to /rw/home/user/.bashrc. Once copying is complete,
the /etc/defaults/vms folder is deleted from the running VM (this has no effect on the original in the template).

   **rc files** are sh script fragments sourced from ../vms/vms.all.rc and ../vms/$vmname.rc. They run near the beginning of the vm-boot-protect service before mounting /rw, and can be used to override variable definitions like `privdirs` as well as the `vm_boot_finish` function which runs near the end before dismount. Another use for rc files is to run threat detection tools such as antivirus.

   **Tags:** Any of the above configs may be defined as tags so that you are not limited to specifying them for either all VMs or specifically-named VMs. Simply configure them as you would acccording to the above directions, but place the files under the '@tags' subdir instead. For example '/etc/default/vms/@tags/special.whitelist' defines a whitelist for the tag 'special'. A tag can be activated for one or more VMs by adding a Qubes service prefixed with `vm-boot-tag-` (i.e. vm-boot-tag-special) to the VMs. Also, multiple tags may be activated for a VM.

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

### Example tags

Some useful configurations have been supplied in /etc/default/vms:

  * vm-boot-tag-network: Contains a whitelist for Network Manager connections and the module blacklist which is often used with network interfaces in Qubes. By default, this config also activates for any VM named 'sys-net'.
  * vm-boot-tag-qhome: Quarantines /home in addition to the /rw system dirs. Useful for 'sys-usb' and DispVM-like functionality.
  * vm-boot-tag-noqbackup: Deletes all quarantined files that are not whitelisted.
  * vm-boot-tag-ibrowse: Preserves Firefox bookmarks while quarantining the /home folder. [Currently](https://github.com/tasket/Qubes-VM-hardening/issues/39) works with Firefox ESR. See Notes below.
  * vm-boot-wiperw: Completely wipe and reformat the /rw partition.

  
### Scope and Limitations

   The *vm-boot-protect* concept enhances the guest operating system's own defenses by using the *root volume non-persistence* provided by the Qubes template system; thus a relatively pristine startup state may be achieved if the *private* volume is brought online in a controlled manner. Protecting the init/autostart files should result in Qubes template-based VMs that boot 'cleanly' with much less chance of being affected by malware initially. Even if malware persists in a VM, it should be possible to run other apps and terminals without interference if the malware has not escalated to root (admittedly, a big 'if').

   Conversely, attacks which damage/exploit the Ext4 private filesystem itself or quickly re-exploit network vulnerabilities could conceivably still persist at startup. Further, repeated running of complex apps, games, and programming environments may reactivate malware; this is because of the complexity of the formats and settings handled by such apps. Therefore, setting apps to autostart can diminish protection of the startup environment.

   Note that as system and app vulnerabilities are patched via system updates, malware that used those vulns to gain entry may cease to function without the kind of loopholes that *vm-boot-protect* closes.

   Efficient template re-use is another aspect of using *vm-boot-protect-root* features, since a single template can be customized for various roles. However, note that some customizations may not be appropriate to run during VM startup.

### Notes

   * The /rw/home directory can be added to `privdirs` so it is quarantined much like the other /rw dirs. The easiest way to configure this is to define `privdirs_add=/rw/home` in an rc file; see 'qhome.rc' for an exmaple.

   * The ibrowse tag works with Firefox versions up to 66 and uses a generic profile named 'profile.default'. If you wish to carry over existing bookmarks for use with ibrowse, rename the current profile folder in '.mozilla/firefox' to 'profile.default' before enabling the ibrowse tag.

   * A bug in v0.8.4 will erase anything in '/etc/default/vms' when booting into the template. For proper
   future operation with sys-net or other VMs you may have customized in that path, updating Qubes-VM-hardening
   to the latest version (using the install script) is recommended, along with restoring any custom files
   in '/etc/default/vms'. Thanks to Daniel Moerner for submitting the patch!

   * All the user-writable startup files in /home should be protected by the immutable flag; See issue #9 if you notice an omission or other problem. An extra step of disabling the flag using `sudo chattr -i` is required whenever the user wants to modify these startup files.

   * The sys-net VM should work 'out of the box' with the vm-boot-protect-root service via the included whitelist file. Additional network VMs may require configuration, such as `cp sys-net.whitelist sys-net2.whitelist`.
   
   * Using the -root service with a [VPN VM](https://github.com/tasket/Qubes-vpn-support) requires manual configuration in the template and can be approached different ways: Whitelist (optionally with SHA) can be made for the appropriate files. Alternately, all VPN configs can be added under /etc/default/vms/vmname/rw so they'll be automatically deployed.

   * Currently the service cannot seamlessly handle 'first boot' when the private volume must be initialized. If you enabled the service on a VM before its first startup, on first start the shell will display a notice telling you to restart the VM. Subsequent starts will proceed normally.

   * The service can be removed from the system with `cd Qubes-VM-hardening; sudo bash install --uninstall`

## Releases
   - v0.9.3  Protect against suid and device nodes
   - v0.9.2  Fix vm-boot-protect mode
   - v0.9.1  Optimized, fix rc order, new "wiperw" tag
   - v0.9.0  Add tags and rc files, protect more home scripts, reinitialize home
   - v0.8.5  Fix template detection, /etc/default/vms erasure
   - v0.8.4  Add protection to /home/user/.config/systemd
   - v0.8.3  Fix for install script copying to /etc/default/vms
   - v0.8.2  Working rescue shell. Add sys-net whitelist, sudo config, fixes.
   - v0.8.0  Adds protection to /rw, file SHA checksums, whitelists, deployment
   - v0.2.0  Protects /home/user files and dirs
