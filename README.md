# Startup Linux setup

Portable Sway desktop setup for Debian, Ubuntu, Linux Mint, Kali Linux, and Arch Linux.

The only supported entry point is `main.sh`:

```sh
./main.sh
sudo ./main.sh
```

The unprivileged form explains when root privileges are required; the privileged
form detects the invoking desktop user and performs system and user operations in
the correct contexts. The installer detects the distribution from `/etc/os-release`,
maps each feature to its native package names, and installs user configuration into
the selected user's XDG directories. It does not accept command-line options.

The installer preserves existing configuration in protected, timestamped
`/var/backups/startup/` task directories and does not replace unrelated user files.
GRUB, package installation, user configuration, wallpapers, keyring, portals, and
Sway runtime validation are independent tasks; a task failure is recorded and the
remaining safe tasks continue. Optional application installers in `install/` are
not entry points and are not invoked directly by the installer.
.
