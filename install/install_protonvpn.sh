#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
optional_detect
if [[ "$OPTIONAL_PM" != apt ]]; then echo 'Proton VPN GUI is not in Arch official repositories. Use Proton VPN WireGuard/OpenVPN profiles or an AUR package.'; exit 0; fi
optional_install curl
tmpdir="$(mktemp -d)"; OPTIONAL_TMPDIR="$tmpdir"; trap 'rm -rf -- "$tmpdir"' EXIT
tmp="$tmpdir/protonvpn-stable-release_1.0.8_all.deb"
url='https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb'
download_file "$url" "$tmp"
echo '0b14e71586b22e498eb20926c48c7b434b751149b1f2af9902ef1cfe6b03e180  '"$tmp" | sha256sum --check --status || {
  echo 'Proton VPN repository package checksum verification failed.' >&2
  exit 1
}
as_root dpkg -i "$tmp"
optional_refresh
optional_install proton-vpn-gnome-desktop || optional_install proton-vpn-cli
