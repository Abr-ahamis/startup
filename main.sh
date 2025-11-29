#!/bin/bash

# ============================================================
#  FIXED VERSION — detects if script is already inside startup
#  and only clones when needed.
# ============================================================

# Require sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo"
  exit
fi

# --- Detect working directory ---
SCRIPT_DIR="$(pwd)"

# Check if this directory **is already the startup repo**
if [ -d "$SCRIPT_DIR/i3" ] && [ -d "$SCRIPT_DIR/grub" ] && [ -d "$SCRIPT_DIR/wallpaper" ]; then
    echo "✔ Detected startup folder. Skipping clone."
    STARTUP_DIR="$SCRIPT_DIR"
else
    echo "📁 Not in startup folder. Checking in current directory..."

    # If startup folder exists here
    if [ -d "./startup" ]; then
        echo "✔ Found existing startup folder. Using it."
        STARTUP_DIR="$(pwd)/startup"
    else
        echo "📥 No startup folder found. Cloning from GitHub..."
        git clone https://github.com/Abr-ahamis/startup.git
        STARTUP_DIR="$(pwd)/startup"
    fi
fi

echo "➡ Using startup directory: $STARTUP_DIR"
cd "$STARTUP_DIR"


# ============================================================
#  MAIN SETUP SCRIPT
# ============================================================

sudo apt update && sudo apt upgrade
sudo apt install -y i3-wm i3blocks rofi pkexec polkitd xdotool dex acpi upower xfce4-power-manager \
i3lock xss-lock pulseaudio-utils brightnessctl feh picom fonts-font-awesome git rsync unzip curl wget

# Create dirs
mkdir -p ~/.config/i3 ~/.config/i3blocks/scripts ~/.config/rofi ~/.config/picom
mkdir -p ~/.local/bin ~/.local/share/fonts ~/Pictures
sudo mkdir -p /usr/share/rofi/themes

# Copy config files
sudo cp i3/usr/share/rofi/themes/Adapta-Nokto.rasi /usr/share/rofi/themes/
cp i3/.config/i3/config ~/.config/i3/
cp -r i3/.config/i3blocks/* ~/.config/i3blocks/
cp -r i3/.config/rofi/* ~/.config/rofi/
cp i3/.config/picom/picom.conf ~/.config/picom/
cp -r i3/.local/bin/* ~/.local/bin/
cp -r i3/.local/share/fonts/* ~/.local/share/fonts/

# Wallpapers
cp wallpaper/wallpaper.jpg ~/Pictures/
sudo cp wallpaper/wallpaper.jpg /usr/share/backgrounds/kali/wallpaper.jpg

# Make executables
chmod +x ~/.config/i3blocks/scripts/*.sh
find ~/.config/rofi -type f -name "*.sh" -exec chmod +x {} \;
chmod +x ~/.local/bin/*

fc-cache -fv
i3-msg restart || true

# ============================================================
#  GRUB THEMES
# ============================================================

safe_rm() { [ -e "$1" ] && sudo rm -rf "$1"; }

safe_rm /boot/grub/themes/kali
sudo cp -r grub /boot/grub/themes/kali

safe_rm /usr/share/grub/themes/kali
sudo mkdir -p /usr/share/grub/themes
sudo cp -r /boot/grub/themes/kali /usr/share/grub/themes

# Extra wallpapers
sudo cp wallpaper/wallpaper-1.jpg /usr/share/backgrounds/kali/login.svg || true
sudo cp wallpaper/wallpaper.jpg /usr/share/backgrounds/kali/kali-maze-16x9.jpg || true
sudo cp wallpaper/wallpaper-2.jpg /usr/share/backgrounds/kali/kali-tiles-16x9.jpg || true
sudo cp wallpaper/wallpaper-1.jpg /usr/share/backgrounds/kali/kali-waves-16x9.png || true
sudo cp wallpaper/wallpaper.jpg /usr/share/backgrounds/kali/kali-oleo-16x9.png || true
sudo cp wallpaper/wallpaper-2.jpg /usr/share/backgrounds/kali/kali-tiles-purple-16x9.jpg || true

sudo apt install -y grub-customizer


# ============================================================
#  TELEGRAM
# ============================================================

safe_rm /tmp/tsetup.tar.xz
wget -q https://telegram.org/dl/desktop/linux -O /tmp/tsetup.tar.xz

safe_rm /opt/Telegram
sudo mkdir -p /opt/Telegram
sudo tar -xf /tmp/tsetup.tar.xz -C /opt/Telegram --strip-components=1

sudo chmod +x /opt/Telegram/Telegram
sudo ln -sf /opt/Telegram/Telegram /usr/local/bin/telegram-desktop

/opt/Telegram/Telegram >/dev/null 2>&1 &


# ============================================================
#  BRAVE NIGHTLY
# ============================================================

curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash || true
sudo apt install -y brave-browser-nightly || true


# ============================================================
#  GSETTINGS FAVORITES
# ============================================================

for entry in brave-browser.desktop brave-browser-nightly.desktop brave.desktop; do
    [ -f "/usr/share/applications/$entry" ] && desktop="$entry" && break
done

if [ -n "$desktop" ]; then
    favs=$(gsettings get org.gnome.shell favorite-apps)
    [[ $favs != *"$desktop"* ]] &&
    new=$(echo "$favs" | sed "s/]$/, '$desktop']/") &&
    gsettings set org.gnome.shell favorite-apps "$new"
fi


# ============================================================
#  PROTONVPN
# ============================================================
sudo apt update && sudo apt upgrade 
wget https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb
sudo dpkg -i ./protonvpn-stable-release_1.0.8_all.deb && sudo apt updatesudo apt install proton-vpn-gnome-desktop

# ============================================================
#  VISUAL STUDIO CODE
# ============================================================

cd /tmp
wget -q "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" -O code.deb
sudo dpkg -i code.deb || sudo apt install -f -y
rm code.deb
nohup code >/dev/null 2>&1 &


# ============================================================
#  RUSTSCAN
# ============================================================

cd /tmp
wget -q https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb
sudo dpkg -i rustscan_2.2.3_amd64.deb || sudo apt install -f -y
ulimit -n 5000


sudo apt install -y timeshift grub-customizer

echo "🎉 Setup complete!"
