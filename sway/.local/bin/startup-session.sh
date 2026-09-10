#!/usr/bin/env bash
# Start Sway helpers from one repeat-safe, readable entry point.
set -u

uid="$(id -u)"
home="${HOME:-$(getent passwd "$(id -un)" | cut -d: -f6)}"
runtime="${XDG_RUNTIME_DIR:-/run/user/$uid}"
[[ -d "$runtime" ]] || runtime="${XDG_RUNTIME_DIR:-/tmp}"
export XDG_RUNTIME_DIR="$runtime"
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "$runtime/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus"
fi
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-sway}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-sway}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
log_file="$runtime/startup-sway-session.log"
mkdir -p "$runtime" 2>/dev/null || true
exec >>"$log_file" 2>&1

start_process() {
  local process="$1"; shift
  command -v "$1" >/dev/null 2>&1 || return 0
  pgrep -u "$uid" -x "$process" >/dev/null 2>&1 && return 0
  "$@" >/dev/null 2>&1 &
}

start_script() {
  local script="$1"
  [[ -x "$script" ]] || return 0
  pgrep -u "$uid" -f -- "$script" >/dev/null 2>&1 || "$script" >/dev/null 2>&1 &
}

# Do not allow distro-provided Gammastep desktop entries to start in the Sway
# session.  Their default GeoClue location provider is commonly denied and
# produces repeated errors on systems without enabled location services.
# A per-user Hidden override follows the XDG autostart specification and leaves
# the vendor entry untouched. Night Light remains an explicit user action in
# the brightness menu.
disable_gammastep_autostart() {
  local config_home="${XDG_CONFIG_HOME:-$home/.config}" entry name override
  local -a autostart_dirs=(/etc/xdg/autostart /usr/share/xdg/autostart)
  for entry in "${autostart_dirs[@]}"/*; do
    [[ -f "$entry" ]] || continue
    name="$(basename -- "$entry")"
    [[ "${name,,}" == *gammastep*.desktop ]] || \
      grep -Eiq '^[[:space:]]*Exec=.*gammastep([[:space:]]|$)' "$entry" || continue
    override="$config_home/autostart/$name"
    mkdir -p "$(dirname -- "$override")" 2>/dev/null || continue
    printf '[Desktop Entry]\nHidden=true\n' >"$override" 2>/dev/null || true
  done
}

command -v dbus-update-activation-environment >/dev/null 2>&1 && dbus-update-activation-environment --systemd DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway || true
command -v systemctl >/dev/null 2>&1 && systemctl --user import-environment DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR WAYLAND_DISPLAY XDG_CURRENT_DESKTOP || true

disable_gammastep_autostart

# Start only in a real Sway session, never in another desktop or in the
# installer's nested preview. Explicit Wayland/manual-temperature mode means
# Gammastep never asks GeoClue for location access.
if [[ -n "${SWAYSOCK:-}" && -n "${WAYLAND_DISPLAY:-}" && "${STARTUP_SWAY_PREVIEW:-0}" != 1 ]]; then
  # Stop only this user's stale automatic Gammastep process before starting
  # the managed Sway instance.
  pkill -u "$uid" -x gammastep >/dev/null 2>&1 || true
  start_process gammastep gammastep -m wayland -O 4500
  printf '1\n' >"$runtime/startup-night-light-$uid" 2>/dev/null || true
fi

start_process nm-applet nm-applet
start_process blueman-applet blueman-applet
start_process dunst dunst
start_process dex dex --autostart --environment sway
start_script "$home/.local/bin/opacity.sh"
# battery-monitor.service is enabled as a target-user unit by the installer;
# do not launch a second copy from the session script.

if command -v wl-paste >/dev/null 2>&1 && command -v cliphist >/dev/null 2>&1; then
  pgrep -u "$uid" -f 'wl-paste.*cliphist store' >/dev/null 2>&1 || wl-paste --type text --watch cliphist store >/dev/null 2>&1 &
fi

if command -v swaybg >/dev/null 2>&1; then
  pkill -u "$uid" -x swaybg 2>/dev/null || true
  image=""
  for candidate in "$home/.local/share/backgrounds/startup/IMG1.jpg" "$home/.local/share/backgrounds/startup/IMG2.jpg"; do
    [[ -f "$candidate" ]] && { image="$candidate"; break; }
  done
  if [[ -z "$image" ]]; then
    for root in "$home/.local/share/backgrounds" /usr/share/backgrounds/gnome /usr/share/backgrounds; do
      [[ -d "$root" ]] || continue
      image="$(find "$root" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.jxl' \) -print -quit 2>/dev/null)"
      [[ -n "$image" ]] && break
    done
  fi
  [[ -n "$image" ]] && swaybg -i "$image" -m fill >/dev/null 2>&1 &
fi

# Ask the target user's D-Bus session to activate Secret Service first. This
# works in Sway without requiring GNOME Shell and avoids duplicate daemons.
secret_service=0
if [[ -S "${XDG_RUNTIME_DIR:-}/bus" ]] && command -v busctl >/dev/null 2>&1; then
  timeout --foreground 5s busctl --user --no-pager status org.freedesktop.secrets >/dev/null 2>&1 && secret_service=1
  if (( secret_service == 0 )); then
    timeout --foreground 5s busctl --user call \
      org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus \
      StartServiceByName su org.freedesktop.secrets 0 >/dev/null 2>&1 || true
    timeout --foreground 5s busctl --user --no-pager status org.freedesktop.secrets >/dev/null 2>&1 && secret_service=1
  fi
fi
if command -v gnome-keyring-daemon >/dev/null 2>&1 && (( secret_service == 0 )) && ! pgrep -u "$uid" -f 'gnome-keyring-daemon|gnome-keyring-d' >/dev/null 2>&1; then
  keyring_env="$(timeout --foreground 5s gnome-keyring-daemon --start --components=secrets,ssh,pkcs11 2>/dev/null || true)"
  [[ -z "$keyring_env" ]] || eval "$keyring_env"
  export GNOME_KEYRING_CONTROL GNOME_KEYRING_PID SSH_AUTH_SOCK
  command -v dbus-update-activation-environment >/dev/null 2>&1 && \
    dbus-update-activation-environment --systemd GNOME_KEYRING_CONTROL SSH_AUTH_SOCK >/dev/null 2>&1 || true
fi
