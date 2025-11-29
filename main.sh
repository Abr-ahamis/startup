#!/bin/bash

# make the scrip ask for sudo when it run 
if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo"
  exit
fi

# Update package lists
sudo apt update

# Install all required packages
sudo apt install -y i3-wm i3blocks rofi pkexec polkitd xdotool dex acpi upower xfce4-power-manager i3lock xss-lock pulseaudio-utils brightnessctl feh picom fonts-font-awesome git rsync unzip curl wget

cd ~/Downloads

# check before cloneing the file is not oradey cloned  if it is it jump the cloning 
if [ ! -d startup ]; then
    git clone https://github.com/Abr-ahamis/startup.git
fi

cd startup

# check the folder is orady created 
# creat a script that check 
# it backup the orignale and cope and past it 
# (explanation: you are creating the config directories before copying)

# Create configuration directories
mkdir -p ~/.config/i3
mkdir -p ~/.config/i3blocks/scripts
mkdir -p ~/.config/rofi
mkdir -p ~/.config/picom
mkdir -p ~/.local/bin
mkdir -p ~/.local/share/fonts
sudo mkdir -p /usr/share/rofi/themes

# make sure the files a all coped 
sudo cp i3/usr/share/rofi/themes/Adapta-Nokto.rasi /usr/share/rofi/themes/Adapta-Nokto.rasi
cp i3/.config/i3/config ~/.config/i3/config
cp -r i3/.config/i3blocks/* ~/.config/i3blocks/
cp -r i3/.config/rofi/* ~/.config/rofi/
cp i3/.config/picom/picom.conf ~/.config/picom/picom.conf
cp -r i3/.local/bin/* ~/.local/bin/
cp -r i3/.local/share/fonts/* ~/.local/share/fonts/

cp wallpaper/wallpaper.jpg ~/Pictures/wallpaper.jpg
sudo cp wallpaper/wallpaper.jpg /usr/share/backgrounds/kali/wallpaper.jpg

# Make sure the folder exists
sudo mkdir -p /usr/share/rofi/themes
sudo rm -f /usr/share/rofi/themes/*
# Copy theme if exists
sudo cp i3/usr/share/rofi/themes/Adapta-Nokto.rasi /usr/share/rofi/themes/

# Make i3blocks scripts executable
chmod +x ~/.config/i3blocks/scripts/*.sh

# Make Rofi scripts executable
find ~/.config/rofi -type f -name '*.sh' -exec chmod +x {} \;

# Make local bin scripts executable
chmod +x ~/.local/bin/*

fc-cache -fv

# Restart i3 (if running)
i3-msg restart || true


# 3️⃣ Apply GRUB themes
safe_rm() { [ -e "$1" ] && sudo rm -rf "$1"; }

safe_rm /boot/grub/themes/kali
sudo cp -r grub /boot/grub/themes/kali || echo "⚠️ grub theme copy failed."

safe_rm /usr/share/grub/themes/kali
sudo mkdir -p /usr/share/grub/themes
sudo cp -r /boot/grub/themes/kali /usr/share/grub/themes || echo "⚠️ grub theme copy failed."

# Copy new wallpapers
sudo cp wallpaper/wallpaper-1.jpg /usr/share/backgrounds/kali/login.svg || true
sudo cp wallpaper/wallpaper.jpg /usr/share/backgrounds/kali/kali-maze-16x9.jpg || true
sudo cp wallpaper/wallpaper-2.jpg /usr/share/backgrounds/kali/kali-tiles-16x9.jpg || true
sudo cp wallpaper/wallpaper-1.jpg /usr/share/backgrounds/kali/kali-waves-16x9.png || true
sudo cp wallpaper/wallpaper.jpg /usr/share/backgrounds/kali/kali-oleo-16x9.png || true
sudo cp wallpaper/wallpaper-2.jpg /usr/share/backgrounds/kali/kali-tiles-purple-16x9.jpg || true
sudo cp wallpaper/wallpaper-1.jpg /usr/share/backgrounds/kali/login-blurred || true

sudo apt install -y grub-customizer


# Telegram
safe_rm tsetup.tar.xz
wget -q https://telegram.org/dl/desktop/linux -O /tmp/tsetup.tar.xz

echo "📦 Extracting Telegram..."
safe_rm /opt/Telegram
sudo mkdir -p /opt/Telegram
sudo tar -xf /tmp/tsetup.tar.xz -C /opt/Telegram --strip-components=1

sudo chmod +x /opt/Telegram/Telegram

if ! command -v telegram-desktop >/dev/null 2>&1; then
    sudo ln -sf /opt/Telegram/Telegram /usr/local/bin/telegram-desktop
fi

/opt/Telegram/Telegram >/dev/null 2>&1 &


# Brave Nightly
echo "🦁 Installing Brave Nightly..."
{
    curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash
    sudo apt-get install -y brave-browser-nightly || echo "⚠️ Brave install failed."
} || echo "⚠️ Brave setup script failed."


# Pin Brave in GNOME favorites (fix: gsettings, not gset)
for entry in brave-browser.desktop brave-browser-nightly.desktop brave.desktop; do
    if [ -f "/usr/share/applications/$entry" ]; then
        desktop="$entry"
        break
    fi
done

if [ -n "${desktop:-}" ]; then
    favs=$(gsettings get org.gnome.shell favorite-apps) || favs=""
    if [[ $favs != *"$desktop"* ]]; then
        new=$(echo "$favs" | sed "s/]$/, '$desktop']/") || new="$favs"
        gsettings set org.gnome.shell favorite-apps "$new" || true
    fi
fi


# Install ProtonVPN
echo "🔐 Installing ProtonVPN..."
wget -q https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb -O /tmp/protonvpn.deb || true
sudo dpkg -i /tmp/protonvpn.deb || true
sudo apt update
sudo apt install -y proton-vpn-gnome-desktop libayatana-appindicator3-1 gir1.2-ayatanaappindicator3-0.1 gnome-shell-extension-appindicator || true
nohup protonvpn-app >/dev/null 2>&1 || true


# Install VS Code
echo "💻 Installing Visual Studio Code..."
cd /tmp
wget -q "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" -O code.deb || true
sudo dpkg -i code.deb || sudo apt-get install -f -y || true
rm -f code.deb
nohup code >/dev/null 2>&1 || true


# Install RustScan
echo "🔍 Installing RustScan..."
cd /tmp
wget -q https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb || true
sudo dpkg -i rustscan_2.2.3_amd64.deb || sudo apt-get install -f -y || true
ulimit -n 5000 || true


sudo apt-get install -y grub-customizer timeshift
