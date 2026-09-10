#!/usr/bin/env bash
#
# Neo Distrobox Universal Setup
#
# Goals:
#   * Detect the Linux host and its package manager.
#   * Install Podman (preferred) or fall back to Docker.
#   * Install Distrobox from the host repository, with an official
#     standalone installer fallback.
#   * Validate rootless containers and repair common devpts/ptmx issues.
#   * Ask which Linux distribution should run INSIDE Distrobox.
#   * Create and initialize the guest with retries and recovery.
#   * Repair common Debian/Ubuntu/Kali APT bootstrap/certificate issues.
#   * Repair inherited locale warnings using C.UTF-8 when available.
#   * Install guest sudo when possible.
#   * Optionally enable guest -> host browser links using host-spawn.
#   * Optionally register HackerAI hackerai:// deep links on the HOST so
#     a browser can return to HackerAI running inside the Distrobox guest.
#   * Produce a useful log and diagnostics instead of silently failing.
#
# Run as your normal user:
#   chmod +x neo-distrobox-setup.sh
#   ./neo-distrobox-setup.sh
#

set -Eeuo pipefail
IFS=$'\n\t'

VERSION='3.0.0'
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/neo-distrobox"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/neo-distrobox"
LOG_FILE="${STATE_ROOT}/setup-$(date +%Y%m%d-%H%M%S).log"
BACKUP_ROOT="${STATE_ROOT}/backups/$(date +%Y%m%d-%H%M%S)"

CONTAINER_NAME=''
GUEST_ID=''
GUEST_IMAGE=''
HOST_ID=''
HOST_LIKE=''
HOST_NAME=''
HOST_ARCH=''
HOST_KERNEL=''
HOST_PM=''
HOST_FAMILY=''
ENGINE=''
DISTROBOX_BIN=''
BROWSER_INTEGRATION='no'
HACKERAI_DEEP_LINK='no'
INSTALL_FLATPAK='no'
REPAIR_LOCALE='yes'
GUEST_SUDO='yes'

# Current stable host-spawn release verified from upstream.
HOST_SPAWN_VERSION='v1.6.2'

mkdir -p "$STATE_ROOT" "$CACHE_ROOT" "$BACKUP_ROOT"
exec > >(tee -a "$LOG_FILE") 2>&1

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------

RESET=$'\033[0m'
BLUE=$'\033[0;34m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
CYAN=$'\033[0;36m'

info() { printf '%b[INFO]%b %s\n' "$BLUE" "$RESET" "$*"; }
ok() { printf '%b[ OK ]%b %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$*"; }
err() { printf '%b[ERR ]%b %s\n' "$RED" "$RESET" "$*" >&2; }
section() { printf '\n%b==== %s ====%b\n' "$CYAN" "$*" "$RESET"; }

ON_ERROR_ACTIVE='yes'
on_error() {
    local rc=$?
    if [[ "$ON_ERROR_ACTIVE" == 'yes' ]]; then
        warn "Unexpected command failure (exit ${rc})."
        warn "Log: ${LOG_FILE}"
    fi
}
trap on_error ERR

cleanup() {
    rm -rf -- "$CACHE_ROOT/tmp" 2>/dev/null || true
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# Basic helpers
# -----------------------------------------------------------------------------

need_cmd() { command -v "$1" >/dev/null 2>&1; }

run_timeout() {
    local seconds="$1"
    shift
    if need_cmd timeout; then
        timeout --signal=TERM --kill-after=10s "${seconds}s" "$@"
    else
        "$@"
    fi
}

as_root() {
    sudo "$@"
}

shell_quote() {
    local value="$1"
    printf "'%s'" "${value//\'/\'\\\'\'}"
}

is_yes() {
    case "${1:-}" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

backup_file() {
    local file="$1"
    [[ -e "$file" ]] || return 0
    local rel="${file#/}"
    mkdir -p "${BACKUP_ROOT}/$(dirname "$rel")"
    as_root cp -a "$file" "${BACKUP_ROOT}/${rel}" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Host detection
# -----------------------------------------------------------------------------

[[ $EUID -ne 0 ]] || { err "Run this as your normal user, not as root."; exit 1; }
need_cmd sudo || { err "sudo is required on the host."; exit 1; }
[[ -r /etc/os-release ]] || { err "Cannot read /etc/os-release."; exit 1; }

# shellcheck disable=SC1091
source /etc/os-release

HOST_ID="${ID:-unknown}"
HOST_LIKE="${ID_LIKE:-}"
HOST_NAME="${PRETTY_NAME:-$HOST_ID}"
HOST_ARCH="$(uname -m)"
HOST_KERNEL="$(uname -r)"

if need_cmd pacman; then
    HOST_PM='pacman'
    HOST_FAMILY='arch'
elif need_cmd apt-get; then
    HOST_PM='apt'
    HOST_FAMILY='debian'
elif need_cmd dnf5; then
    HOST_PM='dnf5'
    HOST_FAMILY='rpm'
elif need_cmd dnf; then
    HOST_PM='dnf'
    HOST_FAMILY='rpm'
elif need_cmd zypper; then
    HOST_PM='zypper'
    HOST_FAMILY='suse'
elif need_cmd apk; then
    HOST_PM='apk'
    HOST_FAMILY='alpine'
elif need_cmd xbps-install; then
    HOST_PM='xbps'
    HOST_FAMILY='void'
elif need_cmd emerge; then
    HOST_PM='emerge'
    HOST_FAMILY='gentoo'
fi

section "Neo Distrobox Setup v${VERSION}"
info "Host OS      : ${HOST_NAME}"
info "OS ID        : ${HOST_ID}"
info "OS family    : ${HOST_LIKE:-unknown}"
info "Package mgr  : ${HOST_PM:-none}"
info "Architecture : ${HOST_ARCH}"
info "Kernel       : ${HOST_KERNEL}"
info "Log file     : ${LOG_FILE}"
info "Backup dir   : ${BACKUP_ROOT}"

if [[ -z "$HOST_PM" ]]; then
    warn "The host package manager is unknown. Package installation may require manual work."
fi

# -----------------------------------------------------------------------------
# Host package installation
# -----------------------------------------------------------------------------

host_install() {
    local package_list=("$@")

    case "$HOST_PM" in
        pacman)
            as_root pacman -Syu --needed --noconfirm "${package_list[@]}"
            ;;
        apt)
            export DEBIAN_FRONTEND=noninteractive
            as_root apt-get update
            as_root apt-get install -y "${package_list[@]}"
            ;;
        dnf5)
            as_root dnf5 install -y "${package_list[@]}"
            ;;
        dnf)
            as_root dnf install -y "${package_list[@]}"
            ;;
        zypper)
            as_root zypper --non-interactive refresh
            as_root zypper --non-interactive install "${package_list[@]}"
            ;;
        apk)
            as_root apk add --no-cache "${package_list[@]}"
            ;;
        xbps)
            as_root xbps-install -Sy "${package_list[@]}"
            ;;
        emerge)
            as_root emerge --oneshot "${package_list[@]}"
            ;;
        *)
            return 1
            ;;
    esac
}

host_install_one() {
    local pkg="$1"
    case "$HOST_PM" in
        pacman) as_root pacman -S --needed --noconfirm "$pkg" ;;
        apt)
            export DEBIAN_FRONTEND=noninteractive
            as_root apt-get install -y "$pkg"
            ;;
        dnf5) as_root dnf5 install -y "$pkg" ;;
        dnf) as_root dnf install -y "$pkg" ;;
        zypper) as_root zypper --non-interactive install "$pkg" ;;
        apk) as_root apk add --no-cache "$pkg" ;;
        xbps) as_root xbps-install -y "$pkg" ;;
        emerge) as_root emerge --oneshot "$pkg" ;;
        *) return 1 ;;
    esac
}

install_distrobox_official() {
    need_cmd curl || return 1
    local prefix="$HOME/.local"
    mkdir -p "$prefix"

    info "Trying official Distrobox standalone installer."
    if curl -fsSL --retry 3 --connect-timeout 15 \
        'https://raw.githubusercontent.com/89luca89/distrobox/main/install' \
        | sh -s -- --prefix "$prefix"; then
        export PATH="$prefix/bin:$PATH"
        return 0
    fi

    return 1
}

section "Host Dependencies"

if ! need_cmd curl; then
    host_install_one curl || warn "Could not install curl using the detected host package manager."
fi

if ! need_cmd podman; then
    info "Podman is not installed; installing it on the detected host."
    if host_install_one podman; then
        ok "Podman installed."
    else
        warn "Podman installation failed."
    fi
fi

if need_cmd podman; then
    ENGINE='podman'
elif need_cmd docker; then
    ENGINE='docker'
    warn "Podman is unavailable; using Docker as the container engine fallback."
else
    # One explicit secondary package attempt before giving up.
    if host_install_one podman; then
        ENGINE='podman'
    elif need_cmd docker; then
        ENGINE='docker'
    else
        die "Neither Podman nor Docker is available on this host."
    fi
fi

if ! need_cmd distrobox; then
    info "Distrobox is missing; trying the host package first."
    case "$HOST_PM" in
        pacman|apt|dnf|dnf5|zypper|apk|xbps|emerge)
            if ! host_install_one distrobox; then
                warn "The distro package for Distrobox failed or is unavailable."
            fi
            ;;
        *)
            warn "No supported host package-manager path for Distrobox."
            ;;
    esac
fi

if ! need_cmd distrobox; then
    install_distrobox_official || {
        err "Distrobox could not be installed."
        err "See ${LOG_FILE}."
        exit 1
    }
fi

DISTROBOX_BIN="$(command -v distrobox)"
ok "Distrobox: $(distrobox --version)"
ok "Container engine: ${ENGINE} (${ENGINE})"

# Flatpak is NOT required for Distrobox or host-browser forwarding. It is
# offered as an optional host component because some users want it for GUI
# applications, and installing it can touch initramfs/system services on some
# distributions. The default is therefore No.
section "Optional Flatpak"
read -r -p 'Install Flatpak support on the host? [y/N]: ' flatpak_answer
if is_yes "${flatpak_answer:-n}"; then
    INSTALL_FLATPAK='yes'
    if need_cmd flatpak; then
        ok "Flatpak is already installed."
    elif host_install_one flatpak; then
        ok "Flatpak installed on the host."
    else
        warn "Flatpak installation failed; continuing without it."
        INSTALL_FLATPAK='no'
    fi
else
    info "Flatpak installation skipped."
fi

# -----------------------------------------------------------------------------
# Host rootless container checks
# -----------------------------------------------------------------------------

configure_rootless_podman() {
    [[ "$ENGINE" == 'podman' ]] || return 0

    section "Rootless Podman"

    for file in /etc/subuid /etc/subgid; do
        if [[ ! -e "$file" ]]; then
            as_root touch "$file"
            as_root chmod 644 "$file"
            backup_file "$file"
        fi
    done

    if ! as_root grep -qE "^${USER}:" /etc/subuid; then
        as_root usermod --add-subuids 100000-165535 "$USER" || \
            warn "Could not add subuid range for ${USER}."
    fi

    if ! as_root grep -qE "^${USER}:" /etc/subgid; then
        as_root usermod --add-subgids 100000-165535 "$USER" || \
            warn "Could not add subgid range for ${USER}."
    fi

    # Exact failure seen on the user's system.
    if [[ ! -e /dev/pts/ptmx ]]; then
        warn "/dev/pts/ptmx is missing; attempting devpts repair."
        as_root mount \
            -t devpts devpts /dev/pts \
            -o gid=5,mode=620,ptmxmode=666 || \
            warn "devpts mount repair failed."
    fi

    if [[ -e /dev/pts/ptmx ]]; then
        ok "/dev/pts/ptmx is available."
    else
        warn "/dev/pts/ptmx is still unavailable."
    fi

    if need_cmd systemctl && systemctl --user >/dev/null 2>&1; then
        systemctl --user enable --now podman.socket >/dev/null 2>&1 || \
            warn "Could not enable podman.socket; continuing because it is optional."
    fi

    local test_output=''
    if test_output="$(podman run --rm docker.io/library/alpine:latest sh -c 'printf "PODMAN_OK"' 2>&1)" \
        && [[ "$test_output" == *PODMAN_OK* ]]; then
        ok "Rootless Podman test passed."
        return 0
    fi

    warn "Rootless Podman test failed. Checking runtime alternatives."

    if ! need_cmd crun; then
        case "$HOST_PM" in
            pacman|apt|dnf|dnf5|zypper|apk|xbps|emerge)
                host_install_one crun >/dev/null 2>&1 || true
                ;;
        esac
    fi

    if need_cmd crun; then
        if podman --runtime crun run --rm docker.io/library/alpine:latest \
            sh -c 'printf "CRUN_OK"' 2>&1 | grep -q 'CRUN_OK'; then
            warn "Podman works with crun as a fallback runtime."
            return 0
        fi
    fi

    if [[ ! -e /dev/pts/ptmx ]]; then
        die "Podman failed and /dev/pts/ptmx is unavailable."
    fi

    die "Rootless Podman container test failed. See ${LOG_FILE}."
}

configure_rootless_podman

# -----------------------------------------------------------------------------
# Guest selection
# -----------------------------------------------------------------------------

choose_guest() {
    section "Choose Guest Linux"

    cat <<'MENU'
  1) Arch Linux
  2) Debian 13
  3) Ubuntu
  4) Fedora
  5) Kali Linux Rolling
  6) openSUSE Tumbleweed
  7) Alpine Linux
  8) Custom OCI image
MENU

    while :; do
        read -r -p 'Selection [1-8]: ' choice
        case "$choice" in
            1)
                GUEST_ID='arch'
                GUEST_IMAGE='docker.io/library/archlinux:latest'
                break
                ;;
            2)
                GUEST_ID='debian'
                GUEST_IMAGE='docker.io/library/debian:13'
                break
                ;;
            3)
                GUEST_ID='ubuntu'
                GUEST_IMAGE='docker.io/library/ubuntu:latest'
                break
                ;;
            4)
                GUEST_ID='fedora'
                GUEST_IMAGE='registry.fedoraproject.org/fedora:latest'
                break
                ;;
            5)
                GUEST_ID='kali'
                GUEST_IMAGE='docker.io/kalilinux/kali-rolling:latest'
                break
                ;;
            6)
                GUEST_ID='opensuse'
                GUEST_IMAGE='registry.opensuse.org/opensuse/tumbleweed:latest'
                break
                ;;
            7)
                GUEST_ID='alpine'
                GUEST_IMAGE='docker.io/library/alpine:latest'
                break
                ;;
            8)
                GUEST_ID='custom'
                read -r -p 'OCI image: ' GUEST_IMAGE
                [[ -n "$GUEST_IMAGE" ]] && break
                warn 'Image cannot be empty.'
                ;;
            *)
                warn 'Choose a number from 1 to 8.'
                ;;
        esac
    done

    local default_name="neo-${GUEST_ID}"
    read -r -p "Container name [${default_name}]: " CONTAINER_NAME
    CONTAINER_NAME="${CONTAINER_NAME:-$default_name}"

    [[ "$CONTAINER_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || \
        die "Invalid container name: ${CONTAINER_NAME}"

    info "Guest image: ${GUEST_IMAGE}"
    info "Container : ${CONTAINER_NAME}"
}

choose_guest

# -----------------------------------------------------------------------------
# Container helpers
# -----------------------------------------------------------------------------

container_exists() {
    if [[ "$ENGINE" == 'podman' ]]; then
        podman container exists "$CONTAINER_NAME" 2>/dev/null
    else
        docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1
    fi
}

container_start() {
    if [[ "$ENGINE" == 'podman' ]]; then
        podman start "$CONTAINER_NAME" >/dev/null 2>&1 || true
    else
        docker start "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
}

container_stop() {
    if [[ "$ENGINE" == 'podman' ]]; then
        podman stop --time 10 "$CONTAINER_NAME" >/dev/null 2>&1 || true
    else
        docker stop -t 10 "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
}

container_logs() {
    if [[ "$ENGINE" == 'podman' ]]; then
        podman logs --tail 120 "$CONTAINER_NAME" 2>&1 || true
    else
        docker logs --tail 120 "$CONTAINER_NAME" 2>&1 || true
    fi
}

container_exec_root() {
    local cmd="$1"
    container_start
    if [[ "$ENGINE" == 'podman' ]]; then
        podman exec --user 0 "$CONTAINER_NAME" sh -lc "$cmd"
    else
        docker exec --user 0 "$CONTAINER_NAME" sh -lc "$cmd"
    fi
}

container_exec_user() {
    local cmd="$1"
    container_start
    if [[ "$ENGINE" == 'podman' ]]; then
        podman exec "$CONTAINER_NAME" sh -lc "$cmd"
    else
        docker exec "$CONTAINER_NAME" sh -lc "$cmd"
    fi
}

# -----------------------------------------------------------------------------
# Create / recreate guest
# -----------------------------------------------------------------------------

prepare_container() {
    section "Guest Container"

    if container_exists; then
        warn "Container ${CONTAINER_NAME} already exists."
        printf '%s\n' \
            '  r) Recreate it from the selected image (destructive to this container only)' \
            '  u) Reuse the existing container' \
            '  a) Abort'

        while :; do
            read -r -p 'Choose [r/u/a]: ' action
            case "$action" in
                r|R)
                    if [[ "$ENGINE" == 'podman' ]]; then
                        podman stop --time 10 "$CONTAINER_NAME" >/dev/null 2>&1 || true
                    else
                        docker stop -t 10 "$CONTAINER_NAME" >/dev/null 2>&1 || true
                    fi

                    distrobox rm --force "$CONTAINER_NAME" 2>/dev/null || true
                    if [[ "$ENGINE" == 'podman' ]]; then
                        podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
                    else
                        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
                    fi
                    break
                    ;;
                u|U)
                    ok "Reusing existing container."
                    return 0
                    ;;
                a|A)
                    exit 0
                    ;;
                *)
                    warn 'Choose r, u, or a.'
                    ;;
            esac
        done
    fi

    local create_attempt=1
    while (( create_attempt <= 2 )); do
        if distrobox create --name "$CONTAINER_NAME" --image "$GUEST_IMAGE"; then
            ok "Distrobox container created."
            return 0
        fi

        warn "Distrobox create attempt ${create_attempt} failed."

        if [[ "$ENGINE" == 'podman' ]]; then
            podman pull "$GUEST_IMAGE" || true
        else
            docker pull "$GUEST_IMAGE" || true
        fi

        ((create_attempt++))
    done

    die "Could not create Distrobox container ${CONTAINER_NAME}."
}

prepare_container

# -----------------------------------------------------------------------------
# Guest APT recovery
# -----------------------------------------------------------------------------

apt_recovery() {
    [[ "$GUEST_ID" =~ ^(debian|ubuntu|kali)$ ]] || return 0

    section "Guest APT Recovery"

    local recovery_script
    recovery_script="$(cat <<'EOF_APT_SCRIPT'
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive

if ! command -v apt-get >/dev/null 2>&1; then
    exit 2
fi

mkdir -p /root/neo-distrobox-recovery

# Save repository configuration before changing anything.
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    cp -a /etc/apt/sources.list.d/debian.sources \
        /root/neo-distrobox-recovery/debian.sources.bak
fi
if [ -f /etc/apt/sources.list ]; then
    cp -a /etc/apt/sources.list \
        /root/neo-distrobox-recovery/sources.list.bak
fi

# Debian 13/Trixie can hit APT problems while Distrobox bootstraps.
# Removing only trixie-updates keeps the stable Trixie base and security repo.
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    sed -i '/^Suites:/ s/ trixie-updates//' \
        /etc/apt/sources.list.d/debian.sources
fi

# First try normal HTTPS.
if apt-get update -o Acquire::Retries=1; then
    exit 0
fi

echo '[neo-distrobox] HTTPS APT update failed; bootstrapping CA certificates.'

# Only fall back to the official Debian mirrors over HTTP for the bootstrap.
# After ca-certificates is installed, HTTPS is restored and verified again.
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    sed -i \
        's#https://deb.debian.org/debian#http://deb.debian.org/debian#g; s#https://deb.debian.org/debian-security#http://deb.debian.org/debian-security#g' \
        /etc/apt/sources.list.d/debian.sources
elif [ -f /etc/apt/sources.list ]; then
    sed -i 's#https://#http://#g' /etc/apt/sources.list
fi

apt-get clean || true
apt-get update -o Acquire::Retries=1 || exit 3
apt-get install -y ca-certificates || exit 4
update-ca-certificates || true

if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    sed -i \
        's#http://deb.debian.org/debian#https://deb.debian.org/debian#g; s#http://deb.debian.org/debian-security#https://deb.debian.org/debian-security#g' \
        /etc/apt/sources.list.d/debian.sources
elif [ -f /etc/apt/sources.list ]; then
    sed -i 's#http://#https://#g' /etc/apt/sources.list
fi

apt-get update -o Acquire::Retries=2
EOF_APT_SCRIPT
)"

    if container_exec_root "$recovery_script"; then
        ok "Guest APT recovery completed."
        return 0
    fi

    warn "Guest APT recovery failed."
    return 1
}

# -----------------------------------------------------------------------------
# Distrobox initialization
# -----------------------------------------------------------------------------

run_distrobox_initialization() {
    section "Distrobox Initialization"

    # Distrobox initialization can legitimately take several minutes on the
    # first run. We provide a hard upper bound so a broken package operation
    # cannot hang the installer forever.
    if run_timeout 600 distrobox enter "$CONTAINER_NAME" -- \
        sh -lc 'printf "NEO_DISTROBOX_INIT_OK\n"'; then
        ok "Distrobox initialization completed."
        return 0
    fi

    warn "Distrobox initialization failed or timed out."
    return 1
}

INIT_OK='no'

if run_distrobox_initialization; then
    INIT_OK='yes'
else
    if [[ "$GUEST_ID" =~ ^(debian|ubuntu|kali)$ ]]; then
        if apt_recovery && run_distrobox_initialization; then
            INIT_OK='yes'
        fi
    fi
fi

if [[ "$INIT_OK" != 'yes' ]]; then
    warn "Trying one controlled container restart."
    container_stop
    container_start
    if run_distrobox_initialization; then
        INIT_OK='yes'
    fi
fi

if [[ "$INIT_OK" != 'yes' ]]; then
    err "Container initialization failed. Last container log:"
    printf '%s\n' '------------------------------------------------------------'
    container_logs
    printf '%s\n' '------------------------------------------------------------'
    die "Cannot safely continue. See ${LOG_FILE}."
fi

# -----------------------------------------------------------------------------
# Guest locale repair
# -----------------------------------------------------------------------------

setup_guest_locale() {
    [[ "$REPAIR_LOCALE" == 'yes' ]] || return 0

    section "Guest Locale"

    local guest_locale_script
    guest_locale_script="$(cat <<'EOF_LOCALE_SCRIPT'
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Prefer C.UTF-8 when the guest provides it. This prevents inherited
# host-locale warnings while retaining UTF-8 support.
if command -v locale >/dev/null 2>&1 && locale -a 2>/dev/null | grep -qiE '^c\\.utf-?8$'; then
    mkdir -p /etc/profile.d
    cat > /etc/profile.d/neo-locale.sh <<'EOF_LOCALE'
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
EOF_LOCALE
    chmod 0644 /etc/profile.d/neo-locale.sh
fi

# Apply the locale to the Distrobox user's environment as well. Distrobox
# commonly creates the user with UID 1000, but we detect the actual name.
guest_user="$(id -nu 1000 2>/dev/null || true)"
if [ -n "$guest_user" ] && [ -d "/home/$guest_user" ]; then
    user_home="/home/$guest_user"
    mkdir -p "$user_home/.config/environment.d" "$user_home/.local/bin"

    cat > "$user_home/.config/environment.d/neo-locale.conf" <<'EOF_ENV'
LANG=C.UTF-8
LC_ALL=C.UTF-8
EOF_ENV

    cat > "$user_home/.local/bin/neo-locale-env" <<'EOF_LOCALE_CMD'
#!/bin/sh
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
exec "$@"
EOF_LOCALE_CMD
    chmod 0755 "$user_home/.local/bin/neo-locale-env"
    chown -R "$guest_user:$guest_user" \
        "$user_home/.config/environment.d" "$user_home/.local" 2>/dev/null || true
fi
EOF_LOCALE_SCRIPT
)"

    container_exec_root "$guest_locale_script" || \
        warn "Locale repair could not be completed."

    ok "Guest locale repair applied where supported."
}

# -----------------------------------------------------------------------------
# Guest sudo installation
# -----------------------------------------------------------------------------

setup_guest_sudo() {
    [[ "$GUEST_SUDO" == 'yes' ]] || return 0

    section "Guest sudo"

    local script
    script="$(cat <<'EOF_SUDO_SCRIPT'
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if command -v sudo >/dev/null 2>&1; then
    exit 0
fi

if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y sudo >/dev/null 2>&1 || {
        apt-get update -o Acquire::Retries=1 || true
        apt-get install -y sudo >/dev/null 2>&1 || true
    }
fi

if ! command -v sudo >/dev/null 2>&1 && command -v dnf5 >/dev/null 2>&1; then
    dnf5 install -y sudo >/dev/null 2>&1 || true
fi
if ! command -v sudo >/dev/null 2>&1 && command -v dnf >/dev/null 2>&1; then
    dnf install -y sudo >/dev/null 2>&1 || true
fi
if ! command -v sudo >/dev/null 2>&1 && command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm sudo >/dev/null 2>&1 || true
fi
if ! command -v sudo >/dev/null 2>&1 && command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install sudo >/dev/null 2>&1 || true
fi
if ! command -v sudo >/dev/null 2>&1 && command -v apk >/dev/null 2>&1; then
    apk add --no-cache sudo >/dev/null 2>&1 || true
fi
if ! command -v sudo >/dev/null 2>&1 && command -v xbps-install >/dev/null 2>&1; then
    xbps-install -Sy sudo >/dev/null 2>&1 || true
fi

command -v sudo >/dev/null 2>&1
EOF_SUDO_SCRIPT
)"

    if container_exec_root "$script"; then
        ok "Guest sudo is available."
    else
        warn "Guest sudo could not be installed automatically; root is still available with su."
    fi
}

# -----------------------------------------------------------------------------
# host-spawn download
# -----------------------------------------------------------------------------

host_spawn_asset_url() {
    case "$HOST_ARCH" in
        x86_64) printf '%s\n' "https://github.com/1player/host-spawn/releases/download/${HOST_SPAWN_VERSION}/host-spawn-x86_64" ;;
        aarch64|arm64) printf '%s\n' "https://github.com/1player/host-spawn/releases/download/${HOST_SPAWN_VERSION}/host-spawn-aarch64" ;;
        loongarch64) printf '%s\n' "https://github.com/1player/host-spawn/releases/download/${HOST_SPAWN_VERSION}/host-spawn-loongarch64" ;;
        riscv64) printf '%s\n' "https://github.com/1player/host-spawn/releases/download/${HOST_SPAWN_VERSION}/host-spawn-riscv64" ;;
        *) return 1 ;;
    esac
}

install_guest_host_spawn() {
    section "Guest host-spawn"

    if container_exec_user 'test -x "$HOME/.local/bin/host-spawn" && "$HOME/.local/bin/host-spawn" --version >/dev/null 2>&1'; then
        ok "host-spawn is already installed."
        return 0
    fi

    local url
    if ! url="$(host_spawn_asset_url)"; then
        warn "No host-spawn release asset is configured for host architecture ${HOST_ARCH}."
        return 1
    fi

    local quoted_url
    quoted_url="$(shell_quote "$url")"
    local install_script
    install_script="$(cat <<EOF_SPAWN_SCRIPT
set -eu
mkdir -p "\$HOME/.local/bin"
tmp="\$HOME/.local/bin/.host-spawn.tmp.\$\$"
trap 'rm -f "\$tmp"' EXIT
if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 ${quoted_url} -o "\$tmp"
elif command -v wget >/dev/null 2>&1; then
    wget -O "\$tmp" ${quoted_url}
else
    echo 'curl or wget is required' >&2
    exit 20
fi
chmod 0755 "\$tmp"
mv -f "\$tmp" "\$HOME/.local/bin/host-spawn"
"\$HOME/.local/bin/host-spawn" --version
EOF_SPAWN_SCRIPT
)"

    if container_exec_user "$install_script"; then
        ok "host-spawn installed (${HOST_SPAWN_VERSION})."
        return 0
    fi

    warn "Could not install host-spawn."
    return 1
}

# -----------------------------------------------------------------------------
# Guest host browser integration
# -----------------------------------------------------------------------------

setup_host_browser_integration() {
    [[ "$BROWSER_INTEGRATION" == 'yes' ]] || return 0

    section "Guest -> Host Browser Links"

    if ! install_guest_host_spawn; then
        warn "Host-browser integration could not be installed."
        return 1
    fi

    local wrapper_script
    wrapper_script="$(cat <<'EOF_BROWSER_SCRIPT'
set -eu
mkdir -p "$HOME/.local/bin" "$HOME/.config/environment.d"

# Route normal web URLs to the HOST browser. Keep non-web paths in the guest.
cat > "$HOME/.local/bin/xdg-open" <<'EOF_OPEN'
#!/bin/sh
set -eu
case "${1:-}" in
    http://*|https://*)
        exec distrobox-host-exec --yes xdg-open "$@"
        ;;
    *)
        exec /usr/bin/xdg-open "$@"
        ;;
esac
EOF_OPEN
chmod 0755 "$HOME/.local/bin/xdg-open"

cat > "$HOME/.config/environment.d/neo-host-browser.conf" <<'EOF_BROWSER_ENV'
PATH="$HOME/.local/bin:$PATH"
BROWSER="$HOME/.local/bin/xdg-open"
EOF_BROWSER_ENV

for rc in "$HOME/.profile" "$HOME/.bashrc"; do
    touch "$rc"
    if ! grep -Fqx 'export PATH="$HOME/.local/bin:$PATH"' "$rc" 2>/dev/null; then
        printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
    fi
done
EOF_BROWSER_SCRIPT
)"

    if container_exec_user "$wrapper_script"; then
        ok "Guest xdg-open host-browser wrapper installed."
    else
        warn "Could not create the guest host-browser wrapper."
        return 1
    fi

    if container_exec_user 'export PATH="$HOME/.local/bin:$PATH"; distrobox-host-exec --yes sh -lc '\''printf "HOST_EXEC_OK"'\'' 2>/dev/null | grep -q HOST_EXEC_OK'; then
        ok "Guest -> host command bridge verified."
    else
        warn "Host execution bridge verification failed."
        return 1
    fi

    if container_exec_user 'test -x "$HOME/.local/bin/xdg-open"'; then
        ok "Host-browser link launcher verified."
    else
        warn "Host-browser launcher verification failed."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Host-side HackerAI deep-link integration
# -----------------------------------------------------------------------------

setup_hackerai_deep_link() {
    [[ "$HACKERAI_DEEP_LINK" == 'yes' ]] || return 0

    section "Host -> HackerAI Deep Links"

    # This handler lives on the HOST because the browser also lives on the
    # host. Registering hackerai:// only inside the guest leaves the browser
    # unable to find the application.
    local handler="$HOME/.local/bin/neo-hackerai-deeplink"
    local desktop="$HOME/.local/share/applications/neo-hackerai.desktop"
    local distrobox_path="$DISTROBOX_BIN"
    local quoted_name
    quoted_name="$(shell_quote "$CONTAINER_NAME")"
    local quoted_distrobox
    quoted_distrobox="$(shell_quote "$distrobox_path")"

    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

    cat > "$handler" <<EOF_HANDLER
#!/bin/sh
set -eu

url="\${1:-}"
case "\$url" in
    hackerai://*) ;;
    *)
        printf '%s\\n' "Unsupported URI: \$url" >&2
        exit 2
        ;;
esac

exec ${quoted_distrobox} enter --name ${quoted_name} -- hackerai-desktop "\$url"
EOF_HANDLER
    chmod 0755 "$handler"

    cat > "$desktop" <<EOF_DESKTOP
[Desktop Entry]
Name=HackerAI (Distrobox)
Comment=Open HackerAI deep links in the Distrobox application
Exec="$handler" %u
Terminal=false
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/hackerai;
Categories=Utility;
EOF_DESKTOP

    if ! need_cmd xdg-mime; then
        host_install_one xdg-utils >/dev/null 2>&1 || true
    fi

    if need_cmd update-desktop-database; then
        update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    fi

    if ! need_cmd xdg-mime; then
        warn "xdg-mime is unavailable; HackerAI deep-link registration cannot be completed."
        return 1
    fi

    if xdg-mime default "$(basename "$desktop")" x-scheme-handler/hackerai; then
        ok "Host hackerai:// handler registered."
    else
        warn "Could not register the hackerai:// handler."
        return 1
    fi

    local registered
    registered="$(xdg-mime query default x-scheme-handler/hackerai 2>/dev/null || true)"
    if [[ "$registered" == "$(basename "$desktop")" ]]; then
        ok "Host hackerai:// MIME mapping verified."
    else
        warn "Host hackerai:// MIME mapping could not be verified."
    fi

    if container_exec_user 'command -v hackerai-desktop >/dev/null 2>&1'; then
        ok "hackerai-desktop is available inside the guest."
    else
        warn "hackerai-desktop is not currently installed in the guest."
        warn "The host handler is registered, but the return-to-app test will only work after HackerAI is installed."
    fi

    ok "Browser -> HackerAI return path configured on the host."
}

# -----------------------------------------------------------------------------
# Ask optional integrations AFTER the guest is ready
# -----------------------------------------------------------------------------

setup_guest_locale
setup_guest_sudo

section "Optional Host Browser Integration"
cat <<'BROWSER_INFO'
GUI applications inside the Distrobox guest can send http:// and https://
links to the host's default browser.

This installs host-spawn inside the guest and a user-writable xdg-open bridge.
It does NOT install a second browser inside the guest.
BROWSER_INFO
read -r -p 'Enable host-browser link opening? [Y/n]: ' browser_answer
browser_answer="${browser_answer:-Y}"
if is_yes "$browser_answer"; then
    BROWSER_INTEGRATION='yes'
    setup_host_browser_integration || warn "Host-browser integration is not fully configured."
fi

section "Optional HackerAI Return Links"
cat <<'HACKERAI_INFO'
HackerAI uses the hackerai:// deep-link scheme.
Because your browser runs on the host, the HOST must register hackerai://
so a browser link can return to HackerAI inside this Distrobox container.
HACKERAI_INFO
read -r -p 'Register HackerAI hackerai:// links on the host? [Y/n]: ' deep_answer
deep_answer="${deep_answer:-Y}"
if is_yes "$deep_answer"; then
    HACKERAI_DEEP_LINK='yes'
    setup_hackerai_deep_link || warn "HackerAI deep-link registration is incomplete."
fi

# -----------------------------------------------------------------------------
# Final validation
# -----------------------------------------------------------------------------

section "Final Validation"

if distrobox list 2>/dev/null | grep -Fq "$CONTAINER_NAME"; then
    ok "Container is registered with Distrobox."
else
    warn "Container is not visible in distrobox list."
fi

local_validation=''
if local_validation="$(run_timeout 60 distrobox enter "$CONTAINER_NAME" -- sh -lc '
    printf "USER=%s\n" "$(id -un)"
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        printf "OS=%s\n" "${PRETTY_NAME:-unknown}"
    fi
    printf "ARCH=%s\n" "$(uname -m)"
    command -v sudo >/dev/null 2>&1 && printf "SUDO=YES\n" || printf "SUDO=NO\n"
' 2>/dev/null)"; then
    printf '%s\n' "$local_validation"
    ok "Guest command execution works."
else
    die "Final guest command validation failed."
fi

if [[ "$ENGINE" == 'podman' ]]; then
    if podman ps --format '{{.Names}}' 2>/dev/null | grep -Fxq "$CONTAINER_NAME"; then
        ok "Guest container is running."
    else
        warn "Guest container is not currently running after validation."
    fi
fi

section "Setup Complete"
ok "Host OS       : ${HOST_NAME}"
ok "Package mgr   : ${HOST_PM:-unknown}"
ok "Engine        : ${ENGINE}"
ok "Guest image   : ${GUEST_IMAGE}"
ok "Container     : ${CONTAINER_NAME}"
ok "Browser bridge: ${BROWSER_INTEGRATION}"
ok "HackerAI link : ${HACKERAI_DEEP_LINK}"
ok "Flatpak       : ${INSTALL_FLATPAK}"
ok "Log file      : ${LOG_FILE}"

printf '\n%s\n' 'Useful commands:'
printf '  distrobox enter %q\n' "$CONTAINER_NAME"
printf '  distrobox list\n'
printf '  distrobox stop %q\n' "$CONTAINER_NAME"
printf '  distrobox rm %q\n' "$CONTAINER_NAME"

printf '\n%s\n' 'Browser integration tests:'
printf '  # from inside the guest:\n'
printf '  export PATH="$HOME/.local/bin:$PATH"\n'
printf '  distrobox-host-exec --yes xdg-open https://github.com\n'
printf '\n%s\n' 'HackerAI return-link test from the host:'
printf '  xdg-open "hackerai://test"\n'

ON_ERROR_ACTIVE='no'
exec distrobox enter "$CONTAINER_NAME"
