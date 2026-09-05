#!/usr/bin/env bash
# Toggle a fixed, GeoClue-free Night Light adjustment for the active Sway user.
set -u

command -v gammastep >/dev/null 2>&1 || exit 127
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
state_file="$runtime_dir/startup-night-light-${UID:-user}"

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send 'Night Light' "$1" || true
}

if [[ "$(<"$state_file" 2>/dev/null || true)" == 1 ]]; then
  gammastep -x >/dev/null 2>&1 || exit 1
  printf '0\n' >"$state_file"
  notify 'Off'
else
  gammastep -m wayland -O 4500 >/dev/null 2>&1 || exit 1
  printf '1\n' >"$state_file"
  notify 'On (4500K)'
fi
