#!/bin/bash

# ==============================================================================
#  Automated i3 + Rofi + Polybar/i3blocks Setup Script
#  Based on the file structure of https://github.com/Abr-ahamis/new.git
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# --- Variables ---
REPO_URL="https://github.com/Abr-ahamis/new.git"
CLONE_DIR="$HOME/Desktop/new"
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

# Colors for pretty output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==============================================================================
# 1. System Update & Dependencies
# ==============================================================================

log_info "Updating package lists and installing required tools..."

# Update apt
sudo apt update

# Install dependencies
# Added: curl, git, wget, unzip for general utility
REQUIRED_PACKAGES=(
    i3-wm
    i3blocks
    rofi
    pkexec
    polkitd
    xdotool
    dex
    acpi
    upower
    xfce4-power-manager
    i3lock
    xss-lock
    pulseaudio-utils
    brightnessctl
    feh
    picom
    fonts-font-awesome
    git
    rsync
)

sudo apt install -y "${REQUIRED_PACKAGES[@]}"

log_success "Dependencies installed."

# ==============================================================================
# 2. Clone Repository
# ==============================================================================

if [ -d "$CLONE_DIR" ]; then
    log_warn "Directory $CLONE_DIR already exists. Pulling latest changes..."
    cd "$CLONE_DIR" && git pull
else
    log_info "Cloning repository to $CLONE_DIR..."
    git clone "$REPO_URL" "$CLONE_DIR"
fi

# Verify the source directory actually has the files we need
if [ ! -d "$CLONE_DIR/.config" ]; then
    log_error "Source .config folder not found in $CLONE_DIR. Exiting."
    exit 1
fi

# ==============================================================================
# 3. Directory Preparation & Backup
# ==============================================================================

log_info "Preparing directories..."

# Create necessary directories if they don't exist
mkdir -p "$HOME/.config/i3"
mkdir -p "$HOME/.config/i3blocks/scripts"
mkdir -p "$HOME/.config/rofi"
mkdir -p "$HOME/.config/picom"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/fonts"
mkdir -p "$HOME/Pictures" # For wallpaper

# ==============================================================================
# 4. Copying Configuration Files (Using rsync for safety)
# ==============================================================================

log_info "Installing configuration files..."

# 4.1 i3 Config
log_info "-> Installing i3 config..."
rsync -av "$CLONE_DIR/.config/i3/config" "$HOME/.config/i3/config"

# 4.2 i3blocks
log_info "-> Installing i3blocks..."
# Use --delete to ensure clean state, but be careful if you have custom scripts
rsync -av --delete "$CLONE_DIR/.config/i3blocks/" "$HOME/.config/i3blocks/"

# 4.3 Rofi
log_info "-> Installing Rofi theme and scripts..."
rsync -av --delete "$CLONE_DIR/.config/rofi/" "$HOME/.config/rofi/"

# 4.4 Picom
log_info "-> Installing Picom config..."
rsync -av "$CLONE_DIR/.config/picom/picom.conf" "$HOME/.config/picom/picom.conf"

# 4.5 Local Binaries (Powermenu script)
log_info "-> Installing local binaries..."
rsync -av "$CLONE_DIR/.local/bin/" "$HOME/.local/bin/"

# 4.6 Fonts
log_info "-> Installing Fonts..."
rsync -av "$CLONE_DIR/.local/share/fonts/" "$HOME/.local/share/fonts/"

# 4.7 Wallpaper (Copied to ~/Pictures/wallpaper.jpg)
if [ -f "$CLONE_DIR/wallpaper.jpg" ]; then
    log_info "-> Installing Wallpaper..."
    cp "$CLONE_DIR/wallpaper.jpg" "$HOME/Pictures/wallpaper.jpg"
fi

# 4.8 System-wide Rofi Theme (Requires Sudo)
log_info "-> Installing system-wide Rofi theme (Adapta-Nokto)..."
SYSTEM_THEME_DIR="/usr/share/rofi/themes"
if [ -d "$SYSTEM_THEME_DIR" ]; then
    if [ -f "$CLONE_DIR/usr/share/rofi/themes/Adapta-Nokto.rasi" ]; then
        sudo cp "$CLONE_DIR/usr/share/rofi/themes/Adapta-Nokto.rasi" "$SYSTEM_THEME_DIR/"
        log_success "System theme installed."
    else
        log_warn "Adapta-Nokto.rasi not found in source repo structure."
    fi
else
    log_warn "Rofi themes directory ($SYSTEM_THEME_DIR) not found. Is Rofi installed?"
fi

# ==============================================================================
# 5. Permissions & Post-Install Setup
# ==============================================================================

log_info "Setting permissions..."

# Make i3blocks scripts executable
find "$HOME/.config/i3blocks/scripts" -type f -name "*.sh" -exec chmod +x {} \;

# Make Rofi scripts executable (launchers, applets, powermenu)
# This targets all .sh files inside the rofi config recursively
find "$HOME/.config/rofi" -type f -name "*.sh" -exec chmod +x {} \;

# Make local bin scripts executable
find "$HOME/.local/bin" -type f -exec chmod +x {} \;

# Rebuild font cache
log_info "Rebuilding font cache (this may take a moment)..."
fc-cache -fv > /dev/null 2>&1

# ==============================================================================
# 6. Reload & Finalize
# ==============================================================================

log_info "Finalizing..."

# Restart i3 if it is running
if pgrep -x "i3" > /dev/null; then
    log_info "Restarting i3..."
    i3-msg restart
else
    log_info "i3 is not currently running. Changes will take effect on next login."
fi

# Set wallpaper (optional immediate trigger)
if [ -f "$HOME/Pictures/wallpaper.jpg" ] && command -v feh > /dev/null; then
    feh --bg-scale "$HOME/Pictures/wallpaper.jpg"
fi

echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}   Installation Complete!   ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "You may need to log out and log back in for all changes to take full effect."
