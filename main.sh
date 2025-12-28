#!/usr/bin/env bash
# setup-i3-kali.sh - Hardened & error-tolerant i3 setup for Kali (from abr-ahamis/startup)
# - Single combined prompt: config overwrite (1) or skip (2); plus apps selection
# - Robust checks for prerequisites, non-fatal failures, clear logging
# - Attempts to run destructive steps only when user chooses them
# - Designed to be run as normal user; uses sudo where needed
# NOTE: This script deletes existing configs when you choose option 1 (no backups).

set -o pipefail

### ---- CONFIG ----
REPO_URL="https://github.com/abr-ahamis/startup.git"
REPO_DIR_NAME="startup"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOGS=()
DRY_RUN=false   # set true for debugging to avoid destructive actions

# Packages to try installing (best-effort)
APT_PACKAGES=(i3-wm i3blocks rofi picom feh brightnessctl pulseaudio-utils \
xss-lock i3lock dex fonts-font-awesome git curl wget unzip rsync \
timeshift grub-customizer)

### ---- Helpers ----
log(){ LOGS+=("[INFO] $1"); echo -e "[INFO] $1"; }
warn(){ LOGS+=("[WARN] $1"); echo -e "[WARN] $1" >&2; }
err(){ LOGS+=("[ERROR] $1"); echo -e "[ERROR] $1" >&2; }

# run a command; don't exit script except for fatal situations.
run() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
    return 0
  fi
  eval "$@" 2>&1 || { warn "Command failed: $*"; return 1; }
}

# Check if a command exists
command_exists() { command -v "$1" >/dev/null 2>&1; }

# safe mkdir -p with ownership for user
safe_mkdir_for_user() {
  local path="$1" user="$2"
  if [ ! -d "$path" ]; then
    run sudo mkdir -p -- "$path" || return 1
  fi
  run sudo chown -R "$user":"$user" "$path" || true
}

# attempt to get absolute path
abs_path() { (cd "$1" 2>/dev/null && pwd -P) || echo "$1"; }

### ---- Determine users/home ----
# Choose REAL_USER:
if [ -n "${SUDO_USER:-}" ]; then
  REAL_USER="$SUDO_USER"
else
  REAL_USER="$(id -un)"
fi

# If running as root without SUDO_USER, try find a non-root user (UID >=1000)
if [ "$(id -u)" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
  # find first human user
  candidate="$(awk -F: '$3>=1000 && $1!="nobody"{print $1; exit}' /etc/passwd)"
  if [ -n "$candidate" ]; then
    REAL_USER="$candidate"
    warn "Running as root with no SUDO_USER; using detected non-root user: $REAL_USER"
  else
    warn "Running as root and no non-root user detected; continuing as root (REAL_USER=root)."
    REAL_USER="root"
  fi
fi

USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
[ -z "$USER_HOME" ] && USER_HOME="$HOME"

CUR_DIR="$(pwd -P)"
REPO_PATH=""

### ---- Graceful shutdown / summary ----
cleanup_and_summary() {
  echo
  echo "===== SUMMARY ====="
  for l in "${LOGS[@]}"; do echo "$l"; done
  echo "==================="
}
trap cleanup_and_summary EXIT

### ---- Prereqs ----
check_prereqs() {
  log "Checking required tools..."
  local needed=(git rsync wget)
  for c in "${needed[@]}"; do
    if ! command_exists "$c"; then
      warn "'$c' not found."
    fi
  done
  if ! command_exists sudo; then
    warn "sudo not found; system-level operations may fail."
  fi
}

### ---- Repo locate/clone ----
locate_or_clone_repo() {
  # If current dir is startup, use it
  if [ "$(basename "$CUR_DIR")" = "$REPO_DIR_NAME" ]; then
    REPO_PATH="$CUR_DIR"
    log "Using current directory as repo: $REPO_PATH"
    return 0
  fi
  # If ./startup exists -> use it
  if [ -d "$CUR_DIR/$REPO_DIR_NAME" ]; then
    REPO_PATH="$(abs_path "$CUR_DIR/$REPO_DIR_NAME")"
    log "Found repo in cwd: $REPO_PATH"
    return 0
  fi
  # Try to clone shallow into cwd/startup
  log "Cloning repository into: $CUR_DIR/$REPO_DIR_NAME"
  if $DRY_RUN; then
    REPO_PATH="$CUR_DIR/$REPO_DIR_NAME"
    return 0
  fi
  if ! command_exists git; then
    err "git not available; cannot clone repo. Install git or place repo locally."
    return 1
  fi
  if git clone --depth 1 "$REPO_URL" "$CUR_DIR/$REPO_DIR_NAME"; then
    REPO_PATH="$(abs_path "$CUR_DIR/$REPO_DIR_NAME")"
    log "Cloned repo successfully to: $REPO_PATH"
    return 0
  else
    err "Git clone failed. Check network and $REPO_URL."
    return 1
  fi
}

validate_repo_structure() {
  local req=(i3 rofi picom wallpaper grub)
  local miss=()
  for d in "${req[@]}"; do
    if [ ! -d "$REPO_PATH/$d" ]; then miss+=("$d"); fi
  done
  if [ ${#miss[@]} -gt 0 ]; then
    err "Repo missing required folders: ${miss[*]}"
    return 1
  fi
  log "Repository structure validated."
  return 0
}

### ---- Install apt packages (best-effort) ----
install_packages() {
  if $DRY_RUN; then
    log "DRY-RUN: skip apt installs"
    return 0
  fi
  if ! command_exists sudo; then
    warn "No sudo: cannot run apt install - skipping package installation."
    return 0
  fi
  log "Updating apt and attempting to install packages..."
  run sudo apt update -y || warn "apt update failed"
  # install in chunks to avoid long arg issues
  run sudo apt install -y "${APT_PACKAGES[@]}" || warn "Some apt package installs failed; continuing."
}

### ---- Config management: delete & copy safely ----
safe_delete() {
  local p="$1"
  if [ -e "$p" ]; then
    log "Removing: $p"
    run sudo rm -rf -- "$p" || warn "Failed to remove $p"
  fi
}

safe_copy_rsync() {
  local src="$1" dst="$2" owner="$3"
  if [ ! -e "$src" ]; then
    warn "Source missing: $src"
    return 1
  fi
  run sudo mkdir -p -- "$dst" || warn "mkdir failed for $dst"
  run sudo rsync -a -- "$src" "$dst" || warn "rsync failed: $src -> $dst"
  run sudo chown -R "$owner":"$owner" "$dst" || true
}

manage_configs() {
  local action="$1"  # remove | skip
  if [ "$action" = "skip" ]; then
    log "Skipping config replacement by user choice."
    return 0
  fi
  log "Replacing configs (deleting old then copying repo versions)."

  # i3
  safe_delete "$USER_HOME/.config/i3"
  safe_copy_rsync "$REPO_PATH/i3/.config/i3/" "$USER_HOME/.config/i3" "$REAL_USER"

  # i3 scripts (ensure permissions)
  safe_delete "$USER_HOME/.config/i3/scripts"
  safe_copy_rsync "$REPO_PATH/i3/.config/i3/scripts/" "$USER_HOME/.config/i3/scripts" "$REAL_USER"
  run sudo chmod -R 755 "$USER_HOME/.config/i3/scripts/" || true

  # i3blocks
  safe_delete "$USER_HOME/.config/i3blocks"
  safe_copy_rsync "$REPO_PATH/i3/.config/i3blocks/" "$USER_HOME/.config/i3blocks" "$REAL_USER"

  # rofi
  safe_delete "$USER_HOME/.config/rofi"
  safe_copy_rsync "$REPO_PATH/i3/.config/rofi/" "$USER_HOME/.config/rofi" "$REAL_USER"
  # system rofi theme
  if [ -f "$REPO_PATH/i3/usr/share/rofi/themes/Adapta-Nokto.rasi" ]; then
    run sudo mkdir -p /usr/share/rofi/themes || true
    run sudo rm -f /usr/share/rofi/themes/* || true
    run sudo cp -a -- "$REPO_PATH/i3/usr/share/rofi/themes/Adapta-Nokto.rasi" /usr/share/rofi/themes/Adapta-Nokto.rasi || warn "Rofi theme copy failed"
  else
    warn "Rofi theme file not found in repo location; skipped."
  fi

  # picom
  safe_delete "$USER_HOME/.config/picom"
  safe_copy_rsync "$REPO_PATH/i3/.config/picom/" "$USER_HOME/.config/picom" "$REAL_USER"

  # local bin
  safe_delete "$USER_HOME/.local/bin"
  safe_copy_rsync "$REPO_PATH/i3/.local/bin/" "$USER_HOME/.local/bin" "$REAL_USER"
  run sudo chmod -R 755 "$USER_HOME/.local/bin/" || true

  # fonts
  safe_delete "$USER_HOME/.local/share/fonts"
  safe_copy_rsync "$REPO_PATH/i3/.local/share/fonts/" "$USER_HOME/.local/share/fonts" "$REAL_USER"
  run sudo -u "$REAL_USER" fc-cache -fv || true

  # battery service
  safe_delete "$USER_HOME/.config/systemd/user/battery-monitor.service"
  safe_delete "$USER_HOME/.config/systemd/user/battery-monitor.sh"
  run sudo mkdir -p "$USER_HOME/.config/systemd/user" || true
  run sudo cp -a -- "$REPO_PATH/i3/.config/systemd/user/battery-monitor.service" "$USER_HOME/.config/systemd/user/" 2>/dev/null || warn "No battery-monitor.service found"
  run sudo cp -a -- "$REPO_PATH/i3/.config/systemd/user/battery-monitor.sh" "$USER_HOME/.config/systemd/user/" 2>/dev/null || warn "No battery-monitor.sh found"
  run sudo chown -R "$REAL_USER":"$REAL_USER" "$USER_HOME/.config/systemd/user" || true
  run sudo chmod 755 "$USER_HOME/.config/systemd/user/battery-monitor.sh" || true
}

### ---- Manage wallpaper (user + system) ----
manage_wallpapers() {
  local src="$REPO_PATH/wallpaper"
  local userpics="$USER_HOME/Pictures"
  local sysdir="/usr/share/backgrounds/kali"
  local files=(wallpaper.jpg wallpaper-1.jpg wallpaper-2.jpg)

  # copy to user pictures
  run sudo mkdir -p "$userpics" || true
  for f in "${files[@]}"; do
    if [ -f "$src/$f" ]; then
      run sudo cp -a -- "$src/$f" "$userpics/" || warn "Failed copy $f to $userpics"
      run sudo chown "$REAL_USER":"$REAL_USER" "$userpics/$f" || true
    else
      warn "Source wallpaper missing: $src/$f"
    fi
  done

  # system replacements (rename existing by appending timestamp)
  run sudo mkdir -p "$sysdir" || warn "Cannot create $sysdir"
  declare -A mapping=( \
    ["login.svg"]="wallpaper.jpg" \
    ["kali-maze-16x9.jpg"]="wallpaper.jpg" \
    ["kali-tiles-16x9.jpg"]="wallpaper-2.jpg" \
    ["kali-waves-16x9.png"]="wallpaper-1.jpg" \
    ["kali-oleo-16x9.png"]="wallpaper.jpg" \
    ["kali-tiles-purple-16x9.jpg"]="wallpaper-2.jpg" \
    ["login-blurred"]="wallpaper-2.jpg" \
  )

  for target in "${!mapping[@]}"; do
    srcfile="${mapping[$target]}"
    if [ -e "$sysdir/$target" ]; then
      bak="${target}.${TIMESTAMP}.bak"
      log "Renaming $sysdir/$target -> $sysdir/$bak"
      run sudo mv -- "$sysdir/$target" "$sysdir/$bak" || warn "Could not rename $sysdir/$target"
    fi
    if [ -f "$src/$srcfile" ]; then
      log "Copying $srcfile to $sysdir/$target"
      run sudo cp -a -- "$src/$srcfile" "$sysdir/$target" || warn "Failed to copy wallpaper"
    else
      warn "Repo wallpaper missing for mapping: $srcfile"
    fi
  done
}

### ---- GRUB theme management ----
manage_grub_theme() {
  local src="$REPO_PATH/grub"
  local t1="/boot/grub/themes/kali"
  local t2="/usr/share/grub/themes"

  run sudo mkdir -p "$t1" "$t2" || true
  # remove existing files safely
  run sudo find "$t1" -mindepth 1 -maxdepth 1 -print0 -exec rm -rf -- {} \; 2>/dev/null || true
  run sudo find "$t2" -mindepth 1 -maxdepth 1 -print0 -exec rm -rf -- {} \; 2>/dev/null || true
  if [ -d "$src" ]; then
    run sudo cp -a -- "$src/"* "$t1/" 2>/dev/null || warn "Failed copying grub files to $t1"
    run sudo cp -a -- "$src/"* "$t2/" 2>/dev/null || warn "Failed copying grub files to $t2"
  else
    warn "No grub assets in repo: $src"
  fi
}

### ---- Battery-monitor user systemd reload ----
manage_battery_service() {
  # systemctl --user requires an active user systemd; attempt but never fatal
  log "Attempting to reload user systemd units for $REAL_USER (best-effort)."
  if $DRY_RUN; then
    echo "[DRY] systemctl --user daemon-reexec"
    return 0
  fi
  if ! command_exists systemctl; then
    warn "systemctl not found; skipping user service reload."
    return 0
  fi
  # Try as the real user
  sudo -u "$REAL_USER" systemctl --user daemon-reexec 2>/dev/null || warn "daemon-reexec may have failed (no user systemd)"
  sudo -u "$REAL_USER" systemctl --user daemon-reload 2>/dev/null || warn "daemon-reload failed"
  sudo -u "$REAL_USER" systemctl --user restart battery-monitor.service 2>/dev/null || warn "Restart battery-monitor.service failed (unit may be absent)."
}

### ---- Finalization: chmod + restart i3 if running ----
finalize() {
  run sudo chmod -R 755 "$USER_HOME/.config/i3/scripts/" || true
  run sudo chmod -R 755 "$USER_HOME/.local/bin/" || true
  run sudo chown -R "$REAL_USER":"$REAL_USER" "$USER_HOME/.config/i3" || true
  run sudo chown -R "$REAL_USER":"$REAL_USER" "$USER_HOME/.local" || true

  # Restart i3 only if running
  if pgrep -u "$REAL_USER" -x i3 >/dev/null 2>&1 || pgrep -u "$REAL_USER" -f "i3" >/dev/null 2>&1; then
    log "i3 detected for $REAL_USER; attempting restart (i3-msg restart)."
    if $DRY_RUN; then
      echo "[DRY] sudo -u \"$REAL_USER\" i3-msg restart"
    else
      sudo -u "$REAL_USER" DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-$USER_HOME/.Xauthority}" i3-msg restart 2>/dev/null || warn "i3-msg restart likely failed (DISPLAY/XAUTH)."
    fi
  else
    log "i3 not running for $REAL_USER; skipping restart to avoid breaking other DEs."
  fi
}

### ---- App installers (best-effort) ----
install_telegram() {
  local src="$REPO_PATH/i3/.local/bin/Telegram"
  local dst="/usr/local/bin/telegram"
  if [ -f "$src" ]; then
    run sudo rm -f "$dst" || true
    run sudo cp -a -- "$src" "$dst" || warn "Failed to install telegram binary"
    run sudo chmod 755 "$dst" || true
  else
    warn "Telegram binary missing in repo: $src"
  fi
}
install_brave() {
  log "Installing Brave Nightly (best-effort)..."
  run bash -c "curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly sudo -E bash -" || warn "Brave installer failed"
  run sudo apt install -y brave-browser-nightly || warn "apt install brave failed"
}
install_vscode() {
  local tmp="/tmp/code_latest_$$.deb"
  run rm -f "$tmp" || true
  run wget -q -O "$tmp" "https://update.code.visualstudio.com/latest/linux-deb-x64/stable" || { warn "VSCode download failed"; return 1; }
  run sudo dpkg -i "$tmp" || true
  run sudo apt install -f -y || true
  run rm -f "$tmp" || true
}
install_rustscan() {
  local tmp="/tmp/rustscan_$$.deb"
  run rm -f "$tmp" || true
  run wget -q -O "$tmp" "https://github.com/RustScan/RustScan/releases/latest/download/rustscan_amd64.deb" || warn "RustScan download failed"
  run sudo dpkg -i "$tmp" || true
  run sudo apt install -f -y || true
  run rm -f "$tmp" || true
}
install_spotify(){
  run sudo apt-get install -y curl gnupg apt-transport-https || true
  run curl -sS https://download.spotify.com/debian/pubkey_0D811D58.gpg | sudo gpg --dearmour -o /usr/share/keyrings/spotify-archive-keyring.gpg || warn "Spotify key add failed"
  run echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list >/dev/null
  run sudo apt update -y || true
  run sudo apt install -y spotify-client || warn "Spotify install failed"
}

install_selected_apps() {
  local sel=("$@")
  for x in "${sel[@]}"; do
    case "$x" in
      1) install_telegram ;;
      2) install_brave ;;
      3) install_vscode ;;
      4) install_rustscan ;;
      5) install_spotify ;;
      *) warn "Unknown app choice: $x" ;;
    esac
  done
}

### ---- Single combined prompt ----
get_user_choices() {
  cat <<'PROMPT'
ONE-TIME INPUT:
Choose config action and apps on one line separated by a semicolon ';'
Examples:
  1; a      -> Remove configs AND install all apps
  2; n      -> Skip configs AND install none

Config:
  1) Remove configs (delete, no backups)
  2) Skip configs

Apps:
  1) Telegram
  2) Brave Nightly
  3) Visual Studio Code
  4) RustScan
  5) Spotify

Format: <1|2>;<a|n|list>   e.g. 1; 1 3 5
Enter: 
PROMPT
  read -r USER_INPUT
  # default if empty
  USER_INPUT="${USER_INPUT:-2;n}"
  CONFIG_CHOICE="$(echo "$USER_INPUT" | awk -F';' '{print $1}' | tr -d '[:space:]')"
  APP_PART="$(echo "$USER_INPUT" | awk -F';' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "$CONFIG_CHOICE" ] && CONFIG_CHOICE=2
  [ -z "$APP_PART" ] && APP_PART="n"

  if [[ "$APP_PART" =~ ^[aA]$ ]]; then APP_SELECTION=(1 2 3 4 5)
  elif [[ "$APP_PART" =~ ^[nN]$ ]]; then APP_SELECTION=()
  else
    read -r -a APP_SELECTION <<< "$APP_PART"
  fi

  if [ "$CONFIG_CHOICE" != "1" ] && [ "$CONFIG_CHOICE" != "2" ]; then
    warn "Invalid config choice; defaulting to skip (2)."
    CONFIG_CHOICE=2
  fi
}

### ---- MAIN ----
main() {
  check_prereqs
  if ! locate_or_clone_repo; then err "Repo missing/clone failed; aborting."; exit 1; fi
  if ! validate_repo_structure; then err "Repo invalid; aborting."; exit 1; fi

  get_user_choices

  if [ "$CONFIG_CHOICE" = "1" ]; then
    manage_configs remove
  else
    manage_configs skip
  fi

  install_packages
  manage_wallpapers
  manage_grub_theme
  manage_battery_service
  finalize

  if [ ${#APP_SELECTION[@]} -gt 0 ]; then
    install_selected_apps "${APP_SELECTION[@]}"
  else
    log "No apps selected for installation."
  fi

  log "Setup finished (non-fatal errors may have been warned)."
}

main "$@"
