# Startup Linux setup

Portable Sway desktop setup for Debian, Ubuntu, Linux Mint, Kali Linux, and Arch Linux.

Run `sudo ./setup.sh`. The installer detects the
distribution from `/etc/os-release`, maps each feature to its native package names,
and installs user configuration into the selected user's XDG directories.

The installer preserves existing configuration in `/tmp/setup/installer-backups/` and
does not replace `/boot/grub` or distribution wallpapers. GRUB theming is explicitly
opt-in. Optional application installers live in `install/`; unsupported vendor flows
report an alternative instead of attempting an incompatible installation.
.
