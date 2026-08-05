#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
optional_detect; optional_refresh
if [[ "$OPTIONAL_PM" == pacman ]]; then optional_install code; exit 0; fi
optional_install curl
arch="$(dpkg --print-architecture)"
case "$arch" in amd64|arm64) ;; *) echo "VS Code's official Debian package is unsupported on architecture: $arch" >&2; exit 1;; esac
tmpdir="$(mktemp -d)"; OPTIONAL_TMPDIR="$tmpdir"; trap 'rm -rf -- "$tmpdir"' EXIT
tmp="$tmpdir/code_${arch}.deb"
download_file "https://update.code.visualstudio.com/latest/linux-deb-${arch}/stable" "$tmp"
as_root apt-get install -y "$tmp"
command -v code >/dev/null 2>&1 || { echo 'VS Code installation completed but code was not found.' >&2; exit 1; }
