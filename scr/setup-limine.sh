#!/usr/bin/env bash
# Configure an existing Limine installation. This helper is not run by main.sh.
set -euo pipefail

IMAGE_SRC="${LIMINE_IMAGE_SRC:-$HOME/Music/IMG.png}"
CONF_FILE="${LIMINE_CONF_FILE:-/boot/efi/EFI/limine.conf}"
IMAGE_DEST=/boot/limine-bg.png

info() { printf '\033[0;34m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\033[0;32m[SUCCESS]\033[0m %s\n' "$*"; }
die() { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "$IMAGE_SRC" ]] || die "Source image not found: $IMAGE_SRC"
if [[ ! -f "$CONF_FILE" ]]; then
  [[ -f /boot/limine.conf ]] && CONF_FILE=/boot/limine.conf || die 'Could not find limine.conf; set LIMINE_CONF_FILE to its path.'
fi

info "Copying background image to $IMAGE_DEST"
sudo install -m 644 -- "$IMAGE_SRC" "$IMAGE_DEST"
info "Using configuration file: $CONF_FILE"

# Remove only settings managed by this helper, then prepend their replacements.
sudo sed -i \
  -e '/^timeout:/d' -e '/^quiet:/d' -e '/^default_entry:/d' \
  -e '/^wallpaper:/d' -e '/^wallpaper_style:/d' -e '/^term_background:/d' \
  -e '/^term_foreground:/d' -e '/^term_foreground_bright:/d' \
  -- "$CONF_FILE"

temp="$(mktemp)"
trap 'rm -f -- "$temp"' EXIT
cat >"$temp" <<'EOF'
### --- Global Settings & Theme ---
timeout: 3
quiet: no
default_entry: 1
wallpaper: boot():/limine-bg.png
wallpaper_style: stretched
term_background: 90000000
term_foreground: f3f3f3
term_foreground_bright: fffffff
EOF
sudo cat -- "$CONF_FILE" >>"$temp"
sudo install -m 644 -- "$temp" "$CONF_FILE"

info 'Scanning for other operating systems'
if command -v limine-scan >/dev/null 2>&1; then
  sudo limine-scan
elif command -v limine-entry-tool >/dev/null 2>&1; then
  sudo limine-entry-tool --scan
elif command -v os-prober >/dev/null 2>&1; then
  sudo os-prober
else
  info 'No Limine or os-prober scanner is installed; skipping discovery.'
fi

if command -v limine-mkinitcpio >/dev/null 2>&1; then
  info 'Finalizing Limine entries'
  sudo limine-mkinitcpio
fi

success 'Setup complete.'
