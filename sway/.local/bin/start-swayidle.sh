#!/usr/bin/env bash
# Start this Sway session's idle hooks, replacing stale hooks for this socket.
set -u

uid="$(id -u)"
home="${HOME:-$(getent passwd "$uid" | cut -d: -f6)}"
runtime="${XDG_RUNTIME_DIR:-/run/user/$uid}"
log_file="$runtime/startup-swayidle.log"

[[ -n "${SWAYSOCK:-}" && -n "${WAYLAND_DISPLAY:-}" ]] || exit 0
[[ "${STARTUP_SWAY_PREVIEW:-0}" != 1 ]] || exit 0
command -v swayidle >/dev/null 2>&1 || exit 0

# Sway's `exec` hooks are not rerun reliably on config reload. Match the
# compositor socket before stopping an old swayidle, so another Sway session
# belonging to this user is left alone.
while read -r pid; do
    [[ -r "/proc/$pid/environ" ]] || continue
    if tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -Fqx "SWAYSOCK=$SWAYSOCK"; then
        kill -TERM "$pid" 2>/dev/null || true
    fi
done < <(pgrep -u "$uid" -x swayidle 2>/dev/null || true)

sleep 0.1
mkdir -p -- "$runtime" 2>/dev/null || true
swayidle -w \
    timeout 1800 "$home/.local/bin/lock-screen.sh" \
    timeout 3600 'systemctl suspend' \
    before-sleep "$home/.local/bin/lock-screen.sh" \
    >>"$log_file" 2>&1 &
