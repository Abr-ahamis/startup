
# Neo Startup

This repository installs the Sway desktop setup and its supporting tools on
Debian-family distributions and Arch Linux. Run `./main.sh` as the target user
or `sudo ./main.sh` when system-level changes are required. Review the modules
in `lib/` before running the installer; it manages packages, user
configuration, services, security settings, and boot artwork.

## Guides

- [GTK lock screen setup](docs/gtklock.md): gtklock on Sway, wallpaper
  selection, sleep locking, configuration, and GNOME/GDM scope.
- [Keybindings](KEYBINDINGS.md): configured Sway and GNOME shortcuts.
- [Docker tools](scr/Docker/README.md): container utilities and examples.

## Development

Shell modules and utilities are Bash. Follow the existing module boundaries in
`lib/`, keep distribution-specific package behavior in `lib/20-packages.sh`,
and preserve existing user files. See `AGENTS.md` for repository contribution
and safety guidance.
