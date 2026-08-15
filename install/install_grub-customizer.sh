```bash
#!/usr/bin/env bash

# ==============================================================================
# GRUB Customizer Installer
# ==============================================================================
#
# Purpose:
#   Install GRUB Customizer as one step in a larger installer chain.
#
# Supported:
#   - Debian
#   - Ubuntu
#   - Linux Mint
#   - Kali Linux
#   - Other Debian-family distributions where possible
#   - Arch Linux / Arch-based systems through yay or paru
#
# Important:
#   This script is intended to be executed by another script with:
#
#       ./install_grub_customizer.sh
#
#   or:
#
#       bash install_grub_customizer.sh
#
#   A successful "exit 0" returns control to the parent script.
#   A failed "exit 1" reports failure to the parent script.
#
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# Basic configuration
# ------------------------------------------------------------------------------

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PACKAGE_NAME="grub-customizer"
PPA_NAME="ppa:danielrichter2007/grub-customizer"

# ------------------------------------------------------------------------------
# Colors
# ------------------------------------------------------------------------------

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    CYAN=''
    RESET=''
fi

# ------------------------------------------------------------------------------
# Logging helpers
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
# Locate common.sh
# ------------------------------------------------------------------------------

COMMON_SH="${SCRIPT_DIR}/common.sh"

if [[ -f "$COMMON_SH" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_SH" || {
        error "Failed to source ${COMMON_SH}"
        exit 1
    }
fi

# ------------------------------------------------------------------------------
# Root / sudo handling
# ------------------------------------------------------------------------------

SUDO=""

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SUDO=""
else
    if ! command -v sudo >/dev/null 2>&1; then
        error "This installer requires root privileges or sudo."
        error "Install sudo or run this script as root."
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
# Detect distribution
# ------------------------------------------------------------------------------

DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_VERSION_ID=""
DISTRO_CODENAME=""

detect_distro() {

    if [[ ! -r /etc/os-release ]]; then
        error "/etc/os-release does not exist."
        return 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    DISTRO_ID="${ID:-}"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_VERSION_ID="${VERSION_ID:-}"
    DISTRO_CODENAME="${VERSION_CODENAME:-}"

    if [[ -z "$DISTRO_ID" ]]; then
        error "Unable to determine Linux distribution."
        return 1
    fi

    return 0
}

is_debian_family() {
    [[ "$DISTRO_ID" == "debian" ]] ||
    [[ "$DISTRO_ID" == "ubuntu" ]] ||
    [[ "$DISTRO_ID" == "kali" ]] ||
    [[ "$DISTRO_ID" == "linuxmint" ]] ||
    [[ "$DISTRO_LIKE" == *debian* ]] ||
    [[ "$DISTRO_LIKE" == *ubuntu* ]]
}

is_arch_family() {
    [[ "$DISTRO_ID" == "arch" ]] ||
    [[ "$DISTRO_LIKE" == *arch* ]]
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
# APT lock handling
# ------------------------------------------------------------------------------

wait_for_apt_locks() {

    local max_wait=120
    local waited=0

    info "Checking for active APT/dpkg operations..."

    while true; do

        local locked=0

        if command -v fuser >/dev/null 2>&1; then

            if fuser \
                /var/lib/dpkg/lock-frontend \
                /var/lib/dpkg/lock \
                /var/lib/apt/lists/lock \
                /var/cache/apt/archives/lock \
                >/dev/null 2>&1; then
                locked=1
            fi

        else

            if command -v lsof >/dev/null 2>&1; then
                if lsof \
                    /var/lib/dpkg/lock-frontend \
                    /var/lib/dpkg/lock \
                    /var/lib/apt/lists/lock \
                    /var/cache/apt/archives/lock \
                    >/dev/null 2>&1; then
                    locked=1
                fi
            fi
        fi

        if [[ "$locked" -eq 0 ]]; then
            ok "APT/dpkg locks are available."
            return 0
        fi

        if [[ "$waited" -ge "$max_wait" ]]; then
            error "APT/dpkg is still locked after ${max_wait} seconds."
            error "Another package manager may still be running."
            return 1
        fi

        printf '\r%b[INFO]%b Waiting for APT/dpkg lock... %3ss' \
            "$YELLOW" "$RESET" "$waited"

        sleep 2
        waited=$((waited + 2))
    done

    printf '\n'
}

# ------------------------------------------------------------------------------
# APT repair
# ------------------------------------------------------------------------------

repair_dpkg() {

    info "Checking dpkg state..."

    if ! run_root dpkg --audit >/dev/null 2>&1; then
        warn "dpkg reported an inconsistent package state."
    fi

    if ! run_root dpkg --configure -a; then
        error "dpkg configuration failed."
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Update APT package lists
# ------------------------------------------------------------------------------

apt_update() {

    step "Refreshing APT package lists"

    wait_for_apt_locks || return 1

    if ! run_root apt-get update; then
        error "apt-get update failed."
        return 1
    fi

    ok "APT package lists refreshed."
    return 0
}

# ------------------------------------------------------------------------------
# Check whether APT can see package
# ------------------------------------------------------------------------------

apt_package_available() {

    local package="$1"

    apt-cache policy "$package" 2>/dev/null |
        grep -qE 'Candidate: [^ ]+'

}

# ------------------------------------------------------------------------------
# Install an APT package
# ------------------------------------------------------------------------------

apt_install() {

    local package="$1"

    wait_for_apt_locks || return 1

    if ! run_root apt-get install -y "$package"; then
        error "Failed to install ${package}."
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Install add-apt-repository support when needed
# ------------------------------------------------------------------------------

ensure_add_apt_repository() {

    if command -v add-apt-repository >/dev/null 2>&1; then
        return 0
    fi

    info "add-apt-repository is not installed."
    info "Installing software-properties-common..."

    if ! apt_install software-properties-common; then
        return 1
    fi

    if ! command -v add-apt-repository >/dev/null 2>&1; then
        error "add-apt-repository is still unavailable after installation."
        return 1
    fi

    ok "Repository-management tools installed."
    return 0
}

# ------------------------------------------------------------------------------
# Determine whether PPA is appropriate
# ------------------------------------------------------------------------------

needs_ubuntu_ppa() {

    case "$DISTRO_ID" in

        ubuntu|linuxmint)
            return 0
            ;;

        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Check whether PPA already exists
# ------------------------------------------------------------------------------

ppa_already_configured() {

    local ppa_pattern="danielrichter2007"

    if [[ -d /etc/apt/sources.list.d ]]; then

        if grep -Rqs \
            --include='*.list' \
            --include='*.sources' \
            "$ppa_pattern" \
            /etc/apt/sources.list.d 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# ------------------------------------------------------------------------------
# Add GRUB Customizer PPA
# ------------------------------------------------------------------------------

add_grub_customizer_ppa() {

    step "Configuring GRUB Customizer repository"

    ensure_add_apt_repository || return 1

    if ppa_already_configured; then
        ok "GRUB Customizer PPA is already configured."
        return 0
    fi

    info "Adding ${PPA_NAME}..."

    if ! run_root add-apt-repository -y "$PPA_NAME"; then
        error "Failed to add GRUB Customizer PPA."
        return 1
    fi

    ok "GRUB Customizer PPA added."
    return 0
}

# ------------------------------------------------------------------------------
# Debian-family installation
# ------------------------------------------------------------------------------

install_debian_family() {

    step "Preparing APT installation"

    repair_dpkg || return 1

    # First refresh the normal repositories.
    apt_update || return 1

    # Debian Trixie and other Debian releases may provide grub-customizer
    # directly in their official repositories. Do NOT add an Ubuntu PPA here.
    if apt_package_available "$PACKAGE_NAME"; then

        ok "${PACKAGE_NAME} is available from the configured APT repositories."

    else

        if needs_ubuntu_ppa; then

            warn "${PACKAGE_NAME} is not available from the currently configured Ubuntu/Mint repositories."
            info "Trying the official GRUB Customizer developer PPA."

            add_grub_customizer_ppa || return 1

            apt_update || return 1

        else

            error "${PACKAGE_NAME} is not available from the configured repositories."
            error "Not adding an Ubuntu PPA to ${DISTRO_ID}."

            if [[ "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "kali" ]]; then
                error "Check that the normal Debian/Kali repository components are enabled."
            fi

            return 1
        fi
    fi

    step "Installing ${PACKAGE_NAME}"

    apt_install "$PACKAGE_NAME" || return 1

    return 0
}

# ------------------------------------------------------------------------------
# Arch installation
# ------------------------------------------------------------------------------

install_arch() {

    step "Preparing Arch installation"

    if command -v yay >/dev/null 2>&1; then

        info "Using yay..."
        yay -S --needed --noconfirm "$PACKAGE_NAME" || {
            error "yay failed to install ${PACKAGE_NAME}."
            return 1
        }

    elif command -v paru >/dev/null 2>&1; then

        info "Using paru..."
        paru -S --needed --noconfirm "$PACKAGE_NAME" || {
            error "paru failed to install ${PACKAGE_NAME}."
            return 1
        }

    else

        error "${PACKAGE_NAME} is normally obtained through the Arch AUR."
        error "Neither yay nor paru is installed."
        error "Install yay or paru and rerun this installer."
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Verify installation
# ------------------------------------------------------------------------------

verify_installation() {

    step "Verifying GRUB Customizer installation"

    if ! command -v "$PACKAGE_NAME" >/dev/null 2>&1; then
        error "The package appears to be installed, but ${PACKAGE_NAME} is not in PATH."
        return 1
    fi

    local binary
    binary="$(command -v "$PACKAGE_NAME")"

    ok "GRUB Customizer found: ${binary}"

    if "$binary" --version >/dev/null 2>&1; then

        local version
        version="$("$binary" --version 2>/dev/null | head -n 1)"

        if [[ -n "$version" ]]; then
            ok "Version: ${version}"
        fi
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {

    printf '\n'
    printf '%b==============================================%b\n' "$CYAN" "$RESET"
    printf '%b       GRUB Customizer Installer%b\n' "$CYAN" "$RESET"
    printf '%b==============================================%b\n' "$CYAN" "$RESET"
    printf '\n'

    info "Script: ${SCRIPT_NAME}"
    info "Directory: ${SCRIPT_DIR}"

    # --------------------------------------------------------------------------
    # Already installed?
    # --------------------------------------------------------------------------

    if command -v "$PACKAGE_NAME" >/dev/null 2>&1; then
        ok "GRUB Customizer is already installed."
        verify_installation || true

        printf '\n'
        ok "GRUB Customizer step completed."
        ok "Returning control to the parent installer."
        printf '\n'

        # IMPORTANT:
        # This exits ONLY this child script when invoked as:
        #   ./install_grub_customizer.sh
        #
        # The parent/main script continues with its next command.
        exit 0
    fi

    # --------------------------------------------------------------------------
    # Detect distribution
    # --------------------------------------------------------------------------

    detect_distro || exit 1

    info "Detected distribution: ${DISTRO_ID}"
    [[ -n "$DISTRO_VERSION_ID" ]] &&
        info "Version: ${DISTRO_VERSION_ID}"

    [[ -n "$DISTRO_CODENAME" ]] &&
        info "Codename: ${DISTRO_CODENAME}"

    # --------------------------------------------------------------------------
    # Detect package manager
    # --------------------------------------------------------------------------

    detect_package_manager || exit 1

    info "Package manager: ${PACKAGE_MANAGER}"

    # --------------------------------------------------------------------------
    # Install
    # --------------------------------------------------------------------------

    case "$PACKAGE_MANAGER" in

        apt)

            if ! is_debian_family; then
                warn "APT detected, but the distribution is not recognized as Debian-family."
                warn "Continuing cautiously because APT is available."
            fi

            if ! install_debian_family; then
                error "GRUB Customizer installation failed."
                exit 1
            fi

            ;;

        pacman)

            if ! is_arch_family; then
                warn "pacman detected, but the distribution is not recognized as Arch-family."
            fi

            if ! install_arch; then
                error "GRUB Customizer installation failed."
                exit 1
            fi

            ;;

        *)

            error "Unsupported package manager: ${PACKAGE_MANAGER}"
            exit 1
            ;;
    esac

    # --------------------------------------------------------------------------
    # Verify
    # --------------------------------------------------------------------------

    if ! verify_installation; then
        error "Installation verification failed."
        exit 1
    fi

    # --------------------------------------------------------------------------
    # Success
    # --------------------------------------------------------------------------

    printf '\n'
    printf '%b==============================================%b\n' "$GREEN" "$RESET"
    ok "GRUB Customizer installed successfully."
    ok "Returning control to the parent installer."
    printf '%b==============================================%b\n' "$GREEN" "$RESET"
    printf '\n'

    # --------------------------------------------------------------------------
    # IMPORTANT FOR INSTALLER CHAINS
    #
    # If this file was started by:
    #
    #     ./install_grub_customizer.sh
    #
    # then exit 0 returns success to the parent script.
    #
    # Example parent:
    #
    #     ./install_grub_customizer.sh || exit 1
    #     ./next_script.sh
    #
    # or:
    #
    #     ./install_grub_customizer.sh
    #     ./next_script.sh
    #
    # Do NOT use "source install_grub_customizer.sh" from the parent if this
    # file uses exit, because "exit" would terminate the current shell.
    # --------------------------------------------------------------------------

    exit 0
}

main "$@"
```
