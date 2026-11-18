#!/usr/bin/env bash
# Keep the battery notifier tied to a real Sway session, not the user's
# long-lived systemd manager (which may also serve GNOME or another desktop).
set -u

[[ -n "${SWAYSOCK:-}" && -S "$SWAYSOCK" ]] || exit 0
[[ "${STARTUP_SWAY_PREVIEW:-0}" != 1 ]] || exit 0

monitor="${HOME:?}/.local/bin/neo-battery-monitor"
[[ -x "$monitor" ]] || exit 0
command -v swaymsg >/dev/null 2>&1 || exit 0
command -v flock >/dev/null 2>&1 || exit 0
swaymsg -s "$SWAYSOCK" -t get_version >/dev/null 2>&1 || exit 0

runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[[ -d "$runtime" ]] || exit 0
exec 9>"$runtime/neo-battery-monitor.lock"
flock -n 9 || exit 0

"$monitor" >>"$runtime/neo-battery-monitor.log" 2>&1 &
monitor_pid=$!

stop_monitor() {
    if kill -0 "$monitor_pid" 2>/dev/null; then
        kill -TERM "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
    fi
}
trap stop_monitor EXIT INT TERM HUP

# Sway removes its IPC socket when the session exits. Check the socket path
# directly so this supervisor does not spawn a swaymsg process every second.
while kill -0 "$monitor_pid" 2>/dev/null && [[ -S "$SWAYSOCK" ]]; do
    sleep 2
done

exit 0
