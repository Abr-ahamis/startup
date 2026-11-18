#!/usr/bin/env bash
# Refresh CPU, RAM, and network speed blocks at 0.7-second intervals in Sway.
set -u

[[ -n "${SWAYSOCK:-}" && -S "$SWAYSOCK" ]] || exit 0
[[ "${STARTUP_SWAY_PREVIEW:-0}" != 1 ]] || exit 0
command -v swaymsg >/dev/null 2>&1 || exit 0
command -v pkill >/dev/null 2>&1 || exit 0
swaymsg -s "$SWAYSOCK" -t get_version >/dev/null 2>&1 || exit 0

uid="${UID:-$(id -u)}"
runtime="${XDG_RUNTIME_DIR:-/run/user/$uid}"
[[ -d "$runtime" ]] || exit 0
exec 9>"$runtime/startup-fast-status-$uid.lock" || exit 0
flock -n 9 || exit 0

while [[ -S "$SWAYSOCK" ]]; do
  sleep 0.7
  [[ -S "$SWAYSOCK" ]] || break
  pkill -RTMIN+12 -u "$uid" -x i3blocks 2>/dev/null || true
done
