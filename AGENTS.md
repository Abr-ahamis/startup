# Repository Guidelines

## Project Structure & Module Organization

`main.sh` is the installer entry point. Its ordered Bash modules live in `lib/`: distro detection, package mapping, user setup, managed configuration, services, security, and reporting. Per-OS package profiles are in `lib/distros/`; shell checks are in `lib/test-*.sh`. Sway user configuration, launchers, bar blocks, and menus are under `sway/.config` and `sway/.local`; `scr/` contains standalone system utilities, `grub/` contains boot artwork helpers, and `wallpaper/` contains image assets. `KEYBINDINGS.md` documents desktop shortcuts.

## Build, Test, and Development Commands

There is no compilation or dependency build step. Run the installer with `sudo ./main.sh` only when you intend to make system and user configuration changes. Review its modules before execution; it installs packages and can change services or boot configuration.

Run the offline distro mapping check with `bash lib/test-distro-matrix.sh` (Arch, Debian, Ubuntu, Linux Mint, Kali, and an unlisted Ubuntu-derived fallback case). Run focused regression checks with `bash lib/test-regressions.sh`. Check shell syntax for edited scripts with `bash -n path/to/script.sh`. These checks do not replace reviewing effects on the target OS.

## Coding Style & Naming Conventions

Use Bash for installer and desktop scripts. Follow nearby code: four-space indentation in structured functions, descriptive `snake_case` function and variable names, quoted expansions, and `--` for paths passed to commands where supported. Prefer existing shared helpers in `lib/00-common.sh` for logging, privilege changes, target-user execution, and backups. Keep OS detection in `lib/10-distro.sh`, package install/verification mechanics in `lib/20-packages.sh`, and package lists in `lib/distros/`. No formatter or linter is configured; keep scripts readable and compatible with the supported Debian-family and Arch package managers.

## Distro Package Profiles

`lib/20-packages.sh` loads `lib/distros/<ID>.sh` using the exact `ID` from `/etc/os-release`. Current profiles are `debian.sh`, `ubuntu.sh`, `linuxmint.sh`, `kali.sh`, and `arch.sh`. Each profile owns its OS-specific `core` package list and can override other features through `distro_package_for`; delegate features without a real OS-specific difference to `default_distro_package_for`.

If no exact profile exists, `lib/distros/default.sh` supplies package mappings based on `DISTRO_FAMILY`. Distro detection uses `ID_LIKE` to identify Debian/Ubuntu-derived and Arch-derived systems, so an unlisted derivative uses the matching family defaults. Keep package names from one family out of another family’s profile. When adding or changing a profile, update `lib/test-distro-matrix.sh` to check profile selection, family-specific package names, and the fallback path; run both distro-matrix and regression checks.

`grub-customizer` is optional because it is absent from some supported APT repositories and the installer’s GRUB theme setup does not depend on it. Keep it out of required core package lists; attempt installation only when available.

## Testing Guidelines

Keep tests as executable or directly runnable shell scripts named `lib/test-*.sh`. Add offline checks for distro/package logic and focused regressions for installer behavior. Avoid tests that install packages or modify a real desktop unless they explicitly isolate and restore system state.

## Commit & Pull Request Guidelines

No established commit-message convention is available in the repository history. Use a short imperative summary, such as `Fix Debian Foot config validation`. Pull requests should describe the user-visible change, affected distributions and components, commands run, and any required manual deployment or system-level validation. Include screenshots only for visual desktop changes.

## Safety & Configuration

Treat installer execution as a privileged operation. Preserve unrelated user files, back up managed files before replacement, and do not remove distribution packages merely to work around version differences. Make new package mappings and OS-specific behavior explicit, and update relevant regression checks and shortcut documentation when behavior changes.
