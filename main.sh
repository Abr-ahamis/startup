#!/usr/bin/env bash
set -euo pipefail

# Recreated installer script for https://github.com/Abr-ahamis/startup.git
# - Prompts for sudo up front and keeps it alive while the script runs
# - Uses cp/mkdir/chmod (no rsync)
# - Skips cloning if repository already exists
# - Copies files only when source exists (safe)
# - Attempts best-effort for optional installs; won't abort on those failures

# --------------------------
# Helpers & Logging
# --------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; }

# Run a command but don't fail whole script (used for best-effort ops)
try() { if ! eval "$*"; then warn "Command failed: $*"; fi }

# Safely remove (best-effort)
safe_rm() {
    if [ -e "$1" ]; then
        log "Removing $1"
        sudo rm -rf "$1" || true
    fi
}

# --------------------------
# Request sudo up-front and keep session alive
# --------------------------
if ! command -v sudo >/dev/null 2>&1; then
    err "sudo not found. Please install sudo and re-run this script as root or with sudo."
    exit 1
fi

echo "This script needs sudo privileges. You may be asked for your password."
sudo -v || { err "Unable to obtain sudo credentials."; exit 1; }
# keep-alive: update existing `sudo` time stamp until script finishes
( while true; do sudo -v; sleep 60; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill ${SUDO_KEEPALIVE_PID} 2>/dev/null || true' EXIT

# --------------------------
# Variables
# --------------------------
REPO_URL="https://github.com/Abr-ahamis/startup.git"
CLONE_DIR="$HOME/Downloads/startup"

PACKAGES=(
  i3-wm i3blocks rofi pkexec polkitd xdotool dex acpi upower xfce4-power-manager
  i3lock xss-lock pulseaudio-utils brightnessctl feh picom fonts-font-awesome
  git rsync unzip curl wget grub-customizer timeshift
)

# --------------------------
# System update & package install
# --------------------------
log "Updating package lists..."
sudo apt update -y

log "Installing packages: ${PACKAGES[*]}"
sudo apt install -y "${PACKAGES[@]}" || warn "apt install had some errors; script will continue."

# --------------------------
# Clone or update repo
# --------------------------
mkdir -p "${HOME}/Downloads"
if [ -d "${CLONE_DIR}/.git" ]; then
    log "Repository already exists at ${CLONE_DIR}; pulling latest changes..."
    try git -C "${CLONE_DIR}" pull --ff-only
else
    log "Cloning repository to ${CLONE_DIR}..."
    try git clone "${REPO_URL}" "${CLONE_DIR}"
fi

# Allow script to continue even if clone/pull failed

# --------------------------
# Create target directories (user and system)
# --------------------------
log "Creating configuration directories..."
mkdir -p "$HOME/.config/i3"
mkdir -p "$HOME/.config/i3blocks/scripts"
mkdir -p "$HOME/.config/rofi"
mkdir -p "$HOME/.config/picom"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/fonts"
mkdir -p "$HOME/Pictures"

sudo mkdir -p /usr/share/rofi/themes
sudo mkdir -p /boot/grub/themes
sudo mkdir -p /usr/share/grub/themes || true

# --------------------------
# Copy files from repo to target locations (user-level)
# --------------------------
log "Copying user configuration files (using cp)..."

# Helper to copy if source exists
safe_cp() {
    local src="$1" dest="$2" use_sudo=${3:-0}
    if [ -e "$src" ]; then
        log "Copying: $src -> $dest"
        if [ "$use_sudo" -eq 1 ]; then
            sudo mkdir -p "$(dirname "$dest")"
            sudo cp -r "$src" "$dest"
        else
            mkdir -p "$(dirname "$dest")"
            cp -r "$src" "$dest"
        fi
    else
        warn "Source not found, skipping: $src"
    fi
}

# Rofi system theme (system path)
safe_cp "$CLONE_DIR/usr/share/rofi/themes/Adapta-Nokto.rasi" "/usr/share/rofi/themes/Adapta-Nokto.rasi" 1

# i3 config
safe_cp "$CLONE_DIR/i3/.config/i3/config" "$HOME/.config/i3/config"

# i3blocks
safe_cp "$CLONE_DIR/i3/.config/i3blocks/" "$HOME/.config/i3blocks/"

# rofi
safe_cp "$CLONE_DIR/i3/.config/rofi/" "$HOME/.config/rofi/"

# picom
safe_cp "$CLONE_DIR/i3/.config/picom/picom.conf" "$HOME/.config/picom/picom.conf"

# local bin
safe_cp "$CLONE_DIR/i3/.local/bin/" "$HOME/.local/bin/"

# fonts
safe_cp "$CLONE_DIR/i3/.local/share/fonts/" "$HOME/.local/share/fonts/"

# wallpapers (user)
safe_cp "$CLONE_DIR/wallpaper/wallpaper.jpg" "$HOME/Pictures/wallpaper.jpg"

# wallpapers (system) - many variants; do best-effort copies
log "Copying wallpapers to /usr/share/backgrounds/kali (best-effort)..."
if [ -d "$CLONE_DIR/wallpaper" ]; then
    for f in "$CLONE_DIR/wallpaper"/*; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        sudo cp -f "$f" "/usr/share/backgrounds/kali/$base" 2>/dev/null || warn "Failed copying $f to system backgrounds"
    done
fi

# --------------------------
# GRUB themes
# --------------------------
log "Applying GRUB theme (best-effort)..."
# Remove existing targets then copy
safe_rm /boot/grub/themes/kali
sudo mkdir -p /boot/grub/themes/kali
if [ -d "$CLONE_DIR/grub" ]; then
    sudo cp -r "$CLONE_DIR/grub/." /boot/grub/themes/kali/ || warn "Failed to copy grub theme files"
    sudo mkdir -p /usr/share/grub/themes/kali
    sudo cp -r /boot/grub/themes/kali/. /usr/share/grub/themes/kali/ || warn "Failed to copy grub themes to /usr/share"
else
    warn "No grub theme directory found in repo."
fi

# --------------------------
# Make scripts executable
# --------------------------
log "Setting executable permissions for scripts..."
find "$HOME/.config/i3blocks" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find "$HOME/.config/rofi" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find "$HOME/.local/bin" -type f -exec chmod +x {} \; 2>/dev/null || true

# --------------------------
# Rebuild font cache
# --------------------------
log "Rebuilding font cache..."
fc-cache -fv || warn "fc-cache failed"

# --------------------------
# Restart i3 if running
# --------------------------
if pgrep -x "i3" >/dev/null 2>&1; then
    log "Restarting i3..."
    try i3-msg restart
else
    log "i3 not running; changes will apply at next login."
fi

# Set wallpaper immediately if feh present
if command -v feh >/dev/null 2>&1 && [ -f "$HOME/Pictures/wallpaper.jpg" ]; then
    try feh --bg-scale "$HOME/Pictures/wallpaper.jpg"
fi

# --------------------------
# Telegram (desktop) install to /opt/Telegram
# --------------------------
log "Installing Telegram Desktop (best-effort)..."
TMP_TG="/tmp/tsetup.tar.xz"
try rm -f "$TMP_TG"
try wget -q https://telegram.org/dl/desktop/linux -O "$TMP_TG" || true
if [ -f "$TMP_TG" ]; then
    safe_rm /opt/Telegram
    sudo mkdir -p /opt/Telegram
    sudo tar -xf "$TMP_TG" -C /opt/Telegram --strip-components=1 || warn "Telegram extract failed"
    sudo chmod +x /opt/Telegram/Telegram || true
    if ! command -v telegram-desktop >/dev/null 2>&1; then
        sudo ln -sf /opt/Telegram/Telegram /usr/local/bin/telegram-desktop || true
    fi
    # Launch in background (no hang)
    /opt/Telegram/Telegram >/dev/null 2>&1 &
else
    warn "Telegram package not downloaded; skipping Telegram installation."
fi

# --------------------------
# Brave (nightly) - best-effort install
# --------------------------
log "Installing Brave (nightly) - best-effort..."
try bash -c "curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash" || warn "Brave install script failed"
try sudo apt-get install -y brave-browser-nightly || warn "brave-browser-nightly apt install failed"

# --------------------------
# ProtonVPN (best-effort)
# --------------------------
log "Installing ProtonVPN (best-effort)..."
try wget -q https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb -O /tmp/protonvpn.deb || true
try sudo dpkg -i /tmp/protonvpn.deb || true
try sudo apt update || true
try sudo apt install -y proton-vpn-gnome-desktop libayatana-appindicator3-1 gir1.2-ayatanaappindicator3-0.1 gnome-shell-extension-appindicator || true

# --------------------------
# Visual Studio Code (best-effort)
# --------------------------
log "Installing Visual Studio Code (best-effort)..."
try cd /tmp
try wget -q "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" -O code.deb || true
try sudo dpkg -i code.deb || try sudo apt-get install -f -y || true
try rm -f code.deb || true

# --------------------------
# RustScan (best-effort)
# --------------------------
log "Installing RustScan (best-effort)..."
try cd /tmp
try wget -q https://github.com/RustScan/RustScan/releases/latest/download/rustscan_2.2.3_amd64.deb -O rustscan.deb || true
try sudo dpkg -i rustscan.deb || try sudo apt-get install -f -y || true
try rm -f rustscan.deb || true

# --------------------------
# Final package installs that are safe
# --------------------------
try sudo apt-get install -y grub-customizer timeshift || warn "grub-customizer/timeshift installation had issues"

# --------------------------
# Final message
# --------------------------
log "All done — some operations were best-effort and may have warnings above."
echo
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}   Installation script finished   ${NC}"
echo -e "${GREEN}==========================================${NC}"

echo "If you want any step to be more strict (fail on error) or to change locations, tell me and I will update the script."
