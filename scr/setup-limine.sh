#!/usr/bin/env bash 

### Exit immediately if a command exits with a non-zero status

set -e 

### Define paths

IMAGE_SRC="$HOME/Music/IMG.png"
CONF_DIR="/boot/efi/EFI"
CONF_FILE="$CONF_DIR/limine.conf"
IMAGE_DEST="/boot/limine-bg.png" 

### Color outputs

INFO='\033[0;34m[INFO]\033[0m'
SUCCESS='\033[0;32m[SUCCESS]\033[0m'
ERROR='\033[0;31m[ERROR]\033[0m' 

echo -e "${INFO} Starting Limine configuration setup..." 

### 1. Verify source image exists

if [ ! -f "$IMAGE_SRC" ]; then
echo -e "ERROR Source image not found at IMAGE_SRC"
exit 1
fi 

### 2. Copy the background image to /boot

echo -e "INFO Copying background image to IMAGE_DEST..."
sudo cp "
𝐼𝑀𝐴𝐺𝐸𝑆𝑅𝐶

"

"
IMAGE_DEST" 

### 3. Verify limine.conf exists

if [ ! -f "$CONF_FILE" ]; then 

# Fallback check if it's directly in /boot

if [ -f "/boot/limine.conf" ]; then
CONF_FILE="/boot/limine.conf"
else
echo -e "${ERROR} Could not find limine.conf automatically. Please check your path."
exit 1
fi

fi
echo -e "INFO Using configuration file at: CONF_FILE" 

### 4. Modify global settings (Timeout, Default OS, Theme)

echo -e "${INFO} Writing theme and boot preferences to configuration file..." 

### Read the file content, filtering out old global entries to avoid duplicates

sudo sed -i '/^timeout:/d' "$CONF_FILE"
sudo sed -i '/^quiet:/d' "$CONF_FILE"
sudo sed -i '/^default_entry:/d' "$CONF_FILE"
sudo sed -i '/^wallpaper:/d' "$CONF_FILE"
sudo sed -i '/^wallpaper_style:/d' "$CONF_FILE"
sudo sed -i '/^term_background:/d' "$CONF_FILE"
sudo sed -i '/^term_foreground:/d' "$CONF_FILE"
sudo sed -i '/^term_foreground_bright:/d' "$CONF_FILE" 

### Prepend the new global settings to the top of the configuration file

sudo tee /tmp/limine_top.conf > /dev/null << 'EOF' 

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

### Merge the new headers with the rest of the existing entries

sudo cat "$CONF_FILE" >> /tmp/limine_top.conf
sudo mv /tmp/limine_top.conf "$CONF_FILE" 

### 5. Automatically Scan for other OS instances

echo -e "${INFO} Scanning for other operating systems..."
if command -v limine-scan &> /dev/null; then
sudo limine-scan
elif command -v limine-entry-tool &> /dev/null; then
sudo limine-entry-tool --scan
else
echo -e "${INFO} Standard scanner tool not found. Trying os-prober backup method..."
if command -v os-prober &> /dev/null; then
sudo os-prober
fi
fi 

### 6. Finalize changes for CachyOS / Arch infrastructure

if command -v limine-mkinitcpio &> /dev/null; then
echo -e "${INFO} Finalizing Limine entries..."
sudo limine-mkinitcpio
fi 

echo -e "${SUCCESS} Setup complete! Your 3-second timer, background image, and OS discovery configurations are applied."
