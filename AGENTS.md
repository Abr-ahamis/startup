# Repository Guidelines

## Project Structure & Module Organization

`main.sh` is the installer entry point. Its ordered Bash modules live in `lib/`: distro detection, package mapping, user setup, managed configuration, services, security, and reporting. Shell checks are in `lib/test-*.sh`. Sway user configuration, launchers, bar blocks, and menus are under `sway/.config` and `sway/.local`; `scr/` contains standalone system utilities, `grub/` contains boot artwork helpers, and `wallpaper/` contains image assets. `KEYBINDINGS.md` documents desktop shortcuts.

## Build, Test, and Development Commands

There is no compilation or dependency build step. Run the installer with `sudo ./main.sh` only when you intend to make system and user configuration changes. Review its modules before execution; it installs packages and can change services or boot configuration.

Run the offline distro mapping check with `bash lib/test-distro-matrix.sh` (Arch, Debian, Ubuntu, and Kali). Run focused regression checks with `bash lib/test-regressions.sh`. Check shell syntax for edited scripts with `bash -n path/to/script.sh`. These checks do not replace reviewing effects on the target OS.

## Coding Style & Naming Conventions

Use Bash for installer and desktop scripts. Follow nearby code: four-space indentation in structured functions, descriptive `snake_case` function and variable names, quoted expansions, and `--` for paths passed to commands where supported. Prefer existing shared helpers in `lib/00-common.sh` for logging, privilege changes, target-user execution, and backups. Keep distro-specific package names and behavior centralized in `lib/10-distro.sh` and `lib/20-packages.sh`. No formatter or linter is configured; keep scripts readable and compatible with the supported Debian-family and Arch package managers.

## Testing Guidelines

Keep tests as executable or directly runnable shell scripts named `lib/test-*.sh`. Add offline checks for distro/package logic and focused regressions for installer behavior. Avoid tests that install packages or modify a real desktop unless they explicitly isolate and restore system state.

## Commit & Pull Request Guidelines

No established commit-message convention is available in the repository history. Use a short imperative summary, such as `Fix Debian Foot config validation`. Pull requests should describe the user-visible change, affected distributions and components, commands run, and any required manual deployment or system-level validation. Include screenshots only for visual desktop changes.

## Safety & Configuration

Treat installer execution as a privileged operation. Preserve unrelated user files, back up managed files before replacement, and do not remove distribution packages merely to work around version differences. Make new package mappings and OS-specific behavior explicit, and update relevant regression checks and shortcut documentation when behavior changes.
