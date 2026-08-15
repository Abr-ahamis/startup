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

optional_refresh >/dev/null 2>&1
optional_install curl ca-certificates gnupg unzip jq tar >/dev/null 2>&1

tmpdir="$(mktemp -d)"
OPTIONAL_TMPDIR="$tmpdir"

# -------------------------
# Brave
# -------------------------
if command -v brave-browser >/dev/null 2>&1; then
    log "Brave is already installed: $(command -v brave-browser)"
else
    log "Installing Brave"

    BRAVE_CHANNEL="${BRAVE_CHANNEL:-nightly}"

    case "$BRAVE_CHANNEL" in
        nightly|stable|release) ;;
        *) die "Unsupported BRAVE_CHANNEL: $BRAVE_CHANNEL (use nightly, stable, or release)" ;;
    esac

    if curl -fsS https://dl.brave.com/install.sh | CHANNEL="$BRAVE_CHANNEL" sh; then
        if command -v brave-browser >/dev/null 2>&1; then
            log "Brave installed successfully using Brave's official installer"
        else
            log "Official Brave installer finished, but brave-browser was not found. Falling back to apt repo."
        fi
    fi

    if ! command -v brave-browser >/dev/null 2>&1; then
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

        install -d -m 0755 /usr/share/keyrings
        curl -fsSLo "/usr/share/keyrings/$(basename "$KEYRING_URL")" "$KEYRING_URL"
        curl -fsSLo "/etc/apt/sources.list.d/$(basename "$SOURCES_URL")" "$SOURCES_URL"

        optional_refresh
        optional_install "$PACKAGE"
    fi
fi

# -------------------------
# VS Code
# -------------------------
if command -v code >/dev/null 2>&1; then
    log "VS Code is already installed: $(command -v code)"
else
    log "Installing VS Code"

    arch="$(dpkg --print-architecture)"
    case "$arch" in
        amd64) vscode_arch="x64" ;;
        arm64) vscode_arch="arm64" ;;
        *) die "Unsupported architecture for VS Code: $arch" ;;
    esac

    url="https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-${vscode_arch}"
    deb="$tmpdir/code.deb"

    curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$deb" "$url"
    [[ -s "$deb" ]] || die "VS Code download failed."

    optional_install "$deb"

    command -v code >/dev/null 2>&1 || die "VS Code installation completed, but 'code' was not found."
fi

# -------------------------
# Telegram Desktop
# -------------------------
if command -v telegram-desktop >/dev/null 2>&1 || [[ -x /opt/Telegram/Telegram ]]; then
    log "Telegram Desktop is already installed"
else
    log "Installing Telegram Desktop"

    tg_archive="$tmpdir/tsetup.tar.xz"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$tg_archive" https://telegram.org/dl/desktop/linux

    tar -xJf "$tg_archive" -C "$tmpdir"
    [[ -x "$tmpdir/Telegram/Telegram" ]] || die "Telegram executable was not found after extraction."

    install -d -m 0755 /opt/Telegram
    cp -a "$tmpdir/Telegram/." /opt/Telegram/
    ln -sfn /opt/Telegram/Telegram /usr/local/bin/telegram-desktop

    command -v telegram-desktop >/dev/null 2>&1 || die "Telegram installation completed, but telegram-desktop was not found."
fi

# -------------------------
# RustScan
# -------------------------
if command -v rustscan >/dev/null 2>&1; then
    log "RustScan is already installed: $(command -v rustscan)"
else
    log "Installing RustScan"

    arch="$(dpkg --print-architecture 2>/dev/null || true)"
    [[ "$arch" == amd64 ]] || die "RustScan installer currently supports Debian amd64 only (detected: ${arch:-unknown})."

    rust_json="$(curl -fsSL https://api.github.com/repos/bee-san/RustScan/releases/latest)"
    rust_url="$(printf '%s' "$rust_json" | jq -r '.assets[].browser_download_url' | grep -E 'rustscan_.*_amd64\.deb$' | head -n1 || true)"
    [[ -n "$rust_url" ]] || die "Could not locate a RustScan amd64 .deb asset."

    rust_deb="$tmpdir/rustscan.deb"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$rust_deb" "$rust_url"
    [[ -s "$rust_deb" ]] || die "RustScan download failed."

    optional_install "$rust_deb"

    command -v rustscan >/dev/null 2>&1 || die "RustScan installation completed, but rustscan was not found."
fi

log "All requested apps are installed or were already present."
