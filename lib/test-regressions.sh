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
source "$SCRIPT_DIR/lib/50-config-files.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

grub_test_tmp="$(mktemp -d)"
trap 'rm -rf -- "$grub_test_tmp"' EXIT
run_as_root() { "$@"; }
grub_prepare_theme_parent "$grub_test_tmp/boot/grub/themes/startup" || fail 'GRUB theme parent could not be created'
[[ -d "$grub_test_tmp/boot/grub/themes" ]] || fail 'missing GRUB themes parent was not created'

SETUP_RUNTIME_DIR="$grub_test_tmp/runtime"
mkdir -p "$SETUP_RUNTIME_DIR"
foot() {
  local config=''
  while (( $# )); do
    case "$1" in
      --config) config="$2"; shift 2;;
      *) shift;;
    esac
  done
  grep -qxF '[colors-dark]' "$config" && return 1
  grep -qxF '[colors]' "$config"
}
prepare_foot_config_source || fail 'legacy Foot parser was not given a compatible config'
[[ "$FOOT_CONFIG_SOURCE" != "$SCRIPT_DIR/sway/.config/foot" ]] || fail 'legacy Foot config did not use an adapted staging tree'
grep -qxF '[colors]' "$FOOT_CONFIG_SOURCE/foot.ini" || fail 'legacy Foot config section was not adapted'
grep -qxF '[colors-dark]' "$SCRIPT_DIR/sway/.config/foot/foot.ini" || fail 'adapter modified the repository config'
foot() { return 0; }
prepare_foot_config_source || fail 'modern Foot config check failed'
[[ "$FOOT_CONFIG_SOURCE" == "$SCRIPT_DIR/sway/.config/foot" ]] || fail 'modern Foot config was unnecessarily adapted'

[[ "$(package_expected_command bluez)" == bluetoothd ]] || fail 'BlueZ must be verified by bluetoothd, not a distro-specific path'

theme='/boot/grub/themes/startup/theme.txt'
grub_cfg_theme_matches "$theme" 'set theme=($root)/grub/themes/startup/theme.txt' || fail 'GRUB root-relative /boot theme reference was rejected'
grub_cfg_theme_matches "$theme" "set theme=$theme" || fail 'literal GRUB theme reference was rejected'
grub_cfg_theme_matches "$theme" 'if background_image "/boot/grub/themes/startup/grub-16x9.png"; then' || fail 'literal GRUB background reference was rejected'
grub_cfg_theme_matches "$theme" 'if background_image "($root)/grub/themes/startup/grub-16x9.png"; then' || fail 'GRUB root-relative background reference was rejected'
if grub_cfg_theme_matches "$theme" 'set theme=($root)/grub/themes/other/theme.txt'; then
  fail 'different GRUB theme reference was accepted'
fi
if grub_cfg_theme_matches "$theme" 'set theme=($root)/boot/grub/themes/startup/theme.txt'; then
  fail 'incorrect root-relative GRUB theme reference was accepted'
fi

# Repository resources are stored under sway/.config and deployed into the
# target user's ~/.config. A stale source path makes every configuration copy
# fail after package installation, so keep the layout contract explicit.
for resource in foot i3blocks sway flameshot wofi systemd startup; do
  [[ -d "$SCRIPT_DIR/sway/.config/$resource" ]] || fail "missing managed resource: sway/.config/$resource"
done
if grep -q 'sway/config/' "$SCRIPT_DIR/lib/50-config-files.sh"; then
  fail 'configuration installer still references the obsolete sway/config source layout'
fi
grep -q '^\[colors-dark\]$' "$SCRIPT_DIR/sway/.config/foot/foot.ini" || fail 'Foot config must use [colors-dark]'
if grep -q '^\[colors\]$' "$SCRIPT_DIR/sway/.config/foot/foot.ini"; then
  fail 'Foot config still uses deprecated [colors]'
fi
grep -q '^bindsym Ctrl+Alt+Delete kill$' "$SCRIPT_DIR/sway/.config/sway/config" || fail 'Ctrl+Alt+Delete must close the focused Sway window directly'
grep -q '"Ctrl + Alt + Delete|Close focused window"' "$SCRIPT_DIR/sway/.config/sway/scripts/key-help-wofi.sh" || fail 'key help does not describe the close-window shortcut'

printf 'Regression checks passed.\n'
