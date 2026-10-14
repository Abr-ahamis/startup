#!/usr/bin/env bash
# End the current Sway login session only after the GDM greeter is available.
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
if [[ -z "$session_id" ]] || ! loginctl show-session "$session_id" -p Name --value 2>/dev/null | grep -qxF "${USER:-$(id -un)}"; then
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
if [[ "$session_service" == gdm* ]] && systemctl is-active --quiet display-manager.service; then
    # GDM started this session and will restore its greeter when the session ends.
    exec swaymsg exit
fi

# Sway can be launched directly from a TTY, outside GDM. In that case, obtain
# authorization before switching VTs, start GDM, activate its greeter, and
# terminate the TTY session as one privileged operation. The fixed command
# body receives only the validated logind session ID as an argument.
command -v pkexec >/dev/null 2>&1 || {
    notify_user 'Logout was cancelled: authorization is needed to start GDM from this TTY session.'
    exit 1
}
[[ "$session_id" =~ ^[[:alnum:]_.:-]+$ ]] || {
    notify_user 'Logout was cancelled: the login session ID is invalid.'
    exit 1
}

read -r -d '' root_logout_command <<'ROOT_COMMAND' || true
session_id="$1"
systemctl start display-manager.service || exit 1
i=0
while [ "$i" -lt 40 ]; do
    for candidate in $(loginctl list-sessions --no-legend --no-pager | awk '$6 == "greeter" {print $1}'); do
        greeter_class="$(loginctl show-session "$candidate" -p Class --value 2>/dev/null || true)"
        greeter_service="$(loginctl show-session "$candidate" -p Service --value 2>/dev/null || true)"
        if [ "$greeter_class" = greeter ] && [ "${greeter_service#gdm}" != "$greeter_service" ]; then
            loginctl activate "$candidate" || exit 1
            loginctl terminate-session "$session_id"
            exit $?
        fi
    done
    sleep 0.5
    i=$((i + 1))
done
exit 1
ROOT_COMMAND

if ! pkexec /usr/bin/sh -c "$root_logout_command" startup-gdm-logout "$session_id"; then
    notify_user 'Logout was cancelled: GDM could not be made ready. Sway is still running.'
    exit 1
fi
