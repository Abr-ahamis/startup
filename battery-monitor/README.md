# NEO Battery Monitor

NEO Battery Monitor reads Linux power-supply data from sysfs, listens for
charger changes with libudev, sends desktop notifications, and provides a
one-shot status line for the existing i3blocks battery block. It does not
replace the Sway bar's `i3blocks` status command.

## Installer support

`main.sh` builds and installs the monitor for the Debian, Ubuntu, Linux Mint,
Kali, Arch, and default package profiles. APT profiles install `cmake`, a C++
compiler, `pkg-config`, and `libudev-dev`; Arch installs `cmake`, `base-devel`,
`pkgconf`, and `systemd-libs`. These packages are build/runtime prerequisites;
the monitor does not start merely because it is installed.

The notifier starts only from `sway/.local/bin/startup-session.sh`, after it
confirms that the session has a Sway socket and is not the installer's preview.
The Sway-only wrapper stops the monitor when that Sway session ends. It is not
a systemd user service, because a user systemd manager can outlive Sway and be
shared by GNOME, KDE, or another desktop session. In other desktops, the
monitor remains inactive. The existing i3blocks battery block can still call
the monitor's one-shot `--status` mode when the Sway bar requests it.

## Build manually

For Debian-family distributions:

```sh
sudo apt update
sudo apt install build-essential cmake pkg-config libudev-dev libnotify-bin
```

For Arch:

```sh
sudo pacman -S --needed base-devel cmake pkgconf systemd-libs libnotify
```

Build and install for the current user:

```sh
cmake -S battery-monitor -B /tmp/neo-battery-monitor-build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/neo-battery-monitor-build --parallel
cmake --install /tmp/neo-battery-monitor-build --prefix "$HOME/.local"
```

Inspect the binary and laptop hardware:

```sh
"$HOME/.local/bin/neo-battery-monitor" --help
"$HOME/.local/bin/neo-battery-monitor" --check
```

Run the isolated hardware-reader test against fake sysfs data:

```sh
bash battery-monitor/tests/test-hardware.sh "$HOME/.local/bin/neo-battery-monitor"
```

To exercise the Sway session wrapper manually, run it from an actual Sway
terminal. It exits without starting anything outside Sway:

```sh
"$HOME/.local/bin/sway-battery-monitor.sh"
```

The wrapper is deployed by the installer to `~/.local/bin/` alongside the
monitor. Starting the binary directly is useful for `--check` and `--status`,
but the long-running notification mode should be launched by the Sway wrapper.

## Migrate from the old service

Running `main.sh` backs up and removes `battery-monitor.service`,
`neo-battery-monitor.service`, their default-target enablement links, and the
old `battery-monitor.sh` script. It does not leave either service enabled. To
stop an already-running older service immediately before running the installer:

```sh
systemctl --user disable --now neo-battery-monitor.service 2>/dev/null || true
systemctl --user disable --now battery-monitor.service 2>/dev/null || true
systemctl --user daemon-reload
```

## Commands

```text
neo-battery-monitor          Watch charger changes and notify (Sway wrapper only)
neo-battery-monitor --check  Print detected battery and power details
neo-battery-monitor --status Print one i3blocks Pango status line
neo-battery-monitor --help   Show usage
```

The event listener falls back to one-second refreshes if it cannot establish a
libudev listener. `--check` and `--status` can use a fixture directory by
setting `NEO_BATTERY_SYSFS_PATH`; the default is `/sys/class/power_supply`.
