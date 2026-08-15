#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo -E bash "$0" "$@"
    fi
    die "This script must be run as root or with sudo."
fi

command -v apt-get >/dev/null 2>&1 || die "This script only supports Debian/Ubuntu/Mint (apt)."

export DEBIAN_FRONTEND=noninteractive

BRAVE_CHANNEL="${BRAVE_CHANNEL:-nightly}"

case "$BRAVE_CHANNEL" in
    nightly|stable|release) ;;
    *) die "Unsupported BRAVE_CHANNEL: $BRAVE_CHANNEL (use nightly, stable, or release)" ;;
esac

log "Updating system package lists"
optional_refresh >/dev/null 2>&1

log "Installing prerequisites"
optional_install curl ca-certificates gnupg >/dev/null 2>&1

# First try Brave's official installer script
log "Trying Brave official installer script"
if curl -fsS https://dl.brave.com/install.sh | CHANNEL="$BRAVE_CHANNEL" sh; then
    if command -v brave-browser >/dev/null 2>&1; then
        log "Installed successfully with official installer: $(command -v brave-browser)"
        exit 0
    fi
    log "Official installer finished, but brave-browser was not found. Falling back to apt method."
else
    log "Official installer failed. Falling back to apt method."
fi

# Backup method: Brave apt repository install
case "$BRAVE_CHANNEL" in
    nightly)
        KEYRING_URL="https://brave-browser-apt-nightly.s3.brave.com/brave-browser-nightly-archive-keyring.gpg"
        SOURCES_URL="https://brave-browser-apt-nightly.s3.brave.com/brave-browser.sources"
        PACKAGE="brave-browser-nightly"
        ;;
    stable|release)
        KEYRING_URL="https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"
        SOURCES_URL="https://brave-browser-apt-release.s3.brave.com/brave-browser.sources"
        PACKAGE="brave-browser"
        ;;
esac

log "Adding Brave repository files"
install -d -m 0755 /usr/share/keyrings
curl -fsSLo "/usr/share/keyrings/$(basename "$KEYRING_URL")" "$KEYRING_URL"
curl -fsSLo "/etc/apt/sources.list.d/$(basename "$SOURCES_URL")" "$SOURCES_URL"

log "Refreshing package lists after adding Brave repo"
optional_refresh >/dev/null 2>&1

log "Installing Brave package: $PACKAGE"
optional_install "$PACKAGE" >/dev/null 2>&1

log "Verifying installation"
if command -v brave-browser >/dev/null 2>&1; then
    log "Installed successfully: $(command -v brave-browser)"
else
    die "Brave installation completed, but brave-browser was not found."
fi
