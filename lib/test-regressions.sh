#!/usr/bin/env bash
# Focused offline regression tests for installer verification edge cases.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# These are normally initialized by 00-common.sh. The functions under test do
# not use them, but 20-packages.sh initializes its backup path while loading.
SETUP_BASE_DIR=/tmp/startup-regression-test
SETUP_TIMESTAMP=test
source "$SCRIPT_DIR/lib/20-packages.sh"
source "$SCRIPT_DIR/lib/40-grub.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ "$(package_expected_command bluez)" == bluetoothd ]] || fail 'BlueZ must be verified by bluetoothd, not a distro-specific path'

theme='/boot/grub/themes/startup/theme.txt'
grub_cfg_theme_matches "$theme" 'set theme=($root)/grub/themes/startup/theme.txt' || fail 'GRUB root-relative /boot theme reference was rejected'
grub_cfg_theme_matches "$theme" "set theme=$theme" || fail 'literal GRUB theme reference was rejected'
if grub_cfg_theme_matches "$theme" 'set theme=($root)/grub/themes/other/theme.txt'; then
  fail 'different GRUB theme reference was accepted'
fi
if grub_cfg_theme_matches "$theme" 'set theme=($root)/boot/grub/themes/startup/theme.txt'; then
  fail 'incorrect root-relative GRUB theme reference was accepted'
fi

# Repository resources are stored under sway/config and deployed into the
# target user's ~/.config. A stale source path makes every configuration copy
# fail after package installation, so keep the layout contract explicit.
for resource in foot i3blocks sway flameshot wofi systemd startup; do
  [[ -d "$SCRIPT_DIR/sway/config/$resource" ]] || fail "missing managed resource: sway/config/$resource"
done
if rg -q 'sway/\.config/' "$SCRIPT_DIR/lib/50-config-files.sh"; then
  fail 'configuration installer still references the obsolete sway/.config source layout'
fi

printf 'Regression checks passed.\n'
