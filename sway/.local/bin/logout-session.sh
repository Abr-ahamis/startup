#!/usr/bin/env bash
# End a Sway session started by GDM so GDM can show its login screen again.
# The installer grants this helper one narrowly scoped passwordless action so
# logout stays inside the desktop and never opens a terminal password prompt.
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

# For TTY-started Sway, use the fixed root-owned helper installed by the
# installer. sudo -n guarantees that a missing permission never opens a
# terminal or password dialog from this keybinding/menu action.
root_helper=/usr/local/libexec/startup-gdm-logout
systemctl_path=/usr/bin/systemctl
if [[ ! -x "$root_helper" || ! -x "$systemctl_path" ]] || ! command -v sudo >/dev/null 2>&1; then
    notify_user 'GDM logout is not configured. Run the installer to install its restricted GDM logout permission.'
    exit 1
fi
if ! sudo -n -- "$systemctl_path" start display-manager.service; then
    notify_user 'Could not start GDM without a password prompt. Sway is still running; run the installer to configure password-free logout.'
    exit 1
fi
if ! sudo -n -- "$root_helper" "$session_id"; then
    notify_user 'Could not switch to the GDM login screen. Sway is still running; check the installer log or run the GDM setup again.'
    exit 1
fi
