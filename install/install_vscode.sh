#!/usr/bin/env bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

log() {
    printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo -E bash "$0" "$@"
    else
        die "sudo is required. Run this script as root."
    fi
fi

command -v apt-get >/dev/null 2>&1 || \
    die "This script requires an apt-based system."

export DEBIAN_FRONTEND=noninteractive

log "Updating package lists..."
optional_refresh >/dev/null 2>&1

log "Installing required packages..."
optional_install curl ca-certificates >/dev/null 2>&1

arch="$(dpkg --print-architecture)"

case "$arch" in
    amd64)
        vscode_arch="x64"
        ;;
    arm64)
        vscode_arch="arm64"
        ;;
    *)
        die "Unsupported architecture: $arch"
        ;;
esac

url="https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-${vscode_arch}"

tmpdir="$(mktemp -d)"
OPTIONAL_TMPDIR="$tmpdir"

deb="$tmpdir/code.deb"

log "Downloading VS Code..."
curl \
    --fail \
    --location \
    --show-error \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --output "$deb" \
    "$url" >/dev/null 2>&1

[[ -s "$deb" ]] || die "VS Code download failed."

log "Installing VS Code..."
optional_install "$deb" >/dev/null 2>&1

log "Verifying installation..."

if command -v code >/dev/null 2>&1; then
    printf '\nVS Code installed successfully.\n'
    printf 'Location: %s\n' "$(command -v code)"
    printf 'Version: '
    code --version | head -n 1
else
    die "VS Code installation completed, but 'code' was not found."
fi
