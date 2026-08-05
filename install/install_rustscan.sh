#!/usr/bin/env bash
set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

optional_detect || exit 1

if [[ "$OPTIONAL_PM" != apt ]]; then
  echo "RustScan is not installed from Arch official repositories; use a trusted AUR package or upstream binary." >&2
  exit 0
fi

optional_refresh
optional_install curl unzip jq

arch="$(dpkg --print-architecture 2>/dev/null || true)"
[[ "$arch" == amd64 ]] || {
  echo "RustScan installer currently supports Debian amd64 only (detected: ${arch:-unknown})." >&2
  exit 1
}

tmpdir="$(mktemp -d)"
OPTIONAL_TMPDIR="$tmpdir"
archive="$tmpdir/rustscan.deb.zip"
trap 'rm -rf -- "$tmpdir"' EXIT

url="$(github_latest_asset_url bee-san/RustScan rustscan.deb.zip || true)"
url="${url:-https://github.com/bee-san/RustScan/releases/download/2.4.1/rustscan.deb.zip}"
download_file "$url" "$archive" || {
  echo 'RustScan download failed.' >&2
  exit 1
}

unzip -q -o "$archive" -d "$tmpdir" || {
  echo 'RustScan archive extraction failed.' >&2
  exit 1
}

deb="$(find "$tmpdir" -maxdepth 1 -type f -name 'rustscan_*_amd64.deb' -print -quit)"
[[ -n "$deb" ]] || {
  echo 'RustScan archive did not contain an amd64 Debian package.' >&2
  exit 1
}

if ! as_root apt-get install -y "$deb"; then
  echo 'RustScan installation failed.' >&2
  exit 1
fi

command -v rustscan >/dev/null 2>&1 && echo 'RustScan installed successfully.' || {
  echo 'RustScan package installation completed but the command was not found.' >&2
  exit 1
}
