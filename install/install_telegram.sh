#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
optional_detect
optional_install wget

tmpdir="$(mktemp -d)"
OPTIONAL_TMPDIR="$tmpdir"
trap 'rm -rf -- "$tmpdir"' EXIT

echo "Installing Telegram Desktop from Telegram's official download..."
cd "$tmpdir"
wget -O tsetup.tar.xz https://telegram.org/dl/desktop/linux

if ! file tsetup.tar.xz | grep -qi 'XZ compressed data'; then
  echo 'The downloaded Telegram archive could not be verified as an XZ archive.' >&2
  exit 1
fi

tar -xf tsetup.tar.xz

if [[ ! -x "$tmpdir/Telegram" ]]; then
  echo 'Telegram executable was not found after extraction.' >&2
  exit 1
fi

as_root mkdir -p /opt
as_root cp -a "$tmpdir/Telegram" /opt/
as_root ln -sfn /opt/Telegram /usr/local/bin/telegram-desktop

run_as_target mkdir -p "$HOME/.local/bin" 2>/dev/null || true
register_gnome_keybinding "startup-telegram" "<Super>t" "Telegram" "/usr/local/bin/telegram-desktop" >/dev/null 2>&1 || true

echo 'Starting Telegram Desktop...'
run_as_target sh -c 'cd /opt/Telegram && ./Telegram >/dev/null 2>&1 &'
