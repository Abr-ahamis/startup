#!/usr/bin/env bash

set -euo pipefail

if ! command -v gsettings >/dev/null 2>&1 || ! gsettings list-schemas | grep -qx 'org.gnome.Terminal.Legacy.Settings'; then
    exit 0
fi

# Hide the GNOME Terminal menu bar when GNOME Terminal is installed.
gsettings set org.gnome.Terminal.Legacy.Settings default-show-menubar false || exit 0

# Get the default GNOME Terminal profile UUID
PROFILE=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
[[ -n "$PROFILE" ]] || exit 0

# Profile path
PROFILE_PATH="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE}/"

echo "[+] Using profile: $PROFILE"

# Disable theme colors
gsettings set "$PROFILE_PATH" use-theme-colors false || exit 0

# GNOME Terminal profile colors
gsettings set "$PROFILE_PATH" foreground-color '#FFFFFF' || true
gsettings set "$PROFILE_PATH" background-color '#2E3436' || true
gsettings set "$PROFILE_PATH" bold-color '#FF3030' || true
gsettings set "$PROFILE_PATH" cursor-foreground-color '#FFFFFF' || true
gsettings set "$PROFILE_PATH" cursor-background-color '#000000' || true
gsettings set "$PROFILE_PATH" highlight-foreground-color '#000000' || true
gsettings set "$PROFILE_PATH" highlight-background-color '#FCFF00' || true

gsettings set "$PROFILE_PATH" palette \
"['#2E3436', '#FF3030', '#00FF00', '#FFFF00', '#3465A4', '#AD7FA8', '#00FFFF', '#FFFFFF', '#555753', '#FF3030', '#00FF00', '#FFFF00', '#729FCF', '#D3A0D3', '#34E2E2', '#FFFFFF']" || true

# Enable transparency
gsettings set "$PROFILE_PATH" use-transparent-background true || true

# Transparency amount
# 0 = fully transparent
# 100 = fully opaque
# 50 = 50% transparent
gsettings set "$PROFILE_PATH" background-transparency-percent 20 || true

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

echo "[✓] GNOME Terminal configured successfully."
