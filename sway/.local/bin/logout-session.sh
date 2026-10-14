#!/usr/bin/env bash
# End a Sway session started by GDM so GDM can show its login screen again.
# Never request administrator authorization from this user-facing action.
set -euo pipefail

notify_user() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send 'Log out' "$1" >/dev/null 2>&1 || true
    fi
    printf '%s\n' "$1" >&2
}

if [[ -z "${SWAYSOCK:-}" || -z "${WAYLAND_DISPLAY:-}" ]] \
    || ! command -v swaymsg >/dev/null 2>&1 \
    || ! swaymsg -t get_version >/dev/null 2>&1; then
    notify_user 'Logout was cancelled: no active Sway session was detected.'
    exit 1
fi

session_id="${XDG_SESSION_ID:-}"
if [[ -z "$session_id" ]] \
    || ! loginctl show-session "$session_id" -p Name --value 2>/dev/null \
        | grep -qxF "${USER:-$(id -un)}"; then
    notify_user 'Logout was cancelled: could not identify this login session.'
    exit 1
fi

display_manager="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
case "$display_manager" in
    */gdm.service|*/gdm3.service) ;;
    *)
        notify_user 'Logout was cancelled: GDM is not selected as the display manager.'
        exit 1
        ;;
esac

session_service="$(loginctl show-session "$session_id" -p Service --value 2>/dev/null || true)"
if [[ "$session_service" == gdm* ]]; then
    # GDM owns this session and returns to its greeter when Sway exits.
    exec swaymsg exit
fi

# A Sway session launched directly from a TTY is not managed by GDM. Starting
# the system display manager or terminating the logind session needs elevated
# privileges, so fail safely instead of prompting at logout or returning the
# user to an unexpected shell. Starting Sway from GDM makes logout passwordless.
notify_user 'This Sway session was started from a terminal, not GDM. It is still running. Log out of this session, then choose Sway from the GDM session menu to enable password-free logout to the GDM login screen.'
exit 1
