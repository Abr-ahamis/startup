# Repository Guidelines

## Project Structure & Module Organization

`main.sh` is the installer entry point. Its ordered Bash modules live in `lib/`: distro detection, package mapping, user setup, managed configuration, services, security, and reporting. Per-OS package profiles are in `lib/distros/`; shell checks are in `lib/test-*.sh`. The standalone C++17 battery monitor is in `battery-monitor/` and includes its CMake build, hardware check, and i3blocks status mode. Sway user configuration, launchers, bar blocks, and menus are under `sway/.config` and `sway/.local`; `scr/` contains standalone system utilities, `grub/` contains boot artwork helpers, and `wallpaper/` contains image assets. `KEYBINDINGS.md` documents desktop shortcuts.

## Build, Test, and Development Commands

The installer builds and installs the battery monitor for supported APT and pacman profiles using CMake, a C++17 compiler, pkg-config, and libudev development files. Run the installer with `sudo ./main.sh` only when you intend to make system and user configuration changes. Review its modules before execution; it installs packages and can change services or boot configuration.

Run the offline distro mapping check with `bash lib/test-distro-matrix.sh` (Arch, Debian, Ubuntu, Linux Mint, Kali, and an unlisted Ubuntu-derived fallback case). Run focused regression checks with `bash lib/test-regressions.sh`. After building the battery monitor, run `bash battery-monitor/tests/test-hardware.sh "$HOME/.local/bin/neo-battery-monitor"`; this test uses a fake sysfs tree. Check shell syntax for edited scripts with `bash -n path/to/script.sh`. These checks do not replace reviewing effects on the target OS.

## Coding Style & Naming Conventions

Use Bash for installer and desktop scripts. Follow nearby code: four-space indentation in structured functions, descriptive `snake_case` function and variable names, quoted expansions, and `--` for paths passed to commands where supported. Prefer existing shared helpers in `lib/00-common.sh` for logging, privilege changes, target-user execution, and backups. Keep OS detection in `lib/10-distro.sh`, package install/verification mechanics in `lib/20-packages.sh`, and package lists in `lib/distros/`. No formatter or linter is configured; keep scripts readable and compatible with the supported Debian-family and Arch package managers.

## Distro Package Profiles

`lib/20-packages.sh` loads `lib/distros/<ID>.sh` using the exact `ID` from `/etc/os-release`. Current profiles are `debian.sh`, `ubuntu.sh`, `linuxmint.sh`, `kali.sh`, and `arch.sh`. Each profile owns its OS-specific `core` package list and can override other features through `distro_package_for`; delegate features without a real OS-specific difference to `default_distro_package_for`.

If no exact profile exists, `lib/distros/default.sh` supplies package mappings based on `DISTRO_FAMILY`. Distro detection uses `ID_LIKE` to identify Debian/Ubuntu-derived and Arch-derived systems, so an unlisted derivative uses the matching family defaults. Keep package names from one family out of another family’s profile. When adding or changing a profile, update `lib/test-distro-matrix.sh` to check profile selection, family-specific package names, and the fallback path; run both distro-matrix and regression checks.

Repository recovery lives in `lib/20-packages.sh`. Keep APT source templates scoped by exact `DISTRO_ID`, release codenames, and that distribution's archive keyring; never write sources from one distro into another. Add only missing official entries in the managed `neo-startup-official.sources` file and leave vendor/third-party sources unchanged. Arch repair backs up and fills only missing `core`/`extra` and mirror settings; use a full `pacman -Syu` when repository indexes must be refreshed, never a standalone `pacman -Sy`. Extend `lib/test-regressions.sh` with isolated fixture tests for each repository template and idempotence.

`grub-customizer` is optional because it is absent from some supported APT repositories and the installer's GRUB theme setup does not depend on it. Keep it out of required core package lists; attempt installation only when available.

Proton VPN is installed as an optional package stage after required packages. `distro_package_for protonvpn` maps Debian-family systems to Proton's official `proton-vpn-gnome-desktop` APT package and Arch to `proton-vpn-gtk-app` in Extra. Debian-family setup downloads Proton's repository package only after DNS resolution succeeds, retries a bounded number of times, verifies the documented SHA-256 checksum, and never changes `/etc/resolv.conf` or resolver services. DNS/network failures are warnings and must not make the main OS setup fail. Keep Proton's version/checksum aligned with Proton's official install page and test DNS failure offline.

The C++ battery monitor is built for supported APT and pacman profiles. It must run only inside Sway: `startup-session.sh` launches `sway-battery-monitor.sh` only with a live `SWAYSOCK`, and that wrapper stops the monitor when its Sway IPC socket exits. Never enable a user systemd service for the monitor, since the user manager may also serve GNOME or another desktop. `lib/70-services.sh` backs up and removes both legacy and prior C++ user units plus the old shell script. Keep the existing `i3blocks` bar command; `sway/.config/i3blocks/scripts/bar/battery.sh` calls `neo-battery-monitor --status` when available and retains a sysfs display fallback. Do not replace the whole bar status command with the monitor, because that would remove the other i3blocks. When changing build support, update every OS profile and the distro matrix tests.

Sway status refresh policy is defined in `sway/.config/i3blocks/config` and the two Sway-only helpers `refresh-fast-status.sh` and `monitor-status-events.sh`. CPU, RAM, and network speed use i3blocks real-time signal 12, sent every 0.7 seconds; other dynamic blocks use one-shot intervals and NetworkManager, BlueZ D-Bus, or power-supply udev events. `startup-session.sh` sends the configured status signals after a Sway start or reload. i3blocks intervals accept whole seconds only, so do not put fractional values in the config. Keep block signal numbers synchronized with these scripts and the regression checks.

## Testing Guidelines

Keep tests as executable or directly runnable shell scripts named `lib/test-*.sh`. Add offline checks for distro/package logic and focused regressions for installer behavior. Avoid tests that install packages or modify a real desktop unless they explicitly isolate and restore system state.

## Commit & Pull Request Guidelines

No established commit-message convention is available in the repository history. Use a short imperative summary, such as `Fix Debian Foot config validation`. Pull requests should describe the user-visible change, affected distributions and components, commands run, and any required manual deployment or system-level validation. Include screenshots only for visual desktop changes.

## Safety & Configuration

Treat installer execution as a privileged operation. Preserve unrelated user files, back up managed files before replacement, and do not remove distribution packages merely to work around version differences. Make new package mappings and OS-specific behavior explicit, and update relevant regression checks and shortcut documentation when behavior changes.
