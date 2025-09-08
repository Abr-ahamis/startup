#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ---------------------------
# Clone the repo
# ---------------------------
git clone https://github.com/Abr-ahamis/startup.git
cd startup || { echo "Failed to enter startup folder"; exit 1; }

# ---------------------------
# Backup and copy GRUB themes
# ---------------------------
sudo mkdir -p /boot/grub/themes/backup
sudo mkdir -p /usr/share/grub/themes/backup

if [ -d /boot/grub/themes/kali ]; then
    sudo mv /boot/grub/themes/kali /boot/grub/themes/backup/kali.b
fi
sudo cp -r kali /boot/grub/themes/

if [ -d /usr/share/grub/themes/kali ]; then
    sudo mv /usr/share/grub/themes/kali /usr/share/grub/themes/backup/kali.b
fi
sudo cp -r /boot/grub/themes/kali /usr/share/grub/themes/
# ---------------------------
sudo mv /boot/grub/grub.cfg /boot/grub/grub.cfg.b
sudo cp grub.cfg /boot/grub/
# ---------------------------

# ---------------------------
# Backup and copy wallpapers
# ---------------------------
cd wallpaper || { echo "Failed to enter wallpaper folder"; exit 1; }
sudo mkdir -p /usr/share/backgrounds/kali/backup

for file in kali-maze-16x9.jpg kali-tiles-16x9.jpg kali-oleo-16x9.png kali-tiles-purple-16x9.jpg kali-waves-16x9.png login.svg login-blurred; do
    if [ -f "/usr/share/backgrounds/kali/$file" ]; then
        sudo mv "/usr/share/backgrounds/kali/$file" "/usr/share/backgrounds/kali/backup/$file.b"
    fi
done

# Copy new wallpapers
sudo cp 20-wallpaper.svg /usr/share/backgrounds/kali/login.svg
sudo cp 12-wallpaper.png /usr/share/backgrounds/kali/kali-maze-16x9.jpg
sudo cp 1-wallpaper.png /usr/share/backgrounds/kali/kali-tiles-16x9.jpg
sudo cp 2-wallpaper.png /usr/share/backgrounds/kali/kali-waves-16x9.png
sudo cp 3-wallpaper.png /usr/share/backgrounds/kali/kali-oleo-16x9.png
sudo cp 4-wallpaper.png /usr/share/backgrounds/kali/kali-tiles-purple-16x9.jpg

# ---------------------------
# Apply GNOME Tweaks
# ---------------------------
gsettings set org.gnome.desktop.interface font-name 'Conifer 11'
gsettings set org.gnome.desktop.interface text-scaling-factor 0.95
gsettings set org.gnome.desktop.background picture-options 'zoom'

echo "✅ GNOME Tweaks settings applied:"
gsettings get org.gnome.desktop.interface font-name
gsettings get org.gnome.desktop.interface text-scaling-factor
gsettings get org.gnome.desktop.background picture-options

# ---------------------------
# Configure Dash-to-Dock
# ---------------------------
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'LEFT'
gsettings set org.gnome.shell.extensions.dash-to-dock autohide true
gsettings set org.gnome.shell.extensions.dash-to-dock animation-time 0.0
gsettings set org.gnome.shell.extensions.dash-to-dock hide-delay 0.0
gsettings set org.gnome.shell.extensions.dash-to-dock pressure-threshold 0.0
gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 20

echo "✅ Dash to Dock configured:"
gsettings get org.gnome.shell.extensions.dash-to-dock dock-position
gsettings get org.gnome.shell.extensions.dash-to-dock autohide
gsettings get org.gnome.shell.extensions.dash-to-dock animation-time
gsettings get org.gnome.shell.extensions.dash-to-dock hide-delay
gsettings get org.gnome.shell.extensions.dash-to-dock pressure-threshold
gsettings get org.gnome.shell.extensions.dash-to-dock dash-max-icon-size

# ---------------------------
# Install Brave (Nightly)
# ---------------------------
curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly sh

# Detect Brave .desktop filename
desktop=""
for f in brave-browser.desktop brave-browser-nightly.desktop brave.desktop; do
    if [ -f "/usr/share/applications/$f" ]; then
        desktop="$f"
        break
    fi
done

if [ -z "$desktop" ]; then
    echo "Could not find Brave .desktop file in /usr/share/applications/"
    exit 1
fi

favs=$(gsettings get org.gnome.shell favorite-apps)
if ! echo "$favs" | grep -q "$desktop"; then
    # Add Brave to favorites safely
    new=$(echo "$favs" | sed "s/]$/, '$desktop']/")
    gsettings set org.gnome.shell favorite-apps "$new"
fi

echo "✅ Brave installed and pinned."

# ---------------------------
# Install Telegram Desktop
# ---------------------------
cd /tmp
url=$(wget -qO- https://telegram.org/dl/desktop/linux | grep -oP 'https://telegram.org/dl/desktop/linux/tsetup\.\d+\.\d+\.\d+\.tar\.xz' | head -n 1)
echo "Downloading Telegram: $url"
wget -q "$url" -O tsetup_latest.tar.xz

sudo rm -rf /opt/Telegram
sudo mkdir -p /opt/Telegram
sudo tar -xf tsetup_latest.tar.xz -C /opt/Telegram --strip-components=1

# Run Telegram as current user
chmod +x /opt/Telegram/Telegram
nohup /opt/Telegram/Telegram &>/dev/null &

echo "✅ Telegram installed."

# ---------------------------
# Install ProtonVPN
# ---------------------------
wget https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb -O /tmp/protonvpn-release.deb
sudo dpkg -i /tmp/protonvpn-release.deb
sudo apt update
sudo apt install -y protonvpn-gnome-desktop \
libayatana-appindicator3-1 gir1.2-ayatanaappindicator3-0.1 gnome-shell-extension-appindicator

nohup protonvpn-app &>/dev/null &

echo "✅ ProtonVPN installed."

# ---------------------------
# Install RustScan
# ---------------------------
wget https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb -O /tmp/rustscan.deb
sudo dpkg -i /tmp/rustscan.deb
sudo apt-get install -f -y
ulimit -n 5000

echo "✅ RustScan installed."

# ---------------------------
# Install VS Code
# ---------------------------
cd /tmp
wget -q "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" -O code.deb
sudo dpkg -i code.deb || sudo apt-get install -f -y
rm -f code.deb
nohup code &>/dev/null &

echo "✅ VS Code installed."

# ---------------------------
# Prompt before reboot
# ---------------------------
read -p "Installation complete. Reboot now? (y/N) " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Reboot skipped. You may need to log out/in for some settings to take effect."
fi
