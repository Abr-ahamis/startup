#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
optional_detect; optional_refresh
kernel="$(uname -r)"
case "$OPTIONAL_PM" in
  apt)
    optional_install build-essential dkms "linux-headers-$kernel" || optional_install linux-headers-amd64 || optional_install linux-headers-generic
    optional_install virtualbox virtualbox-dkms
    ;;
  pacman)
    if [[ "$kernel" == *arch* ]]; then optional_install linux-headers virtualbox virtualbox-host-modules-arch; else optional_install linux-headers virtualbox virtualbox-host-dkms dkms; fi
    ;;
esac
if getent group vboxusers >/dev/null && ! id -nG "$target_user" | tr ' ' '\n' | grep -qx vboxusers; then as_root usermod -aG vboxusers "$target_user"; echo "Added $target_user to vboxusers; log out and back in."; fi
