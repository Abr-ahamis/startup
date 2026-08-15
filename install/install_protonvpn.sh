```bash
#!/usr/bin/env bash

# ==============================================================================
# Proton VPN Installer
# ==============================================================================
#
# Installs the official Proton VPN Linux package.
#
# Debian/Ubuntu/Mint/Kali:
#   - Installs Proton's official repository package.
#   - Verifies the repository package SHA-256 checksum.
#   - Repairs interrupted dpkg operations.
#   - Refreshes APT.
#   - Installs the GUI by default.
#   - Optional CLI installation via:
#
#       PROTONVPN_MODE=cli ./install_protonvpn.sh
#
# Arch:
#   - The official Proton VPN CLI is available through pacman.
#   - GUI installation is not attempted automatically here.
#
# Intended to be called from a parent installer as:
#
#     ./install_protonvpn.sh
#
# The child script exits 0 on success, allowing the parent script to continue.
# It exits 1 on failure.
#
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PROTONVPN_MODE="${PROTONVPN_MODE:-gui}"

REPO_PACKAGE="protonvpn-stable-release_1.0.8_all.deb"
REPO_URL="https://repo.protonvpn.com/debian/dists/stable/main/binary-all/${REPO_PACKAGE}"

# This checksum is published by Proton's official installation instructions.
EXPECTED_SHA256="0b14e71586b22e498eb20926c48c7b434b751149b1f2af9902ef1cfe6b03e180"

GUI_PACKAGE="proton-vpn-gnome-desktop"
CLI_PACKAGE="proton-vpn-cli"

# ------------------------------------------------------------------------------
# Colors
# ------------------------------------------------------------------------------

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    RESET=''
fi

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

info() {
    printf '%b[INFO]%b %s\n' "$BLUE" "$RESET" "$*"
}

ok() {
    printf '%b[ OK ]%b %s\n' "$GREEN" "$RESET" "$*"
}

warn() {
    printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$*" >&2
}

error() {
    printf '%b[ERROR]%b %s\n' "$RED" "$RESET" "$*" >&2
}

step() {
    printf '\n%b==>%b %s\n' "$CYAN" "$RESET" "$*"
}

# ------------------------------------------------------------------------------
# Optional common.sh
# ------------------------------------------------------------------------------

COMMON_SH="${SCRIPT_DIR}/common.sh"

if [[ -f "$COMMON_SH" ]]; then
    # shellcheck disable=SC1090
    if ! source "$COMMON_SH"; then
        error "Failed to load common.sh"
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# Privilege handling
# ------------------------------------------------------------------------------

SUDO=""

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SUDO=""
else
    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo is not installed."
        error "Run this installer as root or install sudo first."
        exit 1
    fi

    SUDO="sudo"
fi

run_root() {
    if [[ -n "$SUDO" ]]; then
        "$SUDO" "$@"
    else
        "$@"
    fi
}

# ------------------------------------------------------------------------------
# Temporary directory
# ------------------------------------------------------------------------------

TMPDIR_PATH=""

cleanup() {
    if [[ -n "$TMPDIR_PATH" && -d "$TMPDIR_PATH" ]]; then
        rm -rf -- "$TMPDIR_PATH"
    fi
}

trap cleanup EXIT

# ------------------------------------------------------------------------------
# Distribution detection
# ------------------------------------------------------------------------------

DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_VERSION=""
DISTRO_CODENAME=""

detect_distro() {

    if [[ ! -r /etc/os-release ]]; then
        error "/etc/os-release is missing."
        return 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    DISTRO_ID="${ID:-}"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_VERSION="${VERSION_ID:-}"
    DISTRO_CODENAME="${VERSION_CODENAME:-}"

    if [[ -z "$DISTRO_ID" ]]; then
        error "Unable to determine Linux distribution."
        return 1
    fi

    return 0
}

is_debian_family() {

    case "$DISTRO_ID" in
        debian|ubuntu|linuxmint|kali|pop|elementary|zorin)
            return 0
            ;;
    esac

    [[ "$DISTRO_LIKE" == *debian* || "$DISTRO_LIKE" == *ubuntu* ]]
}

is_arch_family() {

    case "$DISTRO_ID" in
        arch|endeavouros|manjaro)
            return 0
            ;;
    esac

    [[ "$DISTRO_LIKE" == *arch* ]]
}

# ------------------------------------------------------------------------------
# Architecture validation
# ------------------------------------------------------------------------------

check_architecture() {

    local arch

    arch="$(dpkg --print-architecture 2>/dev/null || true)"

    case "$arch" in
        amd64|arm64|i386)
            ok "APT architecture supported: ${arch}"
            return 0
            ;;
        *)
            error "Unsupported or unknown Debian package architecture: ${arch:-unknown}"
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Package manager detection
# ------------------------------------------------------------------------------

PACKAGE_MANAGER=""

detect_package_manager() {

    if command -v apt-get >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
        return 0
    fi

    if command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"
        return 0
    fi

    error "No supported package manager was found."
    return 1
}

# ------------------------------------------------------------------------------
# APT lock detection
# ------------------------------------------------------------------------------

wait_for_apt_locks() {

    local max_wait=180
    local waited=0
    local locked=0

    while (( waited < max_wait )); do

        locked=0

        if command -v fuser >/dev/null 2>&1; then

            if fuser \
                /var/lib/dpkg/lock-frontend \
                /var/lib/dpkg/lock \
                /var/lib/apt/lists/lock \
                /var/cache/apt/archives/lock \
                >/dev/null 2>&1; then
                locked=1
            fi

        elif command -v lsof >/dev/null 2>&1; then

            if lsof \
                /var/lib/dpkg/lock-frontend \
                /var/lib/dpkg/lock \
                /var/lib/apt/lists/lock \
                /var/cache/apt/archives/lock \
                >/dev/null 2>&1; then
                locked=1
            fi

        else
            # No lock-inspection tool. Give the package manager a chance to
            # report the real problem rather than deleting lock files.
            return 0
        fi

        if (( locked == 0 )); then
            return 0
        fi

        printf '\r%b[INFO]%b Waiting for package manager lock... %3ss' \
            "$YELLOW" "$RESET" "$waited"

        sleep 2
        waited=$((waited + 2))
    done

    printf '\n'
    error "APT/dpkg is still locked after ${max_wait} seconds."
    error "Another package-management process may still be running."
    return 1
}

# ------------------------------------------------------------------------------
# Repair dpkg
# ------------------------------------------------------------------------------

repair_dpkg() {

    step "Checking dpkg state"

    wait_for_apt_locks || return 1

    if ! run_root dpkg --configure -a; then
        error "dpkg --configure -a failed."
        return 1
    fi

    ok "dpkg state is healthy."
    return 0
}

# ------------------------------------------------------------------------------
# APT update
# ------------------------------------------------------------------------------

apt_update() {

    step "Refreshing APT package lists"

    wait_for_apt_locks || return 1

    if ! run_root apt-get update; then
        error "apt-get update failed."

        warn "Checking whether this is caused by a broken dpkg state..."

        if ! run_root dpkg --configure -a; then
            error "dpkg repair also failed."
            return 1
        fi

        if ! run_root apt-get update; then
            error "APT update still failed."
            return 1
        fi
    fi

    ok "APT package lists refreshed."
    return 0
}

# ------------------------------------------------------------------------------
# Install APT package
# ------------------------------------------------------------------------------

apt_install() {

    local package="$1"

    wait_for_apt_locks || return 1

    if run_root apt-get install -y "$package"; then
        return 0
    fi

    warn "Initial installation of ${package} failed."
    warn "Attempting to repair dependencies..."

    if ! run_root apt-get -f install -y; then
        error "APT dependency repair failed."
        return 1
    fi

    if ! run_root apt-get install -y "$package"; then
        error "Failed to install ${package}."
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Download tool
# ------------------------------------------------------------------------------

ensure_downloader() {

    if command -v curl >/dev/null 2>&1; then
        return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        return 0
    fi

    case "$PACKAGE_MANAGER" in

        apt)
            info "Neither curl nor wget is installed."
            info "Installing curl..."

            apt_install curl || return 1
            ;;

        pacman)
            info "Neither curl nor wget is installed."
            info "Installing curl..."

            run_root pacman -S --needed --noconfirm curl || return 1
            ;;

        *)
            error "Unable to install a download tool automatically."
            return 1
            ;;
    esac

    command -v curl >/dev/null 2>&1 ||
    command -v wget >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# Download
# ------------------------------------------------------------------------------

download_file() {

    local url="$1"
    local destination="$2"

    info "Downloading:"
    info "$url"

    rm -f -- "$destination"

    if command -v curl >/dev/null 2>&1; then

        if curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --retry 4 \
            --retry-delay 2 \
            --connect-timeout 15 \
            --max-time 300 \
            --output "$destination" \
            "$url"; then
            return 0
        fi

    elif command -v wget >/dev/null 2>&1; then

        if wget \
            --quiet \
            --tries=4 \
            --timeout=30 \
            --output-document="$destination" \
            "$url"; then
            return 0
        fi

    else
        error "No downloader is available."
        return 1
    fi

    error "Download failed."
    return 1
}

# ------------------------------------------------------------------------------
# Checksum
# ------------------------------------------------------------------------------

verify_checksum() {

    local file="$1"

    step "Verifying Proton repository package"

    if ! command -v sha256sum >/dev/null 2>&1; then
        error "sha256sum is not installed."
        return 1
    fi

    local actual

    actual="$(sha256sum "$file" | awk '{print $1}')"

    if [[ "$actual" != "$EXPECTED_SHA256" ]]; then

        error "Checksum verification failed."
        error "Expected: ${EXPECTED_SHA256}"
        error "Actual:   ${actual}"

        return 1
    fi

    ok "Checksum verified."
    return 0
}

# ------------------------------------------------------------------------------
# Detect existing Proton packages
# ------------------------------------------------------------------------------

package_installed() {

    local package="$1"

    dpkg-query \
        -W \
        -f='${Status}\n' \
        "$package" 2>/dev/null |
        grep -q '^install ok installed$'
}

# ------------------------------------------------------------------------------
# Install Proton repository package
# ------------------------------------------------------------------------------

install_proton_repository() {

    step "Installing Proton VPN repository"

    if [[ ! -f "$TMPDIR_PATH/$REPO_PACKAGE" ]]; then
        error "Repository package is missing."
        return 1
    fi

    if ! run_root dpkg -i "$TMPDIR_PATH/$REPO_PACKAGE"; then

        warn "Repository package installation returned an error."
        warn "Attempting to repair dependencies..."

        if ! run_root apt-get -f install -y; then
            error "Failed to repair Proton VPN repository package."
            return 1
        fi

        # Try the repository package once more after dependency repair.
        if ! run_root dpkg -i "$TMPDIR_PATH/$REPO_PACKAGE"; then
            error "Failed to install Proton VPN repository package."
            return 1
        fi
    fi

    ok "Proton VPN repository installed."
    return 0
}

# ------------------------------------------------------------------------------
# Verify repository
# ------------------------------------------------------------------------------

verify_repository() {

    step "Checking Proton VPN repository"

    local repo_found=0

    if [[ -f /etc/apt/sources.list.d/protonvpn-stable.list ]]; then
        repo_found=1
    fi

    if [[ -d /etc/apt/sources.list.d ]]; then

        if grep -Rqs \
            "repo.protonvpn.com" \
            /etc/apt/sources.list.d 2>/dev/null; then
            repo_found=1
        fi
    fi

    if (( repo_found == 0 )); then
        warn "Could not find a Proton VPN repository file."
        warn "The package may have installed it under a different filename."
    else
        ok "Proton VPN repository configuration found."
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Install GUI on Debian-family systems
# ------------------------------------------------------------------------------

install_debian_gui() {

    if package_installed "$GUI_PACKAGE"; then
        ok "Proton VPN GUI package is already installed."
        return 0
    fi

    step "Installing Proton VPN GUI"

    apt_install "$GUI_PACKAGE" || return 1

    if ! package_installed "$GUI_PACKAGE"; then
        error "APT completed but ${GUI_PACKAGE} is not installed."
        return 1
    fi

    ok "Proton VPN GUI installed."
    return 0
}

# ------------------------------------------------------------------------------
# Install CLI on Debian-family systems
# ------------------------------------------------------------------------------

install_debian_cli() {

    if package_installed "$CLI_PACKAGE"; then
        ok "Proton VPN CLI package is already installed."
        return 0
    fi

    step "Installing Proton VPN CLI"

    apt_install "$CLI_PACKAGE" || return 1

    if ! package_installed "$CLI_PACKAGE"; then
        error "APT completed but ${CLI_PACKAGE} is not installed."
        return 1
    fi

    ok "Proton VPN CLI installed."
    return 0
}

# ------------------------------------------------------------------------------
# Arch installation
# ------------------------------------------------------------------------------

install_arch() {

    case "$PROTONVPN_MODE" in

        cli)

            step "Installing Proton VPN CLI on Arch"

            if ! run_root pacman -Syu --needed --noconfirm proton-vpn-cli; then
                error "Failed to install proton-vpn-cli."
                return 1
            fi

            ok "Proton VPN CLI installed."
            ;;

        gui)

            error "Automatic Proton VPN GUI installation is not configured for Arch."
            error "The official Proton documentation provides a pacman installation"
            error "for proton-vpn-cli on Arch."
            error "Use PROTONVPN_MODE=cli for the official CLI package."

            return 1
            ;;

        *)

            error "Invalid PROTONVPN_MODE: ${PROTONVPN_MODE}"
            error "Valid values are: gui or cli"
            return 1
            ;;
    esac

    return 0
}

# ------------------------------------------------------------------------------
# Check GUI desktop environment
# ------------------------------------------------------------------------------

check_gui_environment() {

    if [[ "$PROTONVPN_MODE" != "gui" ]]; then
        return 0
    fi

    if [[ -z "${XDG_CURRENT_DESKTOP:-}" &&
          -z "${DESKTOP_SESSION:-}" ]]; then

        warn "No desktop session was detected."
        warn "The Proton VPN GUI can still be installed, but it may not"
        warn "be usable until a graphical desktop session is running."
    else

        info "Desktop session: ${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Verify installed application
# ------------------------------------------------------------------------------

verify_installation() {

    step "Verifying Proton VPN installation"

    case "$PROTONVPN_MODE" in

        gui)

            if package_installed "$GUI_PACKAGE"; then
                ok "${GUI_PACKAGE} is installed."
                return 0
            fi

            error "Proton VPN GUI verification failed."
            return 1
            ;;

        cli)

            if package_installed "$CLI_PACKAGE"; then
                ok "${CLI_PACKAGE} is installed."
                return 0
            fi

            error "Proton VPN CLI verification failed."
            return 1
            ;;

        *)
            error "Invalid installation mode."
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Main Debian installation
# ------------------------------------------------------------------------------

install_debian_family() {

    check_architecture || return 1

    repair_dpkg || return 1

    ensure_downloader || return 1

    TMPDIR_PATH="$(mktemp -d "${TMPDIR:-/tmp}/protonvpn.XXXXXXXX")" || {
        error "Failed to create temporary directory."
        return 1
    }

    chmod 700 "$TMPDIR_PATH"

    local package_path="${TMPDIR_PATH}/${REPO_PACKAGE}"

    # --------------------------------------------------------------------------
    # Download
    # --------------------------------------------------------------------------

    step "Downloading Proton VPN repository package"

    if ! download_file "$REPO_URL" "$package_path"; then
        return 1
    fi

    if [[ ! -s "$package_path" ]]; then
        error "Downloaded Proton package is empty."
        return 1
    fi

    ok "Repository package downloaded."

    # --------------------------------------------------------------------------
    # Checksum
    # --------------------------------------------------------------------------

    verify_checksum "$package_path" || return 1

    # --------------------------------------------------------------------------
    # Repository install
    # --------------------------------------------------------------------------

    install_proton_repository || return 1

    verify_repository

    # --------------------------------------------------------------------------
    # Refresh APT
    # --------------------------------------------------------------------------

    apt_update || return 1

    # --------------------------------------------------------------------------
    # Install selected application
    # --------------------------------------------------------------------------

    case "$PROTONVPN_MODE" in

        gui)
            install_debian_gui || return 1
            ;;

        cli)
            install_debian_cli || return 1
            ;;

        *)
            error "Invalid PROTONVPN_MODE: ${PROTONVPN_MODE}"
            return 1
            ;;
    esac

    # --------------------------------------------------------------------------
    # Final dependency check
    # --------------------------------------------------------------------------

    step "Running final dependency check"

    if ! run_root apt-get check; then

        warn "APT dependency check reported a problem."
        warn "Attempting automatic repair..."

        if ! run_root apt-get -f install -y; then
            error "Automatic dependency repair failed."
            return 1
        fi

        if ! run_root apt-get check; then
            error "APT dependency check still reports problems."
            return 1
        fi
    fi

    ok "APT dependency state is healthy."

    return 0
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {

    printf '\n'
    printf '%b==============================================%b\n' "$CYAN" "$RESET"
    printf '%b          Proton VPN Installer%b\n' "$CYAN" "$RESET"
    printf '%b==============================================%b\n' "$CYAN" "$RESET"
    printf '\n'

    info "Script: ${SCRIPT_NAME}"
    info "Mode:   ${PROTONVPN_MODE}"

    # --------------------------------------------------------------------------
    # Validate mode
    # --------------------------------------------------------------------------

    case "$PROTONVPN_MODE" in
        gui|cli)
            ;;
        *)
            error "Invalid PROTONVPN_MODE='${PROTONVPN_MODE}'."
            error "Use 'gui' or 'cli'."
            exit 1
            ;;
    esac

    # --------------------------------------------------------------------------
    # Detect OS
    # --------------------------------------------------------------------------

    detect_distro || exit 1

    info "Distribution: ${DISTRO_ID}"

    if [[ -n "$DISTRO_VERSION" ]]; then
        info "Version:      ${DISTRO_VERSION}"
    fi

    if [[ -n "$DISTRO_CODENAME" ]]; then
        info "Codename:     ${DISTRO_CODENAME}"
    fi

    # --------------------------------------------------------------------------
    # Detect package manager
    # --------------------------------------------------------------------------

    detect_package_manager || exit 1

    info "Package manager: ${PACKAGE_MANAGER}"

    # --------------------------------------------------------------------------
    # Already installed
    # --------------------------------------------------------------------------

    if [[ "$PACKAGE_MANAGER" == "apt" ]]; then

        if [[ "$PROTONVPN_MODE" == "gui" ]] &&
           package_installed "$GUI_PACKAGE"; then

            ok "Proton VPN GUI is already installed."
            printf '\n'
            ok "Proton VPN step completed."
            ok "Returning control to the parent installer."
            printf '\n'
            exit 0
        fi

        if [[ "$PROTONVPN_MODE" == "cli" ]] &&
           package_installed "$CLI_PACKAGE"; then

            ok "Proton VPN CLI is already installed."
            printf '\n'
            ok "Proton VPN step completed."
            ok "Returning control to the parent installer."
            printf '\n'
            exit 0
        fi

    elif [[ "$PACKAGE_MANAGER" == "pacman" ]]; then

        if [[ "$PROTONVPN_MODE" == "cli" ]] &&
           pacman -Q "$CLI_PACKAGE" >/dev/null 2>&1; then

            ok "Proton VPN CLI is already installed."
            printf '\n'
            ok "Proton VPN step completed."
            ok "Returning control to the parent installer."
            printf '\n'
            exit 0
        fi

    fi

    # --------------------------------------------------------------------------
    # Installation
    # --------------------------------------------------------------------------

    case "$PACKAGE_MANAGER" in

        apt)

            if ! is_debian_family; then
                warn "APT detected, but this distribution is not recognized"
                warn "as a Debian-family distribution."
                warn "Continuing because APT is available."
            fi

            check_gui_environment

            if ! install_debian_family; then
                error "Proton VPN installation failed."
                exit 1
            fi
            ;;

        pacman)

            if ! is_arch_family; then
                warn "pacman detected, but the distribution is not recognized"
                warn "as Arch-family."
            fi

            if ! install_arch; then
                error "Proton VPN installation failed."
                exit 1
            fi
            ;;

        *)
            error "Unsupported package manager: ${PACKAGE_MANAGER}"
            exit 1
            ;;
    esac

    # --------------------------------------------------------------------------
    # Final verification
    # --------------------------------------------------------------------------

    if ! verify_installation; then
        error "Final Proton VPN verification failed."
        exit 1
    fi

    # --------------------------------------------------------------------------
    # Success
    # --------------------------------------------------------------------------

    printf '\n'
    printf '%b==============================================%b\n' "$GREEN" "$RESET"
    ok "Proton VPN installation completed successfully."
    ok "Mode: ${PROTONVPN_MODE}"
    ok "Returning control to the parent installer."
    printf '%b==============================================%b\n' "$GREEN" "$RESET"
    printf '\n'

    # IMPORTANT:
    #
    # When this script is launched by:
    #
    #     ./install_protonvpn.sh
    #
    # exit 0 terminates THIS child process only.
    #
    # The parent installer receives status 0 and continues.
    #
    # Do not source this script from the parent with:
    #
    #     source ./install_protonvpn.sh
    #
    # because exit 0/1 would then affect the current shell.
    #
    exit 0
}

main "$@"
```
