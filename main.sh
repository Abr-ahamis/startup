#!/usr/bin/env bash
set -e

# ================= CONFIG =================
REPO_URL="https://github.com/Abr-ahamis/startup.git"
REPO_DIR="startup"

APT_PACKAGES=(
  i3-wm i3blocks rofi xdotool dex acpi upower
  xfce4-power-manager i3lock xss-lock pulseaudio-utils
  brightnessctl feh picom fonts-font-awesome
  git rsync unzip curl wget
)

TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

# =============== FUNCTIONS ===============

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "Run as root: sudo ./startup_setup_full.sh"
    exit 1
  fi
}

clone_or_detect_repo() {
  if [[ -d "i3" && -d "wallpaper" ]]; then
    echo "[INFO] Using current directory as repo"
    REPO_PATH="$PWD"
  elif [[ -d "$REPO_DIR" ]]; then
    REPO_PATH="$REPO_DIR"
  else
    echo "[INFO] Cloning repo..."
    git clone "$REPO_URL" "$REPO_DIR"
    REPO_PATH="$REPO_DIR"
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y "${APT_PACKAGES[@]}"
}

build_dest_paths() {
  DEST_PATHS=(
    "$USER_HOME/.config/i3/config"
    "$USER_HOME/.config/i3/scripts"
    "$USER_HOME/.config/i3blocks"
    "$USER_HOME/.config/rofi"
    "$USER_HOME/.config/picom/picom.conf"
    "$USER_HOME/.local/bin"
    "$USER_HOME/.local/share/fonts"
    "$USER_HOME/.config/systemd/user/battery-monitor.service"
    "$USER_HOME/Pictures/wallpaper.jpg"
    "$USER_HOME/Pictures/wallpaper-1.jpg"
    "$USER_HOME/Pictures/wallpaper-2.jpg"
    "/usr/share/backgrounds/kali"
    "/usr/share/rofi/themes"
  )
}

scan_existing() {
  FOUND_EXISTING=()
  for p in "${DEST_PATHS[@]}"; do
    [[ -e "$p" ]] && FOUND_EXISTING+=("$p")
  done
}

delete_existing() {
  for p in "${FOUND_EXISTING[@]}"; do
    [[ "$p" == "/" || -z "$p" ]] && continue
    echo "[DEL] $p"
    rm -rf "$p"
  done
}

copy_configs() {
  echo "[COPY] Applying configuration files..."

  cp -f "$REPO_PATH/i3/.config/i3/config" "$USER_HOME/.config/i3/config"

  cp -r "$REPO_PATH/i3/.config/i3/scripts" "$USER_HOME/.config/i3/"
  cp -r "$REPO_PATH/i3/.config/i3blocks" "$USER_HOME/.config/"
  cp -r "$REPO_PATH/i3/.config/rofi" "$USER_HOME/.config/"
  cp -f "$REPO_PATH/i3/.config/picom/picom.conf" "$USER_HOME/.config/picom/"

  cp -r "$REPO_PATH/i3/.local/bin" "$USER_HOME/.local/"
  chmod +x "$USER_HOME/.local/bin/"*

  cp -r "$REPO_PATH/i3/.local/share/fonts" "$USER_HOME/.local/share/"

  mkdir -p "$USER_HOME/.config/systemd/user"
  cp -f "$REPO_PATH/i3/.config/systemd/user/battery-monitor.service" \
        "$USER_HOME/.config/systemd/user/"

  # Wallpapers
  mkdir -p "$USER_HOME/Pictures"
  cp -f "$REPO_PATH/wallpaper/"wallpaper*.jpg "$USER_HOME/Pictures/"

  mkdir -p /usr/share/backgrounds/kali
  cp -f "$REPO_PATH/wallpaper/wallpaper-1.jpg" /usr/share/backgrounds/kali/login.svg
  cp -f "$REPO_PATH/wallpaper/wallpaper.jpg" /usr/share/backgrounds/kali/kali-maze-16x9.jpg
  cp -f "$REPO_PATH/wallpaper/wallpaper-2.jpg" /usr/share/backgrounds/kali/kali-tiles-16x9.jpg
  cp -f "$REPO_PATH/wallpaper/wallpaper-1.jpg" /usr/share/backgrounds/kali/login-blurred

  # Rofi theme
  rm -rf /usr/share/rofi/themes/*
  mkdir -p /usr/share/rofi/themes
  cp -f "$REPO_PATH/i3/usr/share/rofi/themes/Adapta-Nokto.rasi" \
        /usr/share/rofi/themes/

  chown -R "$TARGET_USER":"$TARGET_USER" "$USER_HOME"
}

ensure_path() {
  grep -q '.local/bin' "$USER_HOME/.bashrc" 2>/dev/null || \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.bashrc"
}

run_systemctl_user() {
  UID_NUM="$(id -u "$TARGET_USER")"

  echo "[SYSTEMD] Activating battery monitor"

  sudo -u "$TARGET_USER" systemctl --user daemon-reexec || true
  sudo -u "$TARGET_USER" systemctl --user daemon-reload || true
  sudo -u "$TARGET_USER" systemctl --user restart battery-monitor.service || \
    XDG_RUNTIME_DIR="/run/user/$UID_NUM" \
    sudo -u "$TARGET_USER" systemctl --user restart battery-monitor.service || true
}

app_menu() {
  echo ""
  echo "Applications:"
  echo "1) Spotify"
  echo "Enter = skip"
  read -p "Selection: " choice

  case "$choice" in
    1)
      apt install -y spotify-client || snap install spotify
      ;;
  esac
}

# ================= MAIN =================
require_root
clone_or_detect_repo
install_packages

build_dest_paths
scan_existing

if [[ "${#FOUND_EXISTING[@]}" -gt 0 ]]; then
  echo ""
  echo "Existing configuration detected:"
  for p in "${FOUND_EXISTING[@]}"; do echo " - $p"; done
  read -p "Replace all existing configuration files with the repository versions? [y/N]: " ans
  if [[ "$ans" == "y" ]]; then
    delete_existing
    copy_configs
  else
    echo "Skipping configuration replacement."
  fi
else
  copy_configs
fi

ensure_path
run_systemctl_user
app_menu

echo "DONE."
