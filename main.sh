#!/usr/bin/env bash
# ai3-setup.sh - Simple, linear Bash script implementing the uploaded "note"
# Author: Neo (10 years experience) - simple style, basic commands only.
# IMPORTANT: set REPO_URL below if you need the script to clone the repo.

REPO_URL="https://github.com/Abr-ahamis/startup.git"                 # <- PUT your git repo URL here if needed
REPO_DIR="startup"
APT_PACKAGES="i3-wm i3blocks rofi picom feh brightnessctl pulseaudio-utils xss-lock i3lock dex fonts-font-awesome git curl wget unzip rsync timeshift grub-custmizer"
HOME_DIR="$HOME"

# If not root, use sudo where needed
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

echo "=== AI3 setup script (simple) ==="

# 1) Initialization and Repository Check
echo "--> Checking repository presence: $REPO_DIR"
if [ ! -d "$REPO_DIR" ]; then
  if [ -z "$REPO_URL" ]; then
    echo "ERROR: $REPO_DIR not found and REPO_URL is empty. Set REPO_URL at top of script to clone."
    exit 1
  fi
  echo "Cloning repo from $REPO_URL ..."
  git clone "$REPO_URL" "$REPO_DIR" || { echo "git clone failed"; exit 1; }
else
  echo "Repo $REPO_DIR exists."
fi

# 2) Dependency Installation
echo "--> Updating apt and installing packages"
$SUDO apt update
$SUDO apt install -y $APT_PACKAGES

# Helper: simple mkdir -p for destinations
mkdir_p() {
  mkdir -p "$1"
}

# 3) Configuration File Management
echo "--> Copying configuration files (overwrites existing as note requests)"

# 3.1 i3 config
mkdir -p "$HOME_DIR/.config/i3"
if [ -f "$HOME_DIR/.config/i3/config" ]; then
  rm -f "$HOME_DIR/.config/i3/config"
fi
cp -a "$REPO_DIR/i3/.config/i3/config" "$HOME_DIR/.config/i3/config" || echo "Warning: i3 config copy failed"

# 3.2 i3 scripts
rm -rf "$HOME_DIR/.config/i3/scripts"
mkdir -p "$HOME_DIR/.config/i3/scripts"
cp -a "$REPO_DIR/i3/.config/i3/scripts/"* "$HOME_DIR/.config/i3/scripts/" 2>/dev/null || true
chmod 755 "$HOME_DIR/.config/i3/scripts/"* 2>/dev/null || true

# 3.3 i3blocks
rm -rf "$HOME_DIR/.config/i3blocks"
mkdir -p "$HOME_DIR/.config/i3blocks"
cp -a "$REPO_DIR/i3/.config/i3blocks/"* "$HOME_DIR/.config/i3blocks/" 2>/dev/null || true

# 3.4 rofi
rm -rf "$HOME_DIR/.config/rofi"
mkdir -p "$HOME_DIR/.config/rofi"
cp -a "$REPO_DIR/i3/.config/rofi/"* "$HOME_DIR/.config/rofi/" 2>/dev/null || true

# remove files in /usr/share/rofi/themes/* and install repo theme
if [ -d "/usr/share/rofi/themes" ]; then
  $SUDO rm -f /usr/share/rofi/themes/*
else
  $SUDO mkdir -p /usr/share/rofi/themes
fi
if [ -f "$REPO_DIR/i3/usr/share/rofi/themes/Adapta-Nokto.rasi" ]; then
  $SUDO cp "$REPO_DIR/i3/usr/share/rofi/themes/Adapta-Nokto.rasi" /usr/share/rofi/themes/Adapta-Nokto.rasi
fi

# 3.5 picom
mkdir -p "$HOME_DIR/.config/picom"
rm -f "$HOME_DIR/.config/picom/picom.conf"
cp -a "$REPO_DIR/i3/.config/picom/picom.conf" "$HOME_DIR/.config/picom/picom.conf" 2>/dev/null || true

# 3.6 local binaries
rm -rf "$HOME_DIR/.local/bin"
mkdir -p "$HOME_DIR/.local/bin"
cp -a "$REPO_DIR/i3/.local/bin/"* "$HOME_DIR/.local/bin/" 2>/dev/null || true
chmod 755 "$HOME_DIR/.local/bin/"* 2>/dev/null || true

# 3.7 fonts
rm -rf "$HOME_DIR/.local/share/fonts"
mkdir -p "$HOME_DIR/.local/share/fonts"
cp -a "$REPO_DIR/i3/.local/share/fonts/"* "$HOME_DIR/.local/share/fonts/" 2>/dev/null || true

# 3.8 Battery monitoring service files
mkdir -p "$HOME_DIR/.config/systemd/user"
rm -f "$HOME_DIR/.config/systemd/user/battery-monitor.sh"
rm -f "$HOME_DIR/.config/systemd/user/battery-monitor.service"
cp -a "$REPO_DIR/i3/.config/systemd/user/battery-monitor.sh" "$HOME_DIR/.config/systemd/user/battery-monitor.sh" 2>/dev/null || true
cp -a "$REPO_DIR/i3/.config/systemd/user/battery-monitor.service" "$HOME_DIR/.config/systemd/user/battery-monitor.service" 2>/dev/null || true
chmod 755 "$HOME_DIR/.config/systemd/user/battery-monitor.sh" 2>/dev/null || true

# 5) Battery Monitoring Service - reload and restart user service
echo "--> Reloading user systemd and restarting battery-monitor.service (if applicable)"
# Attempt to reload user systemd (works if run as the user)
if systemctl --user status >/dev/null 2>&1; then
  systemctl --user daemon-reexec || true
  systemctl --user daemon-reload || true
  systemctl --user restart battery-monitor.service || true
else
  echo "Note: systemctl --user not available in this environment; run the above commands as the target user if needed."
fi

# 6) Wallpapers
echo "--> Installing wallpapers"
mkdir -p "$HOME_DIR/Pictures"
mkdir -p /usr/share/backgrounds/kali 2>/dev/null || true

# local copies to ~/Pictures
for f in wallpaper.jpg wallpaper-1.jpg wallpaper-2.jpg; do
  if [ -f "$REPO_DIR/wallpaper/$f" ]; then
    rm -f "$HOME_DIR/Pictures/$f"
    cp -a "$REPO_DIR/wallpaper/$f" "$HOME_DIR/Pictures/$f"
  fi
done

# system wallpapers mapping with renames and timestamp backups
TS=$(date +%s)
backup_and_copy() {
  dest="$1"
  src="$2"
  if [ -f "$dest" ]; then
    $SUDO mv "$dest" "${dest}.$TS.bak" || true
  fi
  $SUDO cp -a "$src" "$dest"
}

# Map per the note
if [ -f "$REPO_DIR/wallpaper/wallpaper-1.jpg" ]; then
  backup_and_copy "/usr/share/backgrounds/kali/login.svg" "$REPO_DIR/wallpaper/wallpaper-1.jpg"
fi
if [ -f "$REPO_DIR/wallpaper/wallpaper.jpg" ]; then
  backup_and_copy "/usr/share/backgrounds/kali/kali-maze-16x9.jpg" "$REPO_DIR/wallpaper/wallpaper.jpg"
fi
if [ -f "$REPO_DIR/wallpaper/wallpaper-2.jpg" ]; then
  backup_and_copy "/usr/share/backgrounds/kali/kali-tiles-16x9.jpg" "$REPO_DIR/wallpaper/wallpaper-2.jpg"
fi
if [ -f "$REPO_DIR/wallpaper/wallpaper-1.jpg" ]; then
  backup_and_copy "/usr/share/backgrounds/kali/kali-waves-16x9.png" "$REPO_DIR/wallpaper/wallpaper-1.jpg"
fi
if [ -f "$REPO_DIR/wallpaper/wallpaper.jpg" ]; then
  backup_and_copy "/usr/share/backgrounds/kali/kali-oleo-16x9.png" "$REPO_DIR/wallpaper/wallpaper.jpg"
fi
if [ -f "$REPO_DIR/wallpaper/wallpaper-2.jpg" ]; then
  backup_and_copy "/usr/share/backgrounds/kali/kali-tiles-purple-16x9.jpg" "$REPO_DIR/wallpaper/wallpaper-2.jpg"
fi
if [ -f "$REPO_DIR/wallpaper/wallpaper-1.jpg" ]; then
  backup_and_copy "/usr/share/backgrounds/kali/login-blurred" "$REPO_DIR/wallpaper/wallpaper-1.jpg"
fi

# 7) GRUB Themes
echo "--> Installing GRUB themes"
$SUDO mkdir -p /boot/grub/themes/kali 2>/dev/null || true
$SUDO mkdir -p /usr/share/grub/themes 2>/dev/null || true
$SUDO rm -f /boot/grub/themes/kali/* 2>/dev/null || true
$SUDO rm -f /usr/share/grub/themes/* 2>/dev/null || true
if [ -d "$REPO_DIR/grub" ]; then
  $SUDO cp -a "$REPO_DIR/grub/"* /boot/grub/themes/kali/ 2>/dev/null || true
  $SUDO cp -a "$REPO_DIR/grub/"* /usr/share/grub/themes/ 2>/dev/null || true
fi

# 8) Finalization
echo "--> Finalizing: making scripts executable and restarting i3 if running"
chmod +x "$HOME_DIR/.config/i3/scripts/"* 2>/dev/null || true
chmod +x "$HOME_DIR/.local/bin/"* 2>/dev/null || true

if command -v i3-msg >/dev/null 2>&1; then
  i3-msg restart || true
fi

# 9) Menu for optional app installs (simple choice)
echo
echo "=== Optional app installation menu ==="
echo "Choose apps to install:"
echo "1) Telegram binary"
echo "2) Brave Nightly"
echo "3) Visual Studio Code"
echo "4) ProtonVPN"
echo "5) VirtualBox"
echo "6) RustScan"
echo "7) Spotify"
echo "a) all"
echo "n) none"
read -p "Select (e.g. 1 or 1 2 3) or 'a' for all or 'n' for none: " CHOICE

# Normalize input
if [ "$CHOICE" = "a" ]; then
  CHOICE="1 2 3 4 5 6 7"
fi

if [ "$CHOICE" != "n" ]; then
  for item in $CHOICE; do
    case "$item" in
      1)
        echo "--> Installing Telegram binary (repo -> /usr/local/bin/telegram)"
        if [ -f "$REPO_DIR/i3/.local/bin/Telegram" ]; then
          $SUDO rm -f /usr/local/bin/telegram 2>/dev/null || true
          $SUDO cp -a "$REPO_DIR/i3/.local/bin/Telegram" /usr/local/bin/telegram
          $SUDO chmod 755 /usr/local/bin/telegram
        else
          echo "Telegram binary not found in repo."
        fi
        ;;
      2)
        echo "--> Installing Brave Nightly"
        # As in note: official install script with CHANNEL=nightly
        curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash || echo "Brave install script failed"
        $SUDO apt install -y brave-browser-nightly || true
        ;;
      3)
        echo "--> Installing Visual Studio Code"
        TMP="/tmp/code.deb"
        rm -f "$TMP"
        # official stable download URL
        curl -L -o "$TMP" "https://update.code.visualstudio.com/latest/linux-deb-x64/stable"
        $SUDO dpkg -i "$TMP" || true
        $SUDO apt install -f -y || true
        rm -f "$TMP"
        ;;
      4)
        echo "--> Installing ProtonVPN (deb + dependencies)"
        TMP="/tmp/protonvpn.deb"
        rm -f "$TMP"
        # The note expects the official URL; user may update if needed.
        # Common approach: download the .deb from ProtonVPN. We'll attempt a generic URL placeholder:
        PROTON_URL="https://repo.protonvpn.com/debian/dists/stable/main/binary-amd64/packagename" # placeholder - update as needed
        echo "Note: ProtonVPN download URL is a placeholder. Replace PROTON_URL in the script if you want automatic download."
        # If the user has a .deb in repo, use it
        if [ -f "$REPO_DIR/protonvpn.deb" ]; then
          $SUDO dpkg -i "$REPO_DIR/protonvpn.deb" || true
        else
          echo "Skipping automatic ProtonVPN download (no confirmed URL). Use apt or provide /tmp/protonvpn.deb manually."
        fi
        $SUDO apt install -f -y || true
        $SUDO apt install -y proton-vpn-gnome-desktop 2>/dev/null || true
        ;;
      5)
        echo "--> Installing VirtualBox"
        $SUDO apt update
        $SUDO apt install -y virtualbox || true
        ;;
      6)
        echo "--> Installing RustScan (example .deb flow)"
        TMP="/tmp/rustscan_2.2.3_amd64.deb"
        rm -f "$TMP"
        if [ -f "$REPO_DIR/rustscan_2.2.3_amd64.deb" ]; then
          $SUDO dpkg -i "$REPO_DIR/rustscan_2.2.3_amd64.deb" || true
          $SUDO apt install -f -y || true
        else
          echo "RustScan .deb not found in repo; skipping. Place the .deb at $REPO_DIR/rustscan_2.2.3_amd64.deb to auto-install."
        fi
        ;;
      7)
        echo "--> Installing Spotify (apt + fallback snap)"
        # Try apt via adding key and repo if available - keep simple: attempt apt install, fallback to snap
        $SUDO apt update
        $SUDO apt install -y spotify-client 2>/dev/null || (echo "apt install spotify failed, trying snap" && snap install spotify 2>/dev/null || true)
        ;;
      *)
        echo "Unknown choice: $item"
        ;;
    esac
  done
fi

echo "=== Script finished ==="
echo "Notes:"
echo "- If you ran this as root via sudo, user-level systemctl --user commands may need to be executed as the target user."
echo "- Edit REPO_URL at top if cloning is required."
echo "- ProtonVPN/RustScan .deb URLs are placeholders; provide the .deb files in the repo or update the script."
