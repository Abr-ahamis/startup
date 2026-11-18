
# Neo Startup

This repository installs the Sway desktop setup and its supporting tools on
Debian-family distributions and Arch Linux. Run `./main.sh` as the target user
or `sudo ./main.sh` when system-level changes are required. Review the modules
in `lib/` before running the installer; it manages packages, user
configuration, services, security settings, and boot artwork.

## Repository recovery

Before package discovery, the installer refreshes APT metadata. If that fails,
it checks the detected Debian, Kali, Ubuntu, or Linux Mint release and adds only
missing official repository entries to
`/etc/apt/sources.list.d/neo-startup-official.sources`, using that OS's
codename and archive keyring. It then retries `apt update` once. If required
packages are still absent from the indexes, it performs the same check and
refresh before reporting them unavailable. Existing APT source files,
including third-party sources, are preserved.

For Arch, package availability/install failures trigger a check for active
`core` and `extra` repositories and a mirror. Missing repository settings are
added to `/etc/pacman.conf` and `/etc/pacman.d/mirrorlist`, with backups under
the installer's backup directory. When package indexes are missing required
packages, the installer uses `pacman -Syu` to refresh them; Arch requires a
full system upgrade with a repository refresh. This recovery is conditional,
and the installer reports it in the system summary.

Automatic source templates are limited to the named distributions and use
their signed official archive keyrings. If the release codename or keyring is
missing, the installer preserves the existing repository setup and reports the
problem instead of guessing or mixing repositories from another OS.

## Proton VPN

After required packages are installed, the installer attempts Proton VPN for
each supported profile: Debian, Ubuntu, Linux Mint, and Kali use Proton's
Debian-family repository package; Arch uses `proton-vpn-gtk-app` from Extra.
The Debian-family repository download is retried up to three times and checked
against Proton's published SHA-256 checksum before installation. If Proton's
host cannot resolve or its repository cannot refresh, the installer reports a
warning and continues; it does not overwrite DNS settings or alter resolver
services. Proton documents Debian/Ubuntu setup [here](https://protonvpn.com/support/linux-vpn-debian-ubuntu),
Kali setup [here](https://protonvpn.com/support/official-linux-vpn-kali), and
Arch setup [here](https://protonvpn.com/support/linux-vpn-arch).

## Sway status refresh

The i3blocks bar keeps its existing block layout. CPU, RAM, and network speed
refresh every 0.7 seconds through a Sway-only signal timer because i3blocks
accepts whole-second intervals only. Wi-Fi, interface, and IP blocks refresh
when NetworkManager reports a change; Bluetooth refreshes on BlueZ D-Bus
signals; battery refreshes on kernel power-supply events. Network changes also
invalidate the public IP cache. Sway config reloads run `startup-session.sh`,
which signals the blocks to reread their current state. Slower changing values
such as disk usage, updates, and date/time retain slower intervals. The event
workers exit when their Sway session ends and do not run in other desktops.

## Guides
