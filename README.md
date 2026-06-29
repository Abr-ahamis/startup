# ==========================================
# 1. Update the system
# ==========================================
sudo apt update
sudo apt upgrade -y

# ==========================================
# 2. Install packages
# ==========================================
sudo apt install -y sway
sudo apt install -y swaybg
sudo apt install -y swayidle
sudo apt install -y swaylock
sudo apt install -y waybar
sudo apt install -y rofi-wayland
sudo apt install -y foot
sudo apt install -y dunst
sudo apt install -y network-manager-gnome
sudo apt install -y blueman
sudo apt install -y gammastep
sudo apt install -y brightnessctl
sudo apt install -y pamixer
sudo apt install -y wl-clipboard
sudo apt install -y grim
sudo apt install -y slurp
sudo apt install -y dex
sudo apt install -y git
sudo apt install -y curl
sudo apt install -y wget
sudo apt install -y unzip
sudo apt install -y pipx

# ==========================================
# 3. Setup pipx and install autotiling
# ==========================================
pipx ensurepath
pipx install autotiling

# ==========================================
# 4. Update GRUB files
# ==========================================
sudo mv /boot/grub /boot/grub.bak
sudo cp -r grub /boot/

# ==========================================
# 5. Remove existing configs
# ==========================================
rm -rf ~/.config/foot
rm -rf ~/.config/i3blocks
rm -rf ~/.config/rofi
rm -rf ~/.config/sway

# ==========================================
# 6. Install config files
# ==========================================
mkdir -p ~/.config
cp -a sway/.config/. ~/.config/

# ==========================================
# 7. Copy local binaries
# ==========================================
mkdir -p ~/.local/bin
cp -a sway/.local/bin/. ~/.local/bin/

# ==========================================
# 8. Copy fonts
# ==========================================
mkdir -p ~/.local/share/fonts
cp -r sway/.local/share/fonts/. ~/.local/share/fonts/

# Refresh font cache
fc-cache -fv

# ==========================================
# 9. Fix permissions
# ==========================================
chmod +x ~/.config/sway/scripts/*.sh 2>/dev/null
chmod +x ~/.config/i3blocks/scripts/bar/*.sh 2>/dev/null
chmod +x ~/.config/i3blocks/scripts/menu/*.sh 2>/dev/null
chmod +x ~/.local/bin/*.sh 2>/dev/null

# ==========================================
# 10. Wallpaper setup
# ==========================================

IMG1="$(pwd)/wallpaper1.jpg"
IMG2="$(pwd)/wallpaper2.jpg"
TARGET_DIR="/usr/share/backgrounds/kali"
BACKUP_DIR="/usr/share/backgrounds/kali.bak"

echo "[*] Checking wallpaper sources..."

if [[ ! -f "$IMG1" ]]; then
    echo "[-] Missing wallpaper: $IMG1"
    exit 1
fi

if [[ ! -f "$IMG2" ]]; then
    echo "[-] Missing wallpaper: $IMG2"
    exit 1
fi

echo "[+] Wallpaper sources found"

echo
echo "[*] Backing up wallpaper directory..."

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "[-] Target wallpaper directory does not exist:"
    echo "    $TARGET_DIR"
    exit 1
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
    if sudo cp -a "$TARGET_DIR" "$BACKUP_DIR"; then
        echo "[+] Wallpaper backup created"
    else
        echo "[!] Failed to create wallpaper backup"
    fi
else
    echo "[+] Wallpaper backup already exists"
fi

echo
echo "[*] Rotating wallpapers..."

mapfile -t files < <(
find "$TARGET_DIR" -maxdepth 1 -type f \
\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \)
)

replaced=()
failed=()
i=0

for file in "${files[@]}"; do

    name=$(basename "$file")

    # Skip static wallpaper until the end
    [[ "$name" == "wallpaper.jpg" ]] && continue

    if (( i % 2 == 0 )); then
        if sudo cp -f "$IMG1" "$file"; then
            echo "[+] Replaced $name with IMG1"
            replaced+=("$name")
        else
            echo "[!] Failed to replace $name"
            failed+=("$name")
        fi
    else
        if sudo cp -f "$IMG2" "$file"; then
            echo "[+] Replaced $name with IMG2"
            replaced+=("$name")
        else
            echo "[!] Failed to replace $name"
            failed+=("$name")
        fi
    fi

    ((i++))
done

if sudo cp -f "$IMG2" "$TARGET_DIR/wallpaper.jpg"; then
    echo "[+] Created/Updated wallpaper.jpg with IMG2"
    replaced+=("wallpaper.jpg (Static IMG2)")
else
    echo "[!] Failed to create wallpaper.jpg"
fi

echo
echo "[✓] Done rotating wallpapers."
echo "=========================================="
echo "Total wallpapers replaced: ${#replaced[@]}"
echo "Failed replacements:        ${#failed[@]}"
echo "=========================================="

echo "Replaced files list:"
for file in "${replaced[@]}"; do
    echo "  - $file"
done

if (( ${#failed[@]} > 0 )); then
    echo
    echo "Failed files:"
    for file in "${failed[@]}"; do
        echo "  - $file"
    done
fi

# ==========================================
# 11. Enable user services
# ==========================================
systemctl --user daemon-reexec
systemctl --user enable --now pipewire pipewire-pulse wireplumber

# ==========================================
# 12. Reload Sway
# ==========================================
if pgrep -x sway >/dev/null; then
    swaymsg reload
fi