# NEO Sway setup

NEO Sway setup adds this repository's Sway/Wayland configuration to an existing Linux installation. It does **not** replace, reinstall, upgrade, or otherwise take ownership of the operating system.

Supported distributions are Arch Linux, Debian, Ubuntu, and Kali Linux. Kali is handled as Debian-family while retaining its own `/etc/os-release` identity.

## Install

Run from the repository root:

```sh
./main.sh
```

The installer asks for sudo only when it must install packages. `sudo ./main.sh` is also supported: it uses `SUDO_USER` to put configuration in the invoking desktop user's home, not `/root`. A direct root shell must name the intended user explicitly:

```sh
STARTUP_TARGET_USER=alice ./main.sh
```

It reads `/etc/os-release`, validates the native package manager, and installs only missing packages. It never runs `apt upgrade`, `apt full-upgrade`, `apt dist-upgrade`, `pacman -Syu`, or any distribution upgrade.

If GRUB Customizer is absent from Ubuntu's package metadata, the installer adds only Ubuntu's `ppa:danielrichter2007/grub-customizer`, runs `apt-get update`, and retries. It never adds that PPA on Debian, Kali, or Arch. A PPA is third-party software: review its trust implications before running the installer.

## Existing desktops and TTYs

It is safe to run from GNOME, another desktop, a regular terminal, or a TTY such as `tty4`. A running desktop is reported and preserved. The installer neither removes nor changes GNOME, KDE, XFCE, other window managers, the display manager, NetworkManager's running service, or the current session. It does not start Sway, log out, or switch sessions.

No graphical environment variables are required. From a TTY, install normally and then run `sway` after installation, or log in through the existing display manager and select **Sway**.

## Installed packages

Package names are mapped by distro and checked in configured repositories. The only repository addition is the narrowly gated Ubuntu GRUB Customizer PPA described above; no generic repository or external installer is added. The list is intentionally driven by the files under `sway/`:

| Purpose | Debian / Ubuntu / Kali | Arch |
| --- | --- | --- |
| Sway session, bar, launcher, terminal | `sway swaybg swayidle swaylock i3blocks wofi foot dex gammastep` | same |
| Screenshots | `flameshot grim slurp` | same |
| Audio | `pipewire pipewire-pulse wireplumber pamixer` | same |
| Clipboard | `wl-clipboard cliphist` | same |
| Network applet used by the config | `network-manager network-manager-gnome` | `networkmanager network-manager-applet` |
| Bluetooth applet/tools | `bluez blueman rfkill` | `bluez bluez-utils blueman rfkill` |
| Portals/user bus | `xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk dbus-user-session` | `xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk dbus` |
| Notifications, fonts, helper scripts, keyring | `brightnessctl dunst libnotify-bin fontconfig jq curl gnome-keyring` | `brightnessctl dunst libnotify fontconfig jq curl gnome-keyring` |
| Requested extras | `grub-customizer timeshift` | `timeshift`; see Arch note below |

The NetworkManager packages provide `nmcli`/the applet required by the shipped configuration. The installer does not enable, disable, replace, or restart NetworkManager. If a core Sway package is unavailable, installation stops with its package name. If only the explicit Ubuntu GRUB Customizer extra is unavailable because Launchpad cannot be reached, it is reported and skipped so the Sway/Timeshift setup can complete.

It does **not** install browsers, Brave, VS Code, Telegram, Obsidian, ProtonVPN, RustScan, VirtualBox, Zen Browser, Node/npm, AI tools, Rust, Python development tools, pipx, autotiling, shell themes, or optional-app menus. GRUB Customizer is currently an AUR package on Arch, not an official `pacman` repository package. To avoid silently enabling/building unreviewed AUR code, the installer warns clearly on Arch and installs Timeshift; install the reviewed `grub-customizer` AUR package yourself if you want it there.

## Configuration and ownership

Project-owned configuration is installed for the target user only:

```text
~/.config/{sway,wofi,foot,i3blocks,flameshot,systemd/user/battery-monitor.service}
~/.local/bin/{battery-monitor.sh,brightness-control.sh,opacity.sh,startup-session.sh}
~/.config/sway/scripts/launch-app.sh
~/.local/share/{fonts/neo-setup,backgrounds/startup}
```

Each existing project path is moved to `~/.local/share/neo-setup/backups/<timestamp>/` before replacement. Unrelated files such as GNOME settings are untouched. The installer refuses symlinked destination paths and verifies ownership after copying. It does not write sudoers files, udev rules, `/etc/fstab`, bootloader configuration, or display-manager configuration.

The battery monitor unit is enabled for the target user's next systemd user session by a local `default.target.wants` symlink, but it is not started during installation. `startup-session.sh` does not launch a duplicate copy. PipeWire, portals, keyring, clipboard, and applets are likewise session components, not installer-managed system services.

## GRUB Customizer and Timeshift

`grub-customizer` and `timeshift` are the only extras. They are installed as packages only. The installer never runs GRUB Customizer, `update-grub`, `grub-install`, Timeshift, or any snapshot schedule. The files in `grub/` remain repository assets and are not copied into `/boot` or used automatically.

## Launch and troubleshoot

Log out and choose **Sway** in your current login manager, or run `sway` from a TTY. Sway's session file is supplied by the distro package; the login manager is not changed.

If package availability fails, enable the appropriate official repository in your distro's normal administration workflow and rerun. If configuration ownership is wrong, run the installer as the desktop user or with `sudo ./main.sh` from that user's shell. To inspect syntax without installing, run `bash -n main.sh lib/*.sh` and `bash -n` on the scripts under `sway/`. Run `bash lib/test-distro-matrix.sh` for an offline Arch/Debian/Ubuntu/Kali detection and package-family check.
