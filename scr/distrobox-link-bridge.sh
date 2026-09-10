#!/usr/bin/env bash
# Neo Distrobox Link Bridge v8.2.0
#
# Host-side, idempotent bridge for Distrobox GUI applications:
#   Guest -> Host : http/https -> host's REAL default browser
#   Host -> Guest : non-standard x-scheme-handler/<scheme> -> guest app
#
# The script is deliberately conservative:
#   * never claims host http/https for a Distrobox
#   * never edits host shell startup files
#   * never requires an interactive distrobox-enter for preflight
#   * --remove never starts/enters/stops the container
#   * reruns remove this bridge's previous files first, with rollback backup
#   * failed runs restore the previous bridge configuration
#   * tests never launch a real browser or GUI application
#
# Usage:
#   ./distrobox-link-bridge.sh
#   ./distrobox-link-bridge.sh --test
#   ./distrobox-link-bridge.sh --list
#   ./distrobox-link-bridge.sh --remove [BOX]
#   ./distrobox-link-bridge.sh --rollback RUN_ID

set -uo pipefail
IFS=$'\n\t'
shopt -s nullglob

BRIDGE_VERSION="8.3.0"
SCRIPT_PATH="$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/neo-distrobox-link-bridge"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/neo-distrobox-link-bridge"
HOST_APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
HOST_BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
BACKUP_ROOT="$STATE_DIR/backups"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$RUN_ID"
LOG_FILE="$STATE_DIR/run-$RUN_ID.log"
MANIFEST="$BACKUP_DIR/manifest.tsv"
ENV_BACKUP="$BACKUP_DIR/container-env.tsv"
LOCK_DIR="$STATE_DIR/.lock"
TMP_DIR="$STATE_DIR/tmp-$RUN_ID"
HOST_SPAWN_BASE_URL="https://github.com/1player/host-spawn/releases/latest/download"

SETUP_SUCCESS=0
ROLLBACK_ACTIVE=1
BOX=""
ENGINE=""
WEB_ENABLED=0
REGISTER_SCHEMES="n"
HOST_EXEC_OK=0
PERSISTENT_ENV_OK=0
TEST_FAIL=0
HOST_OPENER=""
HOST_OPENER_KIND=""
HOST_DEFAULT_BROWSER=""
DISTROBOX_BIN=""
HOST_ID="unknown"
HOST_NAME="Linux"
HOST_PM="unknown"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

have() { command -v "$1" >/dev/null 2>&1; }
info() { printf '%b[INFO]%b %s\n' "$BLUE" "$RESET" "$*"; }
ok() { printf '%b[ OK ]%b %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$*"; }
err() { printf '%b[ERR ]%b %s\n' "$RED" "$RESET" "$*" >&2; }
section() { printf '\n%b==== %s ====%b\n' "$CYAN" "$*" "$RESET"; }

safe_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
}

safe_scheme() {
    [[ "${1:-}" =~ ^[a-z][a-z0-9+.-]*$ ]]
}

host_owned_scheme() {
    case "${1:-}" in
        http|https|file|ftp|ftps|mailto|tel|sms|callto|irc|ircs|news|nntp|gopher|data|urn|about)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

run_timeout() {
    local duration="$1"
    shift
    if have timeout; then
        timeout "$duration" "$@"
    else
        "$@"
    fi
}

cleanup_temp() {
    rm -rf -- "$TMP_DIR" 2>/dev/null || true
}

cleanup_lock() {
    rm -rf -- "$LOCK_DIR" 2>/dev/null || true
}

backup_file() {
    local file="$1" rel
    [[ -e "$file" || -L "$file" ]] || return 0
    if awk -F '\t' -v p="$file" '$2==p {found=1} END{exit !found}' "$MANIFEST" 2>/dev/null; then
        return 0
    fi
    if [[ "$file" == "$HOME"/* ]]; then
        rel="${file#"$HOME/"}"
    else
        rel="host/$(basename -- "$file")"
    fi
    mkdir -p "$BACKUP_DIR/$(dirname -- "$rel")" || return 1
    cp -a -- "$file" "$BACKUP_DIR/$rel" || return 1
    printf 'BACKUP\t%s\t%s\n' "$file" "$rel" >> "$MANIFEST"
}

mark_new() {
    local file="$1"
    if ! [[ -e "$file" || -L "$file" ]]; then
        if ! awk -F '\t' -v p="$file" '$2==p {found=1} END{exit !found}' "$MANIFEST" 2>/dev/null; then
            printf 'NEW\t%s\t\n' "$file" >> "$MANIFEST"
        fi
    fi
}

remove_file() {
    local file="$1"
    [[ -e "$file" || -L "$file" ]] || return 0
    backup_file "$file" || return 1
    rm -rf -- "$file"
}

restore_manifest() {
    local manifest_file="$1" source_dir="$2"
    local kind path rel
    local -a lines=()
    [[ -f "$manifest_file" ]] || return 0
    mapfile -t lines < "$manifest_file"
    for (( idx=${#lines[@]}-1; idx>=0; idx-- )); do
        IFS=$'\t' read -r kind path rel <<< "${lines[$idx]}"
        [[ -n "$kind" && -n "$path" ]] || continue
        case "$kind" in
            BACKUP)
                [[ -e "$source_dir/$rel" || -L "$source_dir/$rel" ]] || continue
                mkdir -p "$(dirname -- "$path")" || continue
                rm -rf -- "$path" 2>/dev/null || true
                cp -a -- "$source_dir/$rel" "$path" 2>/dev/null || true
                ;;
            NEW)
                rm -rf -- "$path" 2>/dev/null || true
                ;;
        esac
    done
}

restore_current_run() {
    restore_manifest "$MANIFEST" "$BACKUP_DIR"

    if [[ -s "$ENV_BACKUP" && "$ENGINE" == podman ]] && have podman; then
        local box key had old
        while IFS=$'\t' read -r box key had old; do
            [[ -n "$box" && -n "$key" ]] || continue
            if [[ "$had" == 1 ]]; then
                podman update --env "${key}=${old}" "$box" >/dev/null 2>&1 || true
            else
                podman update --unsetenv "$key" "$box" >/dev/null 2>&1 || true
            fi
        done < "$ENV_BACKUP"
    fi

    have update-desktop-database && update-desktop-database "$HOST_APP_DIR" >/dev/null 2>&1 || true
}

abort_setup() {
    err "$*"
    err "Restoring the previous bridge configuration."
    restore_current_run
    ROLLBACK_ACTIVE=0
    err "Log: $LOG_FILE"
    err "Backups: $BACKUP_DIR"
    exit 1
}

on_interrupt() {
    warn "Interrupted."
    if (( SETUP_SUCCESS == 0 && ROLLBACK_ACTIVE == 1 )); then
        restore_current_run
    fi
    cleanup_temp
    cleanup_lock
    exit 130
}

on_exit() {
    local rc=$?
    if (( SETUP_SUCCESS == 0 && ROLLBACK_ACTIVE == 1 )); then
        restore_current_run
    fi
    cleanup_temp
    cleanup_lock
    exit "$rc"
}

static_test() {
    section "Neo Distrobox Link Bridge v$BRIDGE_VERSION - Static Self-Test"
    local failures=0 cmd

    if bash -n "$SCRIPT_PATH" >/dev/null 2>&1; then ok "Shell syntax: PASS"; else warn "Shell syntax: FAIL"; failures=$((failures+1)); fi

    for cmd in awk sed grep find mktemp tee sort tr cut head tail timeout readlink; do
        if have "$cmd"; then ok "$cmd: PASS"; else warn "$cmd: MISSING"; failures=$((failures+1)); fi
    done

    if grep -Ev '^[[:space:]]*#' "$SCRIPT_PATH" | grep -Eq '(^|[;&|])[[:space:]]*timeout[[:space:]]+[^[:space:]]+[[:space:]]+container_exec_'; then
        warn "Function timeout misuse guard: FAIL"
        failures=$((failures+1))
    else
        ok "Function timeout misuse guard: PASS"
    fi

    if grep -Eq 'name[[:space:]]*==[[:space:]]*"NAME"' "$SCRIPT_PATH"; then
        ok "Distrobox header filtering: PASS"
    else
        warn "Distrobox header filtering: FAIL"
        failures=$((failures+1))
    fi

    if grep -Fq '/usr/bin/xdg-open' "$SCRIPT_PATH" && grep -Fq 'never use a user-local wrapper' "$SCRIPT_PATH"; then
        ok "Host system xdg-open preference: PASS"
    else
        warn "Host system xdg-open preference: FAIL"
        failures=$((failures+1))
    fi

    if grep -Fq 'http|https' "$SCRIPT_PATH" && grep -Fq 'host_owned_scheme' "$SCRIPT_PATH"; then
        ok "Host HTTP/HTTPS protection: PASS"
    else
        warn "Host HTTP/HTTPS protection: FAIL"
        failures=$((failures+1))
    fi

    if grep -Fq -- '--remove' "$SCRIPT_PATH" && grep -Fq 'never starts' "$SCRIPT_PATH"; then
        ok "Fast remove-mode guard: PASS"
    else
        warn "Fast remove-mode guard: FAIL"
        failures=$((failures+1))
    fi

    if have distrobox; then ok "Distrobox CLI: detected"; else warn "Distrobox CLI: MISSING"; failures=$((failures+1)); fi
    have podman && ok "Podman: detected" || true
    have docker && ok "Docker: detected" || true
    have xdg-open && ok "xdg-open: detected" || true
    have gio && ok "gio: detected" || true

    if (( failures == 0 )); then
        ok "Static self-test passed. No integration changes were made."
        return 0
    fi
    warn "$failures static test failure(s)."
    return 1
}

# Parse control-only arguments before creating a persistent run lock.
case "${1:-}" in
    --test|-test|--self-test)
        static_test
        exit $?
        ;;
    --help|-h)
        cat <<USAGE
Neo Distrobox Link Bridge v$BRIDGE_VERSION

Usage:
  $0                       Configure a selected Distrobox
  $0 --test                Static self-test only
  $0 --list                List Distrobox containers
  $0 --remove [BOX]        Remove only Neo link integration
  $0 --rollback RUN_ID     Restore a previous run
USAGE
        exit 0
        ;;
esac

mkdir -p "$STATE_DIR" "$DATA_DIR" "$HOST_APP_DIR" "$HOST_BIN_DIR" "$BACKUP_ROOT" "$BACKUP_DIR" "$TMP_DIR" || {
    printf '[ERR ] Cannot create bridge state directories.\n' >&2
    exit 1
}
: > "$MANIFEST"
: > "$ENV_BACKUP"
exec > >(tee -a "$LOG_FILE") 2>&1

# Refuse execution from inside a container.
if [[ -n "${CONTAINER_ID:-}" || -f /.dockerenv || -f /run/.containerenv ]]; then
    err "This script must run on the Linux host, not inside a container."
    exit 1
fi

# Host detection.
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    HOST_ID="${ID:-unknown}"
    HOST_NAME="${PRETTY_NAME:-$HOST_ID}"
fi

if have pacman; then HOST_PM="pacman"
elif have apt-get; then HOST_PM="apt"
elif have dnf; then HOST_PM="dnf"
elif have zypper; then HOST_PM="zypper"
elif have apk; then HOST_PM="apk"
elif have xbps-install; then HOST_PM="xbps"
fi

DISTROBOX_BIN="$(command -v distrobox 2>/dev/null || true)"
if [[ -z "$DISTROBOX_BIN" ]]; then
    err "Distrobox is not installed on this host."
    exit 127
fi

section "Neo Distrobox Link Bridge v$BRIDGE_VERSION"
info "Host: $HOST_NAME"
info "Package manager: $HOST_PM"
info "State: $STATE_DIR"
info "Log: $LOG_FILE"
info "Backup: $BACKUP_DIR"

# Stale-safe lock.
acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$LOCK_DIR/pid"
        return 0
    fi
    local pid=""
    [[ -f "$LOCK_DIR/pid" ]] && pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        err "Another Neo Distrobox Link Bridge process is already running (PID $pid)."
        return 1
    fi
    warn "Removing stale bridge lock."
    rm -rf -- "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || return 1
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
}

acquire_lock || exit 1
trap on_interrupt INT TERM
trap on_exit EXIT

# Host URL opener: prefer the real system xdg-open, never the user's old
# Distrobox wrapper under ~/.local/bin. Fall back to gio/kde-open when needed.
host_system_opener() {
    local candidate
    for candidate in /usr/bin/xdg-open /bin/xdg-open /usr/local/bin/xdg-open; do
        [[ -x "$candidate" ]] || continue
        if ! grep -Eq 'distrobox-host-exec|neo-distrobox|neo-hackerai' "$candidate" 2>/dev/null; then
            printf '%s\t%s\n' "$candidate" xdg
            return 0
        fi
    done
    for candidate in /usr/bin/gio /bin/gio /usr/local/bin/gio; do
        if [[ -x "$candidate" ]]; then
            printf '%s\t%s\n' "$candidate" gio
            return 0
        fi
    done
    for candidate in /usr/bin/kde-open6 /usr/bin/kde-open5 /bin/kde-open6 /bin/kde-open5; do
        if [[ -x "$candidate" ]]; then
            printf '%s\t%s\n' "$candidate" kde
            return 0
        fi
    done
    return 1
}

host_default_browser_id() {
    local xdg_settings=""
    for xdg_settings in /usr/bin/xdg-settings /bin/xdg-settings /usr/local/bin/xdg-settings; do
        [[ -x "$xdg_settings" ]] || continue
        local value=""
        value="$($xdg_settings get default-web-browser 2>/dev/null || true)"
        [[ -n "$value" ]] && { printf '%s\n' "$value"; return 0; }
    done
    if have xdg-mime; then
        xdg-mime query default x-scheme-handler/http 2>/dev/null || true
    elif [[ -x /usr/bin/gio ]]; then
        /usr/bin/gio mime x-scheme-handler/http 2>/dev/null | sed -n 's/^Default application for .*: //p' | head -n1
    fi
}

host_opener_line="$(host_system_opener 2>/dev/null || true)"
if [[ -n "$host_opener_line" ]]; then
    IFS=$'\t' read -r HOST_OPENER HOST_OPENER_KIND <<< "$host_opener_line"
else
    warn "No safe host URL opener was found; attempting xdg-utils installation."
    case "$HOST_PM" in
        pacman) have sudo && sudo pacman -S --needed --noconfirm xdg-utils >/dev/null 2>&1 || true ;;
        apt) have sudo && sudo apt-get install -y xdg-utils >/dev/null 2>&1 || true ;;
        dnf) have sudo && sudo dnf install -y xdg-utils >/dev/null 2>&1 || true ;;
        zypper) have sudo && sudo zypper --non-interactive install xdg-utils >/dev/null 2>&1 || true ;;
        apk) have sudo && sudo apk add --no-cache xdg-utils >/dev/null 2>&1 || true ;;
        xbps) have sudo && sudo xbps-install -Sy xdg-utils >/dev/null 2>&1 || true ;;
    esac
    host_opener_line="$(host_system_opener 2>/dev/null || true)"
    if [[ -n "$host_opener_line" ]]; then
        IFS=$'\t' read -r HOST_OPENER HOST_OPENER_KIND <<< "$host_opener_line"
    fi
fi

HOST_DEFAULT_BROWSER="$(host_default_browser_id 2>/dev/null || true)"
info "Host URL opener: ${HOST_OPENER:-none} (${HOST_OPENER_KIND:-none})"
info "Host default browser: ${HOST_DEFAULT_BROWSER:-system default/unknown}"

# Distrobox discovery: parse the table's NAME column only. This prevents the
# literal header "NAME" from ever becoming a selectable box.
parse_distrobox_list() {
    local output="" alt=""
    output="$($DISTROBOX_BIN list --no-color 2>/dev/null || true)"
    local parsed=""
    parsed="$(printf '%s\n' "$output" | awk -F '|' '
        NF >= 2 {
            id=$1; name=$2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
            if (id == "ID" || name == "NAME" || name == "") next
            if (name ~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/) print name
        }
    ' | awk 'NF && !seen[$0]++')"
    if [[ -n "$parsed" ]]; then
        printf '%s\n' "$parsed"
        return 0
    fi

    # Fallback for systems shipping distrobox-list separately.
    if have distrobox-list; then
        alt="$(distrobox-list --no-color 2>/dev/null || distrobox-list 2>/dev/null || true)"
        printf '%s\n' "$alt" | awk -F '|' '
            NF >= 2 {
                id=$1; name=$2
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
                if (id == "ID" || name == "NAME" || name == "") next
                if (name ~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/) print name
            }
        ' | awk 'NF && !seen[$0]++'
    fi
}

mapfile -t BOXES < <(parse_distrobox_list)
if (( ${#BOXES[@]} == 0 )); then
    err "No Distrobox containers detected."
    err "Create one first, for example: distrobox create --name mybox --image debian:13"
    exit 1
fi

# Final discovery guard: the table header itself must never be selectable.
for c in "${BOXES[@]}"; do
    if [[ "$c" == "NAME" || "$c" == "ID" || "$c" == "STATUS" || "$c" == "IMAGE" ]]; then
        err "Distrobox discovery returned a header token ($c); refusing unsafe selection."
        exit 1
    fi
done

printf 'Detected Distrobox containers:\n'
for i in "${!BOXES[@]}"; do
    printf '  %d) %s\n' "$((i+1))" "${BOXES[$i]}"
done

if [[ "${1:-}" == "--list" ]]; then
    SETUP_SUCCESS=1
    exit 0
fi

if [[ "${1:-}" == "--remove" && -n "${2:-}" ]]; then
    requested="$2"
    safe_name "$requested" || { err "Invalid box name: $requested"; exit 2; }
    for c in "${BOXES[@]}"; do
        [[ "$c" == "$requested" ]] && BOX="$requested"
    done
    [[ -n "$BOX" ]] || { err "Distrobox '$requested' not found."; exit 1; }
elif [[ "${1:-}" == "--remove" ]]; then
    while :; do
        read -r -p "Choose the Distrobox to remove link integration from [1-${#BOXES[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#BOXES[@]} )); then
            BOX="${BOXES[$((choice-1))]}"
            break
        fi
        warn "Invalid selection."
    done
else
    while :; do
        read -r -p "Choose the Distrobox to integrate [1-${#BOXES[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#BOXES[@]} )); then
            BOX="${BOXES[$((choice-1))]}"
            break
        fi
        warn "Invalid selection."
    done
fi

info "Selected box: $BOX"

BOX_ROOT="$DATA_DIR/$BOX"
GUEST_BIN_DIR="$BOX_ROOT/bin"
GUEST_DATA_DIR="$BOX_ROOT/data"
GUEST_CONFIG_DIR="$BOX_ROOT/config"
GUEST_APP_DIR="$GUEST_DATA_DIR/applications"
GUEST_MIMEAPPS="$GUEST_CONFIG_DIR/mimeapps.list"
GUEST_WEB_HELPER="$GUEST_BIN_DIR/neo-distrobox-open"
GUEST_XDG_WRAPPER="$GUEST_BIN_DIR/xdg-open"
GUEST_URI_HELPER="$GUEST_BIN_DIR/neo-distrobox-uri-dispatch"
GUEST_WEB_DESKTOP="$GUEST_APP_DIR/neo-distrobox-host-browser.desktop"
GUEST_HANDLER_MAP="$BOX_ROOT/handler-map.tsv"
HOST_BROWSER_HELPER="$HOST_BIN_DIR/neo-distrobox-host-open-$BOX"
HOST_DISPATCH="$HOST_BIN_DIR/neo-distrobox-uri-host-dispatch-$BOX"
HOST_MIMEAPPS="$HOME/.config/mimeapps.list"
HOST_DATA_MIMEAPPS="$HOST_APP_DIR/mimeapps.list"
HANDLER_MAP="$TMP_DIR/handlers.tsv"
: > "$HANDLER_MAP"

if have podman && podman container exists "$BOX" >/dev/null 2>&1; then
    ENGINE="podman"
elif have docker && docker container inspect "$BOX" >/dev/null 2>&1; then
    ENGINE="docker"
else
    err "Could not map '$BOX' to Podman or Docker."
    exit 1
fi
info "Container engine: $ENGINE"

container_running() {
    case "$ENGINE" in
        podman) [[ "$(podman inspect -f '{{.State.Running}}' "$BOX" 2>/dev/null || printf false)" == true ]] ;;
        docker) [[ "$(docker inspect -f '{{.State.Running}}' "$BOX" 2>/dev/null || printf false)" == true ]] ;;
        *) return 1 ;;
    esac
}

container_start() {
    case "$ENGINE" in
        podman) run_timeout 15s podman start "$BOX" >/dev/null 2>&1 ;;
        docker) run_timeout 15s docker start "$BOX" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

container_exec_root() {
    case "$ENGINE" in
        podman) run_timeout 10s podman exec --user 0 "$BOX" "$@" ;;
        docker) run_timeout 10s docker exec --user 0 "$BOX" "$@" ;;
        *) return 1 ;;
    esac
}

container_exec_user() {
    local host_uid
    host_uid="$(id -u)"
    case "$ENGINE" in
        podman)
            run_timeout 10s podman exec --user "$host_uid" "$BOX" "$@" 2>/dev/null && return 0
            run_timeout 10s podman exec "$BOX" "$@"
            ;;
        docker)
            run_timeout 10s docker exec --user "$host_uid" "$BOX" "$@" 2>/dev/null && return 0
            run_timeout 10s docker exec "$BOX" "$@"
            ;;
        *) return 1 ;;
    esac
}

container_env() {
    case "$ENGINE" in
        podman) podman inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$BOX" 2>/dev/null || true ;;
        docker) docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$BOX" 2>/dev/null || true ;;
    esac
}

container_manager_start_if_needed() {
    if container_running; then return 0; fi
    info "Starting '$BOX' directly with $ENGINE."
    container_start || return 1
    return 0
}

# -----------------------------------------------------------------------------
# Removal of old Neo/legacy integration. Never enters/stops/starts the box.
# -----------------------------------------------------------------------------
remove_current_bridge() {
    local f base file tmp

    # Generated host desktop handlers for this box.
    for f in "$HOST_APP_DIR"/neo-distrobox-*"-$BOX.desktop" \
             "$HOST_APP_DIR/neo-distrobox-host-browser-$BOX.desktop" \
             "$HOST_APP_DIR/neo-hackerai.desktop"; do
        [[ -f "$f" ]] || continue
        base="$(basename -- "$f")"
        if [[ "$base" == neo-distrobox-*"-$BOX.desktop" || "$base" == "neo-distrobox-host-browser-$BOX.desktop" ]]; then
            remove_file "$f" || return 1
            warn "Removed old Neo handler: $base"
        elif grep -Eqi 'distrobox|neo-hackerai' "$f" 2>/dev/null && grep -Fq "$BOX" "$f" 2>/dev/null; then
            remove_file "$f" || return 1
            warn "Removed legacy handler: $base"
        fi
    done

    for f in "$HOST_BROWSER_HELPER" "$HOST_DISPATCH"; do
        [[ -e "$f" ]] || continue
        remove_file "$f" || return 1
        warn "Removed old Neo helper: $(basename -- "$f")"
    done

    # Remove only bridge-owned MIME entries. Never delete an unrelated native
    # handler from mimeapps.list. A legacy HackerAI handler is handled below
    # only when its desktop file is proven to be Distrobox/Neo-generated.
    for file in "$HOST_MIMEAPPS" "$HOST_DATA_MIMEAPPS"; do
        [[ -f "$file" ]] || continue
        local legacy_scheme_lines="$TMP_DIR/legacy-$((RANDOM % 100000))"
        awk -F '=' -v box="$BOX" '
            {
                lhs=$1
                if (lhs ~ /^x-scheme-handler\//) {
                    value=$0
                    sub(/^[^=]*=/, "", value)
                    val=value
                    sub(/;.*/, "", val)
                    if (val ~ /^neo-distrobox-/ && index(val, box) > 0) next
                }
                print
            }
        ' "$file" > "$legacy_scheme_lines" || return 1
        if ! cmp -s "$file" "$legacy_scheme_lines"; then
            backup_file "$file" || return 1
            mv -f -- "$legacy_scheme_lines" "$file" || return 1
        else
            rm -f -- "$legacy_scheme_lines"
        fi
    done

    # Remove the legacy HackerAI host desktop only when it is clearly a
    # Distrobox-generated file. This avoids deleting an unrelated native app.
    legacy_hackerai_removed=0
    for f in "$HOST_APP_DIR/hackerai-desktop-handler.desktop" "$HOST_APP_DIR/neo-hackerai.desktop"; do
        [[ -f "$f" ]] || continue
        if grep -Eqi 'distrobox|distrobox-host-exec|neo-distrobox' "$f" 2>/dev/null; then
            remove_file "$f" || return 1
            legacy_hackerai_removed=1
            warn "Removed legacy host handler: $(basename -- "$f")"
        fi
    done

    # If that legacy file was proven to be a bridge-generated HackerAI handler,
    # remove only its exact hackerai default association as well.
    if (( legacy_hackerai_removed == 1 )); then
        for file in "$HOST_MIMEAPPS" "$HOST_DATA_MIMEAPPS"; do
            [[ -f "$file" ]] || continue
            local hackerai_clean="$TMP_DIR/legacy-hackerai-$((RANDOM % 100000))"
            awk -F '=' '
                {
                    lhs=$1
                    if (lhs == "x-scheme-handler/hackerai") {
                        value=$0
                        sub(/^[^=]*=/, "", value)
                        val=value
                        sub(/;.*/, "", val)
                        if (val == "hackerai-desktop-handler.desktop" || val == "neo-hackerai.desktop") next
                    }
                    print
                }
            ' "$file" > "$hackerai_clean" || return 1
            if ! cmp -s "$file" "$hackerai_clean"; then
                backup_file "$file" || return 1
                mv -f -- "$hackerai_clean" "$file" || return 1
            else
                rm -f -- "$hackerai_clean"
            fi
        done
    fi

    # A previous manual attempt may have installed a user-level xdg-open that
    # routed the HOST into Distrobox. Remove only when its content is clearly a
    # Neo/Distrobox wrapper. Rollback restores the exact original file.
    if [[ -f "$HOST_BIN_DIR/xdg-open" ]] && grep -Eq 'distrobox-host-exec|neo-distrobox|neo-hackerai' "$HOST_BIN_DIR/xdg-open" 2>/dev/null; then
        remove_file "$HOST_BIN_DIR/xdg-open" || return 1
        warn "Removed legacy user xdg-open Distrobox wrapper."
    fi

    if [[ -d "$BOX_ROOT" ]]; then
        backup_file "$BOX_ROOT" || return 1
        rm -rf -- "$BOX_ROOT" || return 1
        warn "Removed old guest bridge state: $BOX_ROOT"
    fi

    have update-desktop-database && update-desktop-database "$HOST_APP_DIR" >/dev/null 2>&1 || true
    return 0
}

# Removal is intentionally before runtime preflight so it stays fast.
if [[ "${1:-}" == "--remove" ]]; then
    section "Removing Link Integration"
    remove_current_bridge || abort_setup "Could not remove the previous bridge cleanly."
    section "Remove Complete"
    info "Distrobox '$BOX' was not removed, stopped, or entered."
    info "Only Neo link integration was removed."
    info "Backups: $BACKUP_DIR"
    printf '  Restore: %q --rollback %q\n' "$SCRIPT_PATH" "$RUN_ID"
    SETUP_SUCCESS=1
    exit 0
fi

# -----------------------------------------------------------------------------
# Fast runtime preflight.
# ----------------------------------------------------------------------------
section "Fast Distrobox Runtime Check"
container_manager_start_if_needed || abort_setup "Could not start '$BOX'."

# IMPORTANT: do NOT write `timeout ... container_exec_*` here. `timeout` cannot
# execute a shell function. The wrapper function already owns its timeout.
if container_exec_root /bin/sh -c 'exit 0' >/dev/null 2>&1; then
    ok "Direct container execution: PASS"
else
    warn "Direct container execution failed; retrying once after 1 second."
    sleep 1
    if container_exec_root /bin/sh -c 'exit 0' >/dev/null 2>&1; then
        ok "Direct container execution: PASS (retry)"
    else
        warn "Direct execution failed; trying one short Distrobox no-tty fallback."
        if run_timeout 8s "$DISTROBOX_BIN" enter --no-tty --name "$BOX" -- /bin/sh -c 'exit 0' >/dev/null 2>&1; then
            ok "Distrobox no-tty fallback: PASS"
        else
            abort_setup "Container execution failed."
        fi
    fi
fi

if [[ ! -e /dev/pts/ptmx ]]; then
    warn "/dev/pts/ptmx is missing; attempting safe devpts repair."
    if have sudo; then
        sudo mount -t devpts devpts /dev/pts -o gid=5,mode=620,ptmxmode=666 >/dev/null 2>&1 || true
    fi
fi
if [[ -e /dev/pts/ptmx ]]; then ok "/dev/pts/ptmx: PASS"; else warn "/dev/pts/ptmx: unavailable"; fi

# Back up the exact container environment keys this bridge can modify.
if [[ "$ENGINE" == podman ]]; then
    pre_env="$(container_env)"
    for key in PATH XDG_CONFIG_DIRS XDG_DATA_DIRS BROWSER \
               NEO_DISTROBOX_LINK_BRIDGE_BIN NEO_DISTROBOX_LINK_BRIDGE_DATA \
               LANG LC_ALL LC_CTYPE LC_COLLATE; do
        old="$(printf '%s\n' "$pre_env" | sed -n "s/^${key}=//p" | head -n1 || true)"
        if [[ -n "$old" ]]; then
            printf '%s\t%s\t1\t%s\n' "$BOX" "$key" "$old" >> "$ENV_BACKUP"
        else
            printf '%s\t%s\t0\t\n' "$BOX" "$key" >> "$ENV_BACKUP"
        fi
    done
fi

# Only after preflight succeeds do we replace the previous bridge.
section "Removing Previous Neo Bridge"
remove_current_bridge || abort_setup "Could not remove previous bridge cleanly."
mkdir -p "$GUEST_BIN_DIR" "$GUEST_DATA_DIR" "$GUEST_CONFIG_DIR" "$GUEST_APP_DIR" || abort_setup "Could not create bridge directories."

# -----------------------------------------------------------------------------
# Guest -> Host default browser.
# -----------------------------------------------------------------------------
section "Guest -> Host Default Browser"
if [[ -z "$HOST_OPENER" ]]; then
    warn "No safe host URL opener was found. Web-link integration will be unavailable."
else
    read -r -p "Route HTTP/HTTPS links from '$BOX' to the HOST default browser? [Y/n]: " web_answer
    web_answer="${web_answer:-Y}"
    web_answer="${web_answer,,}"
    [[ "$web_answer" == y || "$web_answer" == yes ]] && WEB_ENABLED=1
fi

if (( WEB_ENABLED )); then
    mark_new "$HOST_BROWSER_HELPER"
    backup_file "$HOST_BROWSER_HELPER" || abort_setup "Could not backup host browser helper."
    cat > "$HOST_BROWSER_HELPER" <<EOF_HOST_BROWSER
#!/usr/bin/env bash
set -u
if [[ "\${1:-}" == --test ]]; then
    printf '%s\n' host-default-browser-helper-ok
    exit 0
fi
url="\${1:-}"
case "\$url" in
    http://*|https://*) ;;
    *) exit 2 ;;
esac
case "$HOST_OPENER_KIND" in
    xdg) exec "$HOST_OPENER" "\$url" ;;
    gio) exec "$HOST_OPENER" open "\$url" ;;
    kde) exec "$HOST_OPENER" "\$url" ;;
    *) exit 127 ;;
esac
EOF_HOST_BROWSER
    chmod 755 "$HOST_BROWSER_HELPER"
    ok "Host default-browser helper installed."
    info "Host opener: $HOST_OPENER"
    info "Host default browser: ${HOST_DEFAULT_BROWSER:-system default/unknown}"

    mark_new "$GUEST_WEB_HELPER"
    backup_file "$GUEST_WEB_HELPER" || abort_setup "Could not backup guest web helper."
    cat > "$GUEST_WEB_HELPER" <<EOF_GUEST_WEB
#!/usr/bin/env bash
set -u
url="\${1:-}"
case "\$url" in
    http://*|https://*) ;;
    *) exit 2 ;;
esac
if [[ "\${NEO_BRIDGE_TEST:-0}" == 1 ]]; then
    printf '%s\n' guest-web-helper-ok
    exit 0
fi
hostexec="\$(command -v distrobox-host-exec 2>/dev/null || true)"
if [[ -n "\$hostexec" ]]; then
    exec "\$hostexec" --yes "$HOST_BROWSER_HELPER" "\$url"
fi
if command -v host-spawn >/dev/null 2>&1; then
    exec host-spawn "$HOST_BROWSER_HELPER" "\$url"
fi
if [[ -x "$GUEST_BIN_DIR/host-spawn" ]]; then
    exec "$GUEST_BIN_DIR/host-spawn" "$HOST_BROWSER_HELPER" "\$url"
fi
exit 127
EOF_GUEST_WEB
    chmod 755 "$GUEST_WEB_HELPER"

    mark_new "$GUEST_XDG_WRAPPER"
    backup_file "$GUEST_XDG_WRAPPER" || abort_setup "Could not backup guest xdg-open wrapper."
    cat > "$GUEST_XDG_WRAPPER" <<EOF_GUEST_XDG
#!/usr/bin/env bash
set -u
uri="\${1:-}"
case "\$uri" in
    http://*|https://*) exec "$GUEST_WEB_HELPER" "\$uri" ;;
esac
if [[ -x /usr/bin/xdg-open ]]; then
    exec /usr/bin/xdg-open "\$@"
fi
if command -v gio >/dev/null 2>&1; then
    exec gio open "\$@"
fi
exit 127
EOF_GUEST_XDG
    chmod 755 "$GUEST_XDG_WRAPPER"

    mark_new "$GUEST_WEB_DESKTOP"
    backup_file "$GUEST_WEB_DESKTOP" || abort_setup "Could not backup guest web desktop."
    cat > "$GUEST_WEB_DESKTOP" <<EOF_GUEST_WEB_DESKTOP
[Desktop Entry]
Type=Application
Name=Neo Host Default Browser ($BOX)
Comment=Route HTTP/HTTPS links to the host default browser
Exec=$GUEST_WEB_HELPER %u
TryExec=$GUEST_WEB_HELPER
Terminal=false
NoDisplay=true
StartupNotify=false
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
EOF_GUEST_WEB_DESKTOP
    chmod 644 "$GUEST_WEB_DESKTOP"
fi

# ----------------------------------------------------------------------------
# Guest -> host execution / host-spawn fallback.
# ----------------------------------------------------------------------------
section "Guest -> Host Execution"
if (( WEB_ENABLED )); then
    if container_exec_user /bin/sh -c 'command -v distrobox-host-exec >/dev/null 2>&1 || command -v host-spawn >/dev/null 2>&1' >/dev/null 2>&1; then
        HOST_EXEC_OK=1
        ok "Guest host-exec capability: PASS"
    else
        warn "Guest host-exec helper is missing; trying host-spawn release fallback."
        guest_arch="$(container_exec_root /bin/sh -c 'uname -m' 2>/dev/null || true)"
        case "$guest_arch" in
            x86_64) spawn_asset="host-spawn-x86_64" ;;
            aarch64) spawn_asset="host-spawn-aarch64" ;;
            armv7l) spawn_asset="host-spawn-armv7l" ;;
            riscv64) spawn_asset="host-spawn-riscv64" ;;
            loongarch64) spawn_asset="host-spawn-loongarch64" ;;
            *) spawn_asset="" ;;
        esac
        if [[ -n "$spawn_asset" ]] && { have curl || have wget; }; then
            spawn_tmp="$TMP_DIR/$spawn_asset"
            if have curl; then
                curl -fL --connect-timeout 10 --max-time 60 "$HOST_SPAWN_BASE_URL/$spawn_asset" -o "$spawn_tmp" >/dev/null 2>&1 || true
            else
                wget -q --timeout=10 --tries=1 "$HOST_SPAWN_BASE_URL/$spawn_asset" -O "$spawn_tmp" >/dev/null 2>&1 || true
            fi
            if [[ -s "$spawn_tmp" ]]; then
                mark_new "$GUEST_BIN_DIR/host-spawn"
                backup_file "$GUEST_BIN_DIR/host-spawn" || abort_setup "Could not backup host-spawn fallback."
                cp -f -- "$spawn_tmp" "$GUEST_BIN_DIR/host-spawn" || abort_setup "Could not install host-spawn fallback."
                chmod 755 "$GUEST_BIN_DIR/host-spawn"
            fi
        fi
        if container_exec_user /bin/sh -c 'command -v distrobox-host-exec >/dev/null 2>&1 || command -v host-spawn >/dev/null 2>&1' >/dev/null 2>&1 || [[ -x "$GUEST_BIN_DIR/host-spawn" ]]; then
            HOST_EXEC_OK=1
            ok "Guest host-exec capability: PASS (fallback)"
        else
            warn "Guest host-exec capability could not be established."
        fi
    fi
else
    info "Web integration disabled; host-exec setup not required."
fi

# ----------------------------------------------------------------------------
# Discover guest URI handlers.
# ----------------------------------------------------------------------------
section "Discovering Guest URI Handlers"
DISCOVERY_SCRIPT=''
DISCOVERY_SCRIPT+=$'set -u\n'
DISCOVERY_SCRIPT+=$'for root in /usr/share/applications /usr/local/share/applications "$HOME/.local/share/applications"; do\n'
DISCOVERY_SCRIPT+=$'    [ -d "$root" ] || continue\n'
DISCOVERY_SCRIPT+=$'    find "$root" -maxdepth 1 -type f -name "*.desktop" -print 2>/dev/null\n'
DISCOVERY_SCRIPT+=$'done | sort -u | while IFS= read -r f; do\n'
DISCOVERY_SCRIPT+=$'    [ -f "$f" ] || continue\n'
DISCOVERY_SCRIPT+=$'    grep -q "^Hidden=true" "$f" 2>/dev/null && continue\n'
DISCOVERY_SCRIPT+=$'    # Ignore bridge-generated desktop files.\n'
DISCOVERY_SCRIPT+=$'    grep -Eq "^Name=.*Neo Distrobox|neo-distrobox|distrobox-host-browser" "$f" 2>/dev/null && continue\n'
DISCOVERY_SCRIPT+=$'    base="$(basename -- "$f")"\n'
DISCOVERY_SCRIPT+=$'    mime_line="$(sed -n "s/^MimeType=//p" "$f" | head -n1)"\n'
DISCOVERY_SCRIPT+=$'    [ -n "$mime_line" ] || continue\n'
DISCOVERY_SCRIPT+=$'    oldifs="$IFS"\n'
DISCOVERY_SCRIPT+=$'    IFS=";"\n'
DISCOVERY_SCRIPT+=$'    for m in $mime_line; do\n'
DISCOVERY_SCRIPT+=$'        case "$m" in\n'
DISCOVERY_SCRIPT+=$'            x-scheme-handler/*)\n'
DISCOVERY_SCRIPT+=$'                scheme="${m#x-scheme-handler/}"\n'
DISCOVERY_SCRIPT+=$'                case "$scheme" in\n'
DISCOVERY_SCRIPT+=$'                    http|https|file|ftp|ftps|mailto|tel|sms|callto|irc|ircs|news|nntp|gopher|data|urn|about) continue ;;\n'
DISCOVERY_SCRIPT+=$'                esac\n'
DISCOVERY_SCRIPT+=$'                case "$scheme" in *[!a-z0-9+.-]*|"") continue ;; esac\n'
DISCOVERY_SCRIPT+=$'                printf "%s\\t%s\\t%s\\n" "$scheme" "$base" "$f"\n'
DISCOVERY_SCRIPT+=$'                ;;\n'
DISCOVERY_SCRIPT+=$'        esac\n'
DISCOVERY_SCRIPT+=$'    done\n'
DISCOVERY_SCRIPT+=$'    IFS="$oldifs"\n'
DISCOVERY_SCRIPT+=$'done\n'

if discovery_output="$(container_exec_user /bin/sh -c "$DISCOVERY_SCRIPT" 2>/dev/null)"; then
    printf '%s\n' "$discovery_output" | awk -F '\t' 'NF>=3 && !seen[$1]++ {print}' > "$HANDLER_MAP"
fi

mapped_count="$(awk 'END{print NR+0}' "$HANDLER_MAP")"
if (( mapped_count > 0 )); then
    info "Found $mapped_count non-standard custom URI scheme(s):"
    awk -F '\t' '{printf "  - %s -> %s\n",$1,$2}' "$HANDLER_MAP"
else
    info "No non-standard custom URI schemes were found."
fi

if (( mapped_count > 0 )); then
    mark_new "$GUEST_HANDLER_MAP"
    backup_file "$GUEST_HANDLER_MAP" || abort_setup "Could not backup guest handler map."
    cp -f -- "$HANDLER_MAP" "$GUEST_HANDLER_MAP" || abort_setup "Could not save guest handler map."
    chmod 644 "$GUEST_HANDLER_MAP"

    mark_new "$GUEST_URI_HELPER"
    backup_file "$GUEST_URI_HELPER" || abort_setup "Could not backup guest URI helper."
    cat > "$GUEST_URI_HELPER" <<EOF_GUEST_URI
#!/usr/bin/env bash
set -u
mode=run
if [[ "\${1:-}" == --test ]]; then mode=test; shift; fi
scheme="\${1:-}"
uri="\${2:-}"
[[ -n "\$scheme" && -n "\$uri" ]] || exit 2
case "\$scheme" in
    http|https|file|ftp|ftps|mailto|tel|sms|callto|irc|ircs|news|nntp|gopher|data|urn|about) exit 2 ;;
esac
case "\$scheme" in *[!a-z0-9+.-]*) exit 2 ;; esac
case "\$uri" in "\$scheme":*) ;; *) exit 2 ;; esac

find_handler_file() {
    local target="\$1" root file
    while IFS= read -r root; do
        [[ -d "\$root" ]] || continue
        file="\$root/\$target"
        if [[ -f "\$file" ]]; then
            printf '%s\\n' "\$file"
            return 0
        fi
    done <<EOF_ROOTS
/usr/share/applications
/usr/local/share/applications
\$HOME/.local/share/applications
EOF_ROOTS
    return 1
}

handler=""
if [[ -f "${GUEST_HANDLER_MAP}" ]]; then
    mapped="\$(awk -F '\\t' -v s="\$scheme" '\$1==s {print \$2; exit}' "${GUEST_HANDLER_MAP}" 2>/dev/null || true)"
    if [[ -n "\$mapped" ]]; then
        handler="\$(find_handler_file "\$mapped" 2>/dev/null || true)"
    fi
fi

if [[ -z "\$handler" ]]; then
    find_handler() {
        local root file mime
        for root in /usr/share/applications /usr/local/share/applications "\$HOME/.local/share/applications"; do
            [[ -d "\$root" ]] || continue
            while IFS= read -r file; do
                [[ -f "\$file" ]] || continue
                grep -q '^Hidden=true' "\$file" 2>/dev/null && continue
                grep -Eq '^Name=.*Neo Distrobox|neo-distrobox|distrobox-host-browser' "\$file" 2>/dev/null && continue
                mime="\$(sed -n 's/^MimeType=//p' "\$file" | head -n1)"
                case ";\$mime;" in
                    *";x-scheme-handler/\$scheme;"*) printf '%s\\n' "\$file"; return 0 ;;
                esac
            done < <(find "\$root" -maxdepth 1 -type f -name '*.desktop' -print 2>/dev/null | sort)
        done
        return 1
    }
    handler="\$(find_handler 2>/dev/null || true)"
fi

[[ -n "\$handler" ]] || exit 4

if [[ "\$mode" == test ]]; then
    printf 'guest-uri-handler-ok:%s\\n' "\$(basename -- "\$handler")"
    exit 0
fi

if command -v gio >/dev/null 2>&1; then
    exec gio launch "\$handler" "\$uri"
fi
if command -v gtk-launch >/dev/null 2>&1; then
    desktop_id="\$(basename -- "\$handler")"
    desktop_id="\${desktop_id%.desktop}"
    exec gtk-launch "\$desktop_id" "\$uri"
fi

exec_line="\$(sed -n 's/^Exec=//p' "\$handler" | head -n1)"
[[ -n "\$exec_line" ]] || exit 127
quoted_uri="\$(printf '%q' "\$uri")"
exec_line="\${exec_line//%U/\$quoted_uri}"
exec_line="\${exec_line//%u/\$quoted_uri}"
exec_line="\${exec_line//%F/\$quoted_uri}"
exec_line="\${exec_line//%f/\$quoted_uri}"
exec_line="\${exec_line//%i/}"
exec_line="\${exec_line//%c/}"
exec_line="\${exec_line//%k/\$handler}"
sh -c "\$exec_line" >/dev/null 2>&1 &
exit 0
EOF_GUEST_URI
    chmod 755 "$GUEST_URI_HELPER"

    mark_new "$GUEST_MIMEAPPS"
    backup_file "$GUEST_MIMEAPPS" || abort_setup "Could not backup guest MIME defaults."
    {
        printf '[Default Applications]\n'
        if (( WEB_ENABLED )); then
            printf 'x-scheme-handler/http=neo-distrobox-host-browser.desktop;\n'
            printf 'x-scheme-handler/https=neo-distrobox-host-browser.desktop;\n'
            printf 'text/html=neo-distrobox-host-browser.desktop;\n'
        fi
        while IFS=$'\t' read -r scheme guest_desktop guest_path; do
            [[ -n "$scheme" ]] || continue
            safe_file="$(printf '%s' "$scheme" | tr -c 'A-Za-z0-9._-' '_')"
            printf 'x-scheme-handler/%s=neo-distrobox-%s-%s.desktop;\n' "$scheme" "$safe_file" "$BOX"
            : "$guest_desktop" "$guest_path"
        done < "$HANDLER_MAP"
    } > "$GUEST_MIMEAPPS"
    chmod 644 "$GUEST_MIMEAPPS"
fi

# ----------------------------------------------------------------------------
# Host custom URI handlers.
# ----------------------------------------------------------------------------
set_host_mime() {
    local scheme="$1" desktop="$2" mime="x-scheme-handler/$1" file tmp
    for file in "$HOST_MIMEAPPS" "$HOST_DATA_MIMEAPPS"; do
        if [[ -f "$file" ]]; then
            backup_file "$file" || return 1
        else
            mark_new "$file"
        fi
        mkdir -p "$(dirname -- "$file")" || return 1
        [[ -f "$file" ]] || : > "$file"
        tmp="$TMP_DIR/$(basename -- "$file").mime.$scheme"
        awk -v key="$mime" -v value="$desktop" '
            BEGIN { in_default=0; found=0; seen=0 }
            /^\[Default Applications\]$/ { in_default=1; seen=1; print; next }
            /^\[/ {
                if (in_default && !found) { print key "=" value ";"; found=1 }
                in_default=0
                print
                next
            }
            in_default && index($0,key "=")==1 { next }
            { print }
            END {
                if (in_default && !found) print key "=" value ";"
                if (!seen) { print ""; print "[Default Applications]"; print key "=" value ";" }
            }
        ' "$file" > "$tmp" || return 1
        chmod 644 "$tmp"
        mv -f -- "$tmp" "$file" || return 1
    done

    if have xdg-mime; then
        xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true
    fi
    if have gio; then
        gio mime "$mime" "$desktop" >/dev/null 2>&1 || true
    fi
}

if (( mapped_count > 0 )); then
    printf '\nCustom URI schemes mapped to guest applications:\n'
    awk -F '\t' '{printf "  - %s -> %s\n",$1,$2}' "$HANDLER_MAP"
    read -r -p "Register these custom URI schemes on the HOST so links return to '$BOX'? [Y/n]: " REGISTER_SCHEMES
    REGISTER_SCHEMES="${REGISTER_SCHEMES:-Y}"
    REGISTER_SCHEMES="${REGISTER_SCHEMES,,}"
fi

if (( mapped_count > 0 )) && [[ "$REGISTER_SCHEMES" == y || "$REGISTER_SCHEMES" == yes ]]; then
    mark_new "$HOST_DISPATCH"
    backup_file "$HOST_DISPATCH" || abort_setup "Could not backup host URI dispatcher."
    cat > "$HOST_DISPATCH" <<EOF_HOST_DISPATCH
#!/usr/bin/env bash
set -u
BOX=""
SCHEME=""
URI=""
TEST=0
DISTROBOX_BIN="$DISTROBOX_BIN"
ENGINE="$ENGINE"
GUEST_URI_HELPER="$GUEST_URI_HELPER"

while (( \$# )); do
    case "\$1" in
        --box) BOX="\${2:-}"; shift 2 ;;
        --scheme) SCHEME="\${2:-}"; shift 2 ;;
        --uri) URI="\${2:-}"; shift 2 ;;
        --test) TEST=1; shift ;;
        --help|-h) printf '%s\\n' 'Neo Distrobox host URI dispatcher'; exit 0 ;;
        *) [[ -n "\$URI" ]] || URI="\$1"; shift ;;
    esac
done

[[ -n "\$BOX" && -n "\$SCHEME" && -n "\$URI" ]] || exit 2
case "\$SCHEME" in *[!a-z0-9+.-]*|"") exit 2 ;; esac
case "\$URI" in "\$SCHEME":*) ;; *) exit 2 ;; esac
case "\$SCHEME" in
    http|https|file|ftp|ftps|mailto|tel|sms|callto|irc|ircs|news|nntp|gopher|data|urn|about) exit 2 ;;
esac

if (( TEST )); then
    command -v "\$DISTROBOX_BIN" >/dev/null 2>&1 || exit 127
    case "\$ENGINE" in
        podman)
            podman container exists "\$BOX" >/dev/null 2>&1 || exit 4
            podman inspect -f '{{.State.Running}}' "\$BOX" 2>/dev/null | grep -qx true || exit 5
            podman exec --user "$(id -u)" "\$BOX" test -x "\$GUEST_URI_HELPER" 2>/dev/null || exit 6
            ;;
        docker)
            docker container inspect "\$BOX" >/dev/null 2>&1 || exit 4
            docker inspect -f '{{.State.Running}}' "\$BOX" 2>/dev/null | grep -qx true || exit 5
            docker exec --user "$(id -u)" "\$BOX" test -x "\$GUEST_URI_HELPER" 2>/dev/null || exit 6
            ;;
        *) exit 7 ;;
    esac
    printf '%s\\n' host-uri-dispatcher-ok
    exit 0
fi

exec "\$DISTROBOX_BIN" enter --no-tty --name "\$BOX" -- "\$GUEST_URI_HELPER" "\$SCHEME" "\$URI"
EOF_HOST_DISPATCH
    chmod 755 "$HOST_DISPATCH"

    while IFS=$'\t' read -r scheme guest_desktop guest_path; do
        [[ -n "$scheme" ]] || continue
        safe_file="$(printf '%s' "$scheme" | tr -c 'A-Za-z0-9._-' '_')"
        host_desktop="neo-distrobox-${safe_file}-${BOX}.desktop"
        host_file="$HOST_APP_DIR/$host_desktop"
        mark_new "$host_file"
        backup_file "$host_file" || abort_setup "Could not backup host desktop handler."
        cat > "$host_file" <<EOF_HOST_DESKTOP
[Desktop Entry]
Type=Application
Name=Neo Distrobox ${scheme} Handler (${BOX})
Comment=Open ${scheme} links in ${BOX}
Exec=$HOST_DISPATCH --box $BOX --scheme $scheme --uri %u
TryExec=$HOST_DISPATCH
Terminal=false
NoDisplay=true
StartupNotify=false
MimeType=x-scheme-handler/${scheme};
EOF_HOST_DESKTOP
        chmod 644 "$host_file"
        set_host_mime "$scheme" "$host_desktop" || abort_setup "Could not register host MIME handler for $scheme."
        ok "Host ${scheme}:// -> $BOX configured."
        : "$guest_desktop" "$guest_path"
    done < "$HANDLER_MAP"
fi

have update-desktop-database && update-desktop-database "$HOST_APP_DIR" >/dev/null 2>&1 || true

# ----------------------------------------------------------------------------
# Persistent container environment.
# ----------------------------------------------------------------------------
section "Persistent Guest Environment"
if [[ "$ENGINE" == podman ]]; then
    envdump="$(container_env)"
    old_path="$(printf '%s\n' "$envdump" | sed -n 's/^PATH=//p' | head -n1 || true)"
    [[ -n "$old_path" ]] || old_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    case ":$old_path:" in *":$GUEST_BIN_DIR:"*) new_path="$old_path" ;; *) new_path="$GUEST_BIN_DIR:$old_path" ;; esac

    old_config_dirs="$(printf '%s\n' "$envdump" | sed -n 's/^XDG_CONFIG_DIRS=//p' | head -n1 || true)"
    [[ -n "$old_config_dirs" ]] || old_config_dirs="/etc/xdg:/usr/local/etc/xdg"
    case ":$old_config_dirs:" in *":$GUEST_CONFIG_DIR:"*) new_config_dirs="$old_config_dirs" ;; *) new_config_dirs="$GUEST_CONFIG_DIR:$old_config_dirs" ;; esac

    old_data_dirs="$(printf '%s\n' "$envdump" | sed -n 's/^XDG_DATA_DIRS=//p' | head -n1 || true)"
    [[ -n "$old_data_dirs" ]] || old_data_dirs="/usr/local/share:/usr/share"
    case ":$old_data_dirs:" in *":$GUEST_DATA_DIR:"*) new_data_dirs="$old_data_dirs" ;; *) new_data_dirs="$GUEST_DATA_DIR:$old_data_dirs" ;; esac

    podman_args=(
        --env "PATH=$new_path"
        --env "XDG_CONFIG_DIRS=$new_config_dirs"
        --env "XDG_DATA_DIRS=$new_data_dirs"
        --env "NEO_DISTROBOX_LINK_BRIDGE_BIN=$GUEST_BIN_DIR"
        --env "NEO_DISTROBOX_LINK_BRIDGE_DATA=$GUEST_DATA_DIR"
        --env "LANG=C.UTF-8"
        --env "LC_ALL=C.UTF-8"
        --env "LC_CTYPE=C.UTF-8"
        --env "LC_COLLATE=C.UTF-8"
    )
    if (( WEB_ENABLED )); then
        podman_args+=(--env "BROWSER=$GUEST_WEB_HELPER")
    else
        existing_browser="$(printf '%s\n' "$envdump" | sed -n 's/^BROWSER=//p' | head -n1 || true)"
        if [[ "$existing_browser" == "$GUEST_WEB_HELPER" ]]; then
            podman_args+=(--unsetenv BROWSER)
        fi
    fi

    if podman update "${podman_args[@]}" "$BOX" >/dev/null 2>&1; then
        PERSISTENT_ENV_OK=1
        ok "Persistent guest PATH, XDG and locale environment: PASS"
    else
        warn "Podman did not accept persistent environment changes. Generated helpers remain available."
    fi
else
    warn "Docker is active; persistent per-container environment updates are limited."
fi

# ----------------------------------------------------------------------------
# Automated tests. No test opens a GUI/browser.
# ----------------------------------------------------------------------------
section "Automated Tests"
TEST_FAIL=0

if bash -n "$SCRIPT_PATH" >/dev/null 2>&1; then ok "Script syntax: PASS"; else warn "Script syntax: FAIL"; TEST_FAIL=$((TEST_FAIL+1)); fi
if container_exec_root /bin/sh -c 'exit 0' >/dev/null 2>&1; then ok "Direct container execution: PASS"; else warn "Direct container execution: FAIL"; TEST_FAIL=$((TEST_FAIL+1)); fi
if [[ -e /dev/pts/ptmx ]]; then ok "/dev/pts/ptmx: PASS"; else warn "/dev/pts/ptmx: unavailable"; fi

# Ensure host default browser opener is the real host implementation.
if [[ -n "$HOST_OPENER" && -x "$HOST_OPENER" ]] && ! grep -Eq 'distrobox-host-exec|neo-distrobox|neo-hackerai' "$HOST_OPENER" 2>/dev/null; then
    ok "Host default-browser opener: PASS"
else
    warn "Host default-browser opener: FAIL"
    TEST_FAIL=$((TEST_FAIL+1))
fi

if (( WEB_ENABLED )); then
    if [[ -x "$HOST_BROWSER_HELPER" ]] && "$HOST_BROWSER_HELPER" --test >/dev/null 2>&1; then
        ok "Host browser helper: PASS"
    else
        warn "Host browser helper: FAIL"
        TEST_FAIL=$((TEST_FAIL+1))
    fi

    if [[ -x "$GUEST_WEB_HELPER" && -x "$GUEST_XDG_WRAPPER" && -f "$GUEST_WEB_DESKTOP" ]]; then
        ok "Guest web bridge files: PASS"
    else
        warn "Guest web bridge files: FAIL"
        TEST_FAIL=$((TEST_FAIL+1))
    fi

    if (( HOST_EXEC_OK )); then
        if container_exec_user env NEO_BRIDGE_TEST=1 "$GUEST_WEB_HELPER" https://example.com >/dev/null 2>&1; then
            ok "Guest -> host browser execution: PASS"
        else
            warn "Guest -> host browser execution: FAIL"
            TEST_FAIL=$((TEST_FAIL+1))
        fi
    else
        warn "Guest -> host execution capability: FAIL"
        TEST_FAIL=$((TEST_FAIL+1))
    fi
fi

for scheme in http https; do
    current=""
    if have xdg-mime; then
        current="$(xdg-mime query default "x-scheme-handler/$scheme" 2>/dev/null || true)"
    fi
    if [[ "$current" == neo-distrobox-* ]]; then
        warn "Host $scheme:// is incorrectly assigned to Neo Distrobox: $current"
        TEST_FAIL=$((TEST_FAIL+1))
    else
        ok "Host $scheme:// remains host-owned: ${current:-system/default}"
    fi
done

if [[ "$ENGINE" == podman ]]; then
    after="$(container_env)"
    env_ok=1
    for item in \
        "NEO_DISTROBOX_LINK_BRIDGE_BIN=$GUEST_BIN_DIR" \
        "NEO_DISTROBOX_LINK_BRIDGE_DATA=$GUEST_DATA_DIR" \
        "LANG=C.UTF-8" \
        "LC_ALL=C.UTF-8"; do
        grep -Fqx "$item" <<< "$after" || env_ok=0
    done
    if (( PERSISTENT_ENV_OK && env_ok )); then
        ok "Persistent guest environment: PASS"
    else
        warn "Persistent guest environment: FAIL"
        TEST_FAIL=$((TEST_FAIL+1))
    fi
fi

if (( mapped_count > 0 )) && [[ "$REGISTER_SCHEMES" == y || "$REGISTER_SCHEMES" == yes ]]; then
    first_scheme="$(head -n1 "$HANDLER_MAP" | cut -f1)"
    first_safe="$(printf '%s' "$first_scheme" | tr -c 'A-Za-z0-9._-' '_')"
    first_host_desktop="neo-distrobox-${first_safe}-${BOX}.desktop"
    first_host_file="$HOST_APP_DIR/$first_host_desktop"

    if [[ -f "$first_host_file" ]] && grep -Fq "x-scheme-handler/$first_scheme;" "$first_host_file"; then
        ok "Host ${first_scheme}:// desktop: PASS"
    else
        warn "Host ${first_scheme}:// desktop: FAIL"
        TEST_FAIL=$((TEST_FAIL+1))
    fi

    if container_exec_user "$GUEST_URI_HELPER" --test "$first_scheme" "${first_scheme}://test" >/dev/null 2>&1; then
        ok "Guest ${first_scheme}:// handler: PASS"
    else
        warn "Guest ${first_scheme}:// handler: FAIL"
        TEST_FAIL=$((TEST_FAIL+1))
    fi

    if [[ -x "$HOST_DISPATCH" ]] && "$HOST_DISPATCH" --test --box "$BOX" --scheme "$first_scheme" --uri "${first_scheme}://test" >/dev/null 2>&1; then
        ok "Host ${first_scheme}:// dispatcher: PASS"
    else
        warn "Host ${first_scheme}:// dispatcher: FAIL"
        TEST_FAIL=$((TEST_FAIL+1))
    fi

    mime_ok=0
    if grep -Fq "x-scheme-handler/$first_scheme=$first_host_desktop;" "$HOST_MIMEAPPS" 2>/dev/null; then mime_ok=1; fi
    if grep -Fq "x-scheme-handler/$first_scheme=$first_host_desktop;" "$HOST_DATA_MIMEAPPS" 2>/dev/null; then mime_ok=1; fi
    if (( mime_ok )); then
        ok "Host ${first_scheme}:// MIME default: PASS"
    else
        warn "Host ${first_scheme}:// MIME default: FAIL"
        TEST_FAIL=$((TEST_FAIL+1))
    fi

    xdg_current=""
    gio_current=""
    have xdg-mime && xdg_current="$(xdg-mime query default "x-scheme-handler/$first_scheme" 2>/dev/null || true)"
    have gio && gio_current="$(gio mime "x-scheme-handler/$first_scheme" 2>/dev/null | sed -n 's/^Default application for .*: //p' | head -n1 || true)"
    if [[ "$xdg_current" == "$first_host_desktop" || "$gio_current" == "$first_host_desktop" ]]; then
        ok "Host ${first_scheme}:// desktop association: PASS"
    else
        warn "Host ${first_scheme}:// desktop association: expected $first_host_desktop, got xdg='${xdg_current:-none}', gio='${gio_current:-none}'"
        TEST_FAIL=$((TEST_FAIL+1))
    fi
fi

# Save state for future diagnostics.
cp -f -- "$HANDLER_MAP" "$STATE_DIR/last-handlers-$BOX.tsv" 2>/dev/null || true
printf '%s\n' "$BOX" > "$STATE_DIR/last-box"
cat > "$STATE_DIR/last-run.tsv" <<EOF_LAST
version=$BRIDGE_VERSION
host=$HOST_NAME
host_id=$HOST_ID
host_pm=$HOST_PM
box=$BOX
engine=$ENGINE
web_enabled=$WEB_ENABLED
host_opener=$HOST_OPENER
host_default_browser=${HOST_DEFAULT_BROWSER:-system-default}
guest_to_host_exec=$HOST_EXEC_OK
persistent_environment=$PERSISTENT_ENV_OK
custom_scheme_count=$mapped_count
custom_scheme_registration=$REGISTER_SCHEMES
test_failures=$TEST_FAIL
log=$LOG_FILE
backup=$BACKUP_DIR
EOF_LAST

section "Finished"
if (( TEST_FAIL == 0 )); then
    ok "Integration completed and all automated tests passed for '$BOX'."
    SETUP_SUCCESS=1
else
    warn "Integration produced $TEST_FAIL automated test failure(s)."
    err "Restoring the previous bridge configuration."
    restore_current_run
    ROLLBACK_ACTIVE=0
    err "Log: $LOG_FILE"
    err "Backups: $BACKUP_DIR"
    exit 1
fi

if (( WEB_ENABLED )); then
    info "Guest HTTP/HTTPS -> HOST default browser: configured"
    info "Host browser: ${HOST_DEFAULT_BROWSER:-system default/unknown}"
else
    info "Guest HTTP/HTTPS -> HOST default browser: disabled"
fi

if (( mapped_count > 0 )) && [[ "$REGISTER_SCHEMES" == y || "$REGISTER_SCHEMES" == yes ]]; then
    info "HOST custom URI -> '$BOX': configured for $mapped_count scheme(s)"
else
    info "HOST custom URI registration: disabled"
fi

info "Backups: $BACKUP_DIR"
info "Log: $LOG_FILE"
printf '  Rollback: %q --rollback %q\n' "$SCRIPT_PATH" "$RUN_ID"
printf '  Remove bridge: %q --remove %q\n' "$SCRIPT_PATH" "$BOX"

if (( WEB_ENABLED )); then
    printf '\nNon-destructive guest web test:\n'
    printf '  %q enter --no-tty --name %q -- env NEO_BRIDGE_TEST=1 %q %q\n' "$DISTROBOX_BIN" "$BOX" "$GUEST_WEB_HELPER" 'https://example.com'
    printf 'Live web test (opens the HOST default browser):\n'
    printf '  %q enter --name %q -- %q %q\n' "$DISTROBOX_BIN" "$BOX" "$GUEST_XDG_WRAPPER" 'https://example.com'
fi

if (( mapped_count > 0 )) && [[ "$REGISTER_SCHEMES" == y || "$REGISTER_SCHEMES" == yes ]]; then
    first_scheme="$(head -n1 "$HANDLER_MAP" | cut -f1)"
    printf 'Non-destructive host custom-URI test:\n'
    printf '  %q --test --box %q --scheme %q --uri %q\n' "$HOST_DISPATCH" "$BOX" "$first_scheme" "${first_scheme}://test"
    printf 'Live custom-URI test (opens/returns to the guest app):\n'
    printf '  xdg-open %q\n' "${first_scheme}://test"
fi

exit 0
