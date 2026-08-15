#!/usr/bin/env bash

# Sway / XDG Desktop Portal repair helper.
#
# Purpose:
#   - Install a Sway-specific portal configuration.
#   - Keep the configuration entirely per-user.
#   - Never use sudo/root.
#   - Never modify the generic portals.conf.
#   - Avoid unnecessary writes and backups.
#   - Detect the exact filesystem operation that fails.
#   - Work correctly when Sway is active or when the script is run
#     from another desktop/session.
#
# Usage:
#   ./fix-sway-portals.sh setup
#   ./fix-sway-portals.sh restart
#   ./fix-sway-portals.sh status
#   ./fix-sway-portals.sh remove

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

info() {
    printf '[INFO] %s\n' "$*"
}

ok() {
    printf '[ OK ] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

error() {
    printf '[ERROR] %s\n' "$*" >&2
}

die() {
    error "$*"
    exit 1
}

# ---------------------------------------------------------------------------
# Root / identity protection
# ---------------------------------------------------------------------------

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    die "Do not run $SCRIPT_NAME with sudo or as root."
fi

if [[ -z "${HOME:-}" ]]; then
    die "\$HOME is not set."
fi

if [[ ! -d "$HOME" ]]; then
    die "HOME does not exist: $HOME"
fi

CURRENT_UID="$(id -u)"
CURRENT_USER="$(id -un 2>/dev/null || printf 'unknown')"

# ---------------------------------------------------------------------------
# XDG paths
# ---------------------------------------------------------------------------

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-"$HOME/.config"}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-"$HOME/.cache"}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-"/run/user/$CURRENT_UID"}"

CFG_DIR="$XDG_CONFIG_HOME/xdg-desktop-portal"
SWAY_PORTALS="$CFG_DIR/sway-portals.conf"
CACHE_DIR="$XDG_CACHE_HOME/xdg-desktop-portal"

# Optional legacy Sway config marker.
SWAY_CFG="$XDG_CONFIG_HOME/sway/config"

# ---------------------------------------------------------------------------
# Safety checks
# ---------------------------------------------------------------------------

check_home_owner() {
    local owner_uid

    if ! owner_uid="$(stat -c '%u' -- "$HOME" 2>/dev/null)"; then
        warn "Unable to determine ownership of HOME: $HOME"
        return 1
    fi

    if [[ "$owner_uid" != "$CURRENT_UID" ]]; then
        error "HOME is not owned by the current user."
        error "HOME : $HOME"
        error "Owner: UID $owner_uid"
        error "User : $CURRENT_USER / UID $CURRENT_UID"
        return 1
    fi

    return 0
}

check_parent_writable() {
    local directory="$1"

    if [[ ! -d "$directory" ]]; then
        return 0
    fi

    if [[ ! -w "$directory" || ! -x "$directory" ]]; then
        error "Directory is not writable/searchable:"
        error "  $directory"
        error "Check with:"
        error "  ls -ld \"$directory\""
        error "  namei -l \"$directory\""
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Portal configuration
# ---------------------------------------------------------------------------

portal_content() {
    cat <<'EOF'
[preferred]
default=gtk
org.freedesktop.impl.portal.Screenshot=wlr
org.freedesktop.impl.portal.ScreenCast=wlr
EOF
}

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

backup_if_changed() {
    local path="$1"
    local backup

    [[ -e "$path" || -L "$path" ]] || return 0

    if [[ -L "$path" ]]; then
        error "Refusing to modify a symlink:"
        error "  $path"
        return 1
    fi

    backup="${path}.bak.$(date +'%Y%m%d-%H%M%S')"

    if ! cp -a -- "$path" "$backup"; then
        error "Failed to create backup:"
        error "  $backup"
        return 1
    fi

    info "Backup created: $backup"
    return 0
}

# ---------------------------------------------------------------------------
# Safe atomic file writer
# ---------------------------------------------------------------------------

write_if_changed() {
    local path="$1"
    local directory
    local temp

    directory="$(dirname -- "$path")"

    if [[ ! -d "$directory" ]]; then
        if ! mkdir -p -- "$directory"; then
            error "Cannot create directory:"
            error "  $directory"
            return 1
        fi
    fi

    # Configuration directories should not be world-accessible.
    if ! chmod 700 -- "$directory" 2>/dev/null; then
        warn "Could not set 700 permissions on:"
        warn "  $directory"
    fi

    if ! check_parent_writable "$directory"; then
        return 1
    fi

    # Explicitly test creation of the temporary file.
    if ! temp="$(mktemp "$directory/.portal.XXXXXX" 2>/dev/null)"; then
        error "Cannot create temporary file in:"
        error "  $directory"
        error "This is a filesystem/permission problem, not a Sway problem."
        error "Check:"
        error "  ls -ld \"$directory\""
        error "  namei -l \"$path\""
        return 1
    fi

    # Private configuration file.
    if ! chmod 600 -- "$temp"; then
        rm -f -- "$temp"
        error "Cannot set permissions on temporary file:"
        error "  $temp"
        return 1
    fi

    # Write the actual content.
    if ! portal_content >"$temp"; then
        rm -f -- "$temp"
        error "Cannot write temporary portal configuration:"
        error "  $temp"
        return 1
    fi

    # No change: avoid backup and replacement.
    if [[ -f "$path" ]] && cmp -s -- "$temp" "$path"; then
        rm -f -- "$temp"
        return 0
    fi

    if [[ -e "$path" || -L "$path" ]]; then
        if ! backup_if_changed "$path"; then
            rm -f -- "$temp"
            return 1
        fi
    fi

    # Atomic replacement.
    if ! mv -f -- "$temp" "$path"; then
        rm -f -- "$temp"
        error "Cannot replace portal configuration:"
        error "  $path"
        error "Check:"
        error "  ls -ld \"$directory\""
        error "  namei -l \"$path\""
        return 1
    fi

    # Final permission enforcement.
    if ! chmod 600 -- "$path"; then
        warn "Could not set 600 permissions on:"
        warn "  $path"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Sway detection
# ---------------------------------------------------------------------------

find_sway_socket() {
    local socket

    [[ -d "$XDG_RUNTIME_DIR" ]] || return 1

    for socket in "$XDG_RUNTIME_DIR"/sway-ipc."$CURRENT_UID".*.sock; do
        [[ -S "$socket" ]] || continue

        if command -v swaymsg >/dev/null 2>&1; then
            if SWAYSOCK="$socket" swaymsg -t get_version >/dev/null 2>&1; then
                printf '%s\n' "$socket"
                return 0
            fi
        fi
    done

    return 1
}

sway_session_active() {
    local socket

    socket="$(find_sway_socket 2>/dev/null)" || return 1

    export SWAYSOCK="$socket"
    return 0
}

# ---------------------------------------------------------------------------
# User D-Bus / systemd detection
# ---------------------------------------------------------------------------

have_user_bus() {
    [[ -S "$XDG_RUNTIME_DIR/bus" ]] || return 1

    command -v systemctl >/dev/null 2>&1 || return 1

    systemctl --user show-environment >/dev/null 2>&1
}

refresh_user_environment() {
    if ! have_user_bus; then
        warn "No active user D-Bus/systemd session was found."
        warn "Configuration will still be repaired."
        warn "Portal services will not be restarted from this shell."
        return 1
    fi

    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        dbus-update-activation-environment \
            --systemd \
            XDG_CURRENT_DESKTOP \
            XDG_SESSION_DESKTOP \
            XDG_SESSION_TYPE \
            WAYLAND_DISPLAY \
            DISPLAY \
            XDG_CURRENT_DESKTOP \
            >/dev/null 2>&1 || true
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Service helpers
# ---------------------------------------------------------------------------

restart_user_service() {
    local service="$1"

    if ! systemctl --user reset-failed "$service" >/dev/null 2>&1; then
        :
    fi

    if command -v timeout >/dev/null 2>&1; then
        timeout 10s systemctl --user restart "$service"
    else
        systemctl --user restart "$service"
    fi
}

restart_services() {
    if ! have_user_bus; then
        warn "Skipping portal service restart: no active user session."
        return 2
    fi

    refresh_user_environment || true

    if ! restart_user_service xdg-desktop-portal.service; then
        error "Failed to restart xdg-desktop-portal.service"
        return 1
    fi

    if sway_session_active; then
        if systemctl --user cat xdg-desktop-portal-wlr.service \
            >/dev/null 2>&1; then

            if ! restart_user_service xdg-desktop-portal-wlr.service; then
                error "Failed to restart xdg-desktop-portal-wlr.service"
                return 1
            fi
        else
            warn "xdg-desktop-portal-wlr.service is not installed."
            warn "Install the xdg-desktop-portal-wlr package."
        fi
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

print_service_status() {
    local service="$1"
    local state

    state="$(systemctl --user is-active "$service" 2>/dev/null || true)"

    printf '%-45s %s\n' "$service" "${state:-unknown}"

    [[ "$state" == "active" ]]
}

status_check() {
    local result=0

    printf '%-45s %s\n' "Portal configuration" \
        "$([[ -f "$SWAY_PORTALS" ]] && printf 'present' || printf 'missing')"

    if [[ -f "$SWAY_PORTALS" ]]; then
        printf '%s\n' "---------------------------------------------"
        cat -- "$SWAY_PORTALS"
    fi

    printf '\n'

    if sway_session_active; then
        ok "Sway session detected"
        printf 'SWAYSOCK=%s\n' "${SWAYSOCK:-unknown}"
    else
        info "No active Sway IPC session detected"
    fi

    printf '\n'

    if ! have_user_bus; then
        warn "No active user D-Bus/systemd session."
        return 2
    fi

    print_service_status xdg-desktop-portal.service || result=1

    if sway_session_active; then
        if systemctl --user cat xdg-desktop-portal-wlr.service \
            >/dev/null 2>&1; then
            print_service_status xdg-desktop-portal-wlr.service || result=1
        else
            warn "xdg-desktop-portal-wlr.service is not installed."
            result=1
        fi
    fi

    return "$result"
}

# ---------------------------------------------------------------------------
# Remove obsolete Sway shell block
# ---------------------------------------------------------------------------

remove_legacy_sway_block() {
    local temp

    [[ -f "$SWAY_CFG" ]] || return 0

    # Only touch the file if our exact markers exist.
    grep -q '^# fix-sway-portals start$' "$SWAY_CFG" || return 0
    grep -q '^# fix-sway-portals end$' "$SWAY_CFG" || return 0

    if ! temp="$(mktemp "${SWAY_CFG}.XXXXXX" 2>/dev/null)"; then
        error "Cannot create temporary Sway config."
        return 1
    fi

    if ! awk '
        /^# fix-sway-portals start$/ {
            skip=1
            next
        }

        /^# fix-sway-portals end$/ {
            skip=0
            next
        }

        !skip {
            print
        }
    ' "$SWAY_CFG" >"$temp"; then
        rm -f -- "$temp"
        error "Failed to remove legacy Sway portal block."
        return 1
    fi

    if ! cmp -s -- "$temp" "$SWAY_CFG"; then
        if ! backup_if_changed "$SWAY_CFG"; then
            rm -f -- "$temp"
            return 1
        fi

        if ! mv -f -- "$temp" "$SWAY_CFG"; then
            rm -f -- "$temp"
            error "Failed to update Sway config."
            return 1
        fi

        info "Removed obsolete portal commands from Sway config."
    else
        rm -f -- "$temp"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------

clear_cache() {
    [[ -e "$CACHE_DIR" ]] || return 0

    if ! rm -rf -- "$CACHE_DIR"; then
        warn "Could not remove portal cache:"
        warn "  $CACHE_DIR"
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Main setup
# ---------------------------------------------------------------------------

setup() {
    local restart_result=0

    if ! check_home_owner; then
        return 1
    fi

    info "User      : $CURRENT_USER"
    info "UID       : $CURRENT_UID"
    info "HOME      : $HOME"
    info "Config    : $XDG_CONFIG_HOME"
    info "Portal dir: $CFG_DIR"
    printf '\n'

    # Ensure ~/.config is usable.
    if ! mkdir -p -- "$XDG_CONFIG_HOME"; then
        error "Cannot create XDG config directory:"
        error "  $XDG_CONFIG_HOME"
        return 1
    fi

    if ! chmod 700 -- "$XDG_CONFIG_HOME" 2>/dev/null; then
        warn "Could not enforce 700 permissions on:"
        warn "  $XDG_CONFIG_HOME"
    fi

    if ! write_if_changed "$SWAY_PORTALS"; then
        error "Sway portal configuration could not be written."
        return 1
    fi

    ok "Sway portal configuration is current:"
    printf '     %s\n' "$SWAY_PORTALS"

    if ! remove_legacy_sway_block; then
        return 1
    fi

    if ! clear_cache; then
        warn "Portal cache cleanup was incomplete."
    fi

    printf '\n'

    restart_services || restart_result=$?

    printf '\n'

    case "$restart_result" in
        0)
            ok "Portal services restarted."
            ;;
        2)
            warn "Portal configuration was repaired, but no user session was available."
            ;;
        *)
            warn "Portal configuration was repaired, but service restart failed."
            ;;
    esac

    printf '\n'

    # A service restart failure should not erase a successful configuration
    # repair. Verify configuration independently.
    if [[ -f "$SWAY_PORTALS" ]] &&
       cmp -s <(portal_content) "$SWAY_PORTALS"; then
        ok "Final configuration verified."
    else
        error "Final configuration verification failed."
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Restart only
# ---------------------------------------------------------------------------

restart_only() {
    if ! clear_cache; then
        warn "Portal cache cleanup failed."
    fi

    if restart_services; then
        ok "Portal services restarted."
        return 0
    fi

    warn "Portal services could not be fully restarted."
    return 1
}

# ---------------------------------------------------------------------------
# Remove configuration
# ---------------------------------------------------------------------------

remove_config() {
    local removed=0

    if [[ -L "$SWAY_PORTALS" ]]; then
        warn "Refusing to remove symlink:"
        warn "  $SWAY_PORTALS"
        return 1
    fi

    if [[ -f "$SWAY_PORTALS" ]]; then
        if ! backup_if_changed "$SWAY_PORTALS"; then
            return 1
        fi

        if ! rm -f -- "$SWAY_PORTALS"; then
            error "Failed to remove:"
            error "  $SWAY_PORTALS"
            return 1
        fi

        removed=1
        info "Removed $SWAY_PORTALS"
    fi

    if [[ -d "$CFG_DIR" ]]; then
        if rmdir --ignore-fail-on-non-empty "$CFG_DIR" 2>/dev/null; then
            :
        fi
    fi

    if clear_cache; then
        :
    fi

    if [[ "$removed" -eq 0 ]]; then
        info "No Sway portal configuration was installed."
    else
        ok "Sway portal configuration removed."
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------

ACTION="${1:-setup}"

case "$ACTION" in
    setup)
        setup
        exit $?
        ;;

    restart)
        restart_only
        exit $?
        ;;

    status)
        status_check
        exit $?
        ;;

    remove)
        remove_config
        exit $?
        ;;

    start)
        restart_only
        exit $?
        ;;

    *)
        cat >&2 <<EOF
Usage:
    $SCRIPT_NAME setup
    $SCRIPT_NAME restart
    $SCRIPT_NAME status
    $SCRIPT_NAME remove

Examples:
    ./$SCRIPT_NAME setup
    ./$SCRIPT_NAME restart
    ./$SCRIPT_NAME status
    ./$SCRIPT_NAME remove
EOF
        exit 2
        ;;
esac