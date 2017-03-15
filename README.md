# Qubes-VM-hardening
Files for enhancing Qubes VM security and privacy

## rc.local: Protect sh and bash init files

Placed in /etc/rc.local of a template VM, this makes the shell init files immutable so PATH and alias cannot be used to hijack commands like su and sudo. I combed the dash and bash docs to address all the user-writable files. Feel free to comment or create issue if you see an omission or other problem.

 
 
 
------

 
## See also:

[Enabling dom0 prompt for sudo](https://www.qubes-os.org/doc/vm-sudo/#replacing-password-less-root-access-with-dom0-user-prompt)

[AppArmor Profiles](https://github.com/tasket/AppArmor-Profiles)
