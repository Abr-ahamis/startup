#!/usr/bin/env bash
# Start Sway helpers from one repeat-safe, readable entry point.
set -u

uid="$(id -u)"
home="${HOME:-$(getent passwd "$(id -un)" | cut -d: -f6)}"
runtime="${XDG_RUNTIME_DIR:-/tmp}"
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

command -v dbus-update-activation-environment >/dev/null 2>&1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway || true
command -v systemctl >/dev/null 2>&1 && systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP || true

autotiling="$home/.local/bin/autotiling"
autotiling_venv="$home/.local/share/pipx/venvs/autotiling/bin/autotiling"
autotiling_system="$(command -v autotiling 2>/dev/null || true)"
if [[ ! -x "$autotiling" && -x "$autotiling_venv" ]]; then
  mkdir -p "$home/.local/bin" 2>/dev/null || true
  ln -sfn "$autotiling_venv" "$autotiling" 2>/dev/null || true
fi
if [[ -x "$autotiling" ]]; then
  pgrep -u "$uid" -x autotiling >/dev/null 2>&1 || "$autotiling" >/dev/null 2>&1 &
elif [[ -x "$autotiling_venv" ]]; then
  pgrep -u "$uid" -x autotiling >/dev/null 2>&1 || "$autotiling_venv" >/dev/null 2>&1 &
elif [[ -x "$autotiling_system" ]]; then
  pgrep -u "$uid" -x autotiling >/dev/null 2>&1 || "$autotiling_system" >/dev/null 2>&1 &
fi

start_process nm-applet nm-applet
start_process blueman-applet blueman-applet
start_process dunst dunst
start_process gammastep gammastep -O 4500
start_process dex dex --autostart --environment sway
start_script "$home/.local/bin/terminal.sh"
start_script "$home/.local/bin/opacity.sh"
start_script "$home/.local/bin/battery-monitor.sh"

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

if command -v gnome-keyring-daemon >/dev/null 2>&1 && ! pgrep -u "$uid" -x gnome-keyring-daemon >/dev/null 2>&1; then
  eval "$(gnome-keyring-daemon --start --components=secrets,ssh,pkcs11 2>/dev/null)" || true
  export GNOME_KEYRING_CONTROL GNOME_KEYRING_PID SSH_AUTH_SOCK
fi
