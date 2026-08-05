#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
optional_detect
if [[ "$OPTIONAL_PM" != apt ]]; then echo 'Brave is not in Arch official repositories. Use an AUR helper or install Chromium/Firefox instead.'; exit 0; fi
optional_install curl
echo "Installing Brave Nightly from Brave's official repository..."
as_root sh -c 'curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly sh'
command -v brave-browser >/dev/null 2>&1 || {
  echo 'Brave installation completed but brave-browser was not found.' >&2
  exit 1
}
