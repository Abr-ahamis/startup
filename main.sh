#!/usr/bin/env bash
# setup-i3-kali.sh
# Polished automated i3 setup for Kali Linux from repo `abr-ahamis/startup`
# - One combined user interaction (config overwrite + app selection)
# - Uses functions, logging, safety checks, minimal hard failures
# - Deletes existing configs (per user preference), copies repo files, installs optional apps
# Run as your normal user. sudo will be used where required.

set -o pipefail

## ---- Configuration / Variables ----
REPO_URL="https://github.com/abr-ahamis/startup.git"
REPO_DIR_NAME="startup"               # expected repo dir name
CUR_DIR="$(pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOGS=()
APT_PACKAGES=(i3-wm i3blocks rofi picom feh brightnessctl pulseaudio-utils \
xss-lock i3lock dex fonts-font-awesome git curl wget unzip rsync \
timeshift grub-customizer)

# Determine real user & home (works when called with sudo)
if [ -n "${SUDO_USER:-}" ]; then
  REAL_USER="$SUDO_USER"
else
  REAL_USER="$(id -un)"
fi
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
if [ -z "$USER_HOME" ]; then
  USER_HOME="$HOME"
fi

REPO_PATH=""  # will be set after repo detection/clone
DRY_RUN=false   # set true for testing (no destructive actions)

# Utility logging
log() { LOGS+=("$1"); echo -e "[INFO] $1"; }
warn() { LOGS+=("WARN: $1"); echo -e "[WARN] $1" >&2; }
err() { LOGS+=("ERROR: $1"); echo -e "[ERROR] $1" >&2; }

# Safe run wrapper: run command, don't exit script on failure (unless critical)
run() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
    return 0
  fi
  eval "$@" || { warn "Command failed: $*"; return 1; }
}

## ---- Safety checks ----
check_requirements() {
  log "Running basic environment checks..."
  # ensure sudo available when we need system write
  if ! command -v sudo >/dev/null 2>&1; then
    warn "sudo not found. Script will attempt system actions without sudo."
  fi
}

## ---- Repo detection / clone ----
locate_or_clone_repo() {
  # If current directory basename is "startup", use it.
  if [ "$(basename "$CUR_DIR")" = "$REPO_DIR_NAME" ]; then
    REPO_PATH="$CUR_DIR"
    log "Script running inside '$REPO_DIR_NAME' directory: $REPO_PATH"
    return 0
  fi

  # If ./startup exists in cwd, use it
  if [ -d "$CUR_DIR/$REPO_DIR_NAME" ]; then
    REPO_PATH="$CUR_DIR/$REPO_DIR_NAME"
    log "Found '$REPO_DIR_NAME' in current directory: $REPO_PATH"
    return 0
  fi

  # Otherwise try to clone into ./startup
  log "Repository not found locally. Attempting to clone into ./startup ..."
  if $DRY_RUN; then
    REPO_PATH="$CUR_DIR/$REPO_DIR_NAME"
    return 0
  fi
  if git clone "$REPO_URL" "$CUR_DIR/$REPO_DIR_NAME"; then
    REPO_PATH="$CUR_DIR/$REPO_DIR_NAME"
    log "Cloned repo to: $REPO_PATH"
    return 0
  else
    err "Failed to clone repository from $REPO_URL. Aborting."
    return 1
  fi
}

## ---- Validate required repo structure ----
validate_repo_structure() {
  local required=(i3 rofi picom wallpaper grub)
  local missing=()
  for d in "${required[@]}"; do
    if [ ! -d "$REPO_PATH/$d" ]; then
      missing+=("$d")
    fi
  done
  if [ ${#missing[@]} -ne 0 ]; then
    err "Repository structure missing required folders: ${missing[*]}"
    return 1
  fi
  log "Repository structure OK."
  return 0
}

## ---- APT dependencies ----
install_packages() {
  log "Updating apt and installing packages: ${APT_PACKAGES[*]}"
  run sudo apt update -y
  run sudo apt install -y "${APT_PACKAGES[@]}" || warn "Some apt installs failed; continuing."
}

## ---- Helpers for file operations (operate on REAL_USER home) ----
ensure_dir_user() {
  local dirpath="$1"
  if [ ! -d "$dirpath" ]; then
    log "Creating directory: $dirpath"
    run sudo mkdir -p "$dirpath" || return 1
    run sudo chown -R "$REAL_USER":"$REAL_USER" "$dirpath" || true
  fi
}

delete_path_user() {
  local path="$1"
  if [ -e "$path" ]; then
    log "Deleting existing path: $path"
    run sudo rm -rf "$path" || warn "Failed to delete $path"
  fi
}

copy_with_owner() {
  local src="$1" dst="$2"
  run sudo mkdir -p "$(dirname "$dst")"
  log "Copying: $src -> $dst"
  run sudo cp -a "$src" "$dst" || warn "Failed to copy $src -> $dst"
  run sudo chown -R "$REAL_USER":"$REAL_USER" "$dst" || true
}

rsync_with_owner() {
  local src="$1" dst="$2"
  log "Rsync: $src -> $dst"
  run sudo mkdir -p "$dst"
  run sudo rsync -a "$src" "$dst" || warn "rsync failed: $src -> $dst"
  run sudo chown -R "$REAL_USER":"$REAL_USER" "$dst" || true
}

## ---- Config management (delete existing, copy repo files) ----
manage_configs() {
  local action="$1"  # "remove" or "skip"
  if [ "$action" = "skip" ]; then
    log "User chose to skip config replacement. Skipping config copy steps."
    return 0
  fi

  log "Replacing configuration files (deleting old then copying repo versions)..."

  # i3 config
  delete_path_user "$USER_HOME/.config/i3"
  ensure_dir_user "$USER_HOME/.config/i3"
  rsync_with_owner "$REPO_PATH/i3/.config/i3/" "$USER_HOME/.config/i3/"

  # i3 scripts
  delete_path_user "$USER_HOME/.config/i3/scripts"
  ensure_dir_user "$USER_HOME/.config/i3/scripts"
  rsync_with_owner "$REPO_PATH/i3/.config/i3/scripts/" "$USER_HOME/.config/i3/scripts/"
  run sudo chmod -R 755 "$USER_HOME/.config/i3/scripts/" || true

  # i3blocks
  delete_path_user "$USER_HOME/.config/i3blocks"
  ensure_dir_user "$USER_HOME/.config/i3blocks"
  rsync_with_owner "$REPO_PATH/i3/.config/i3blocks/" "$USER_HOME/.config/i3blocks/"

  # rofi
  delete_path_user "$USER_HOME/.config/rofi"
  ensure_dir_user "$USER_HOME/.config/rofi"
  rsync_with_owner "$REPO_PATH/i3/.config/rofi/" "$USER_HOME/.config/rofi/"

  # system-wide rofi theme
  if [ -f "$REPO_PATH/i3/usr/share/rofi/themes/Adapta-Nokto.rasi" ]; then
    run sudo rm -f /usr/share/rofi/themes/* || true
    copy_with_owner "$REPO_PATH/i3/usr/share/rofi/themes/Adapta-Nokto.rasi" "/usr/share/rofi/themes/Adapta-Nokto.rasi"
  else
    warn "Rofi theme missing in repo; skipped."
  fi

  # picom
  delete_path_user "$USER_HOME/.config/picom"
  ensure_dir_user "$USER_HOME/.config/picom"
  rsync_with_owner "$REPO_PATH/i3/.config/picom/" "$USER_HOME/.config/picom/"
  # Ensure specific picom.conf if present
  if [ -f "$REPO_PATH/i3/.config/picom/picom.conf" ]; then
    copy_with_owner "$REPO_PATH/i3/.config/picom/picom.conf" "$USER_HOME/.config/picom/picom.conf"
  fi

  # local bin
  delete_path_user "$USER_HOME/.local/bin"
  ensure_dir_user "$USER_HOME/.local/bin"
  rsync_with_owner "$REPO_PATH/i3/.local/bin/" "$USER_HOME/.local/bin/"
  run sudo chmod -R 755 "$USER_HOME/.local/bin/" || true

  # fonts
  delete_path_user "$USER_HOME/.local/share/fonts"
  ensure_dir_user "$USER_HOME/.local/share/fonts"
  rsync_with_owner "$REPO_PATH/i3/.local/share/fonts/" "$USER_HOME/.local/share/fonts/"
  # refresh font cache
  run sudo -u "$REAL_USER" fc-cache -fv || true

  # battery service + script (user systemd)
  ensure_dir_user "$USER_HOME/.config/systemd/user"
  delete_path_user "$USER_HOME/.config/systemd/user/battery-monitor.service"
  delete_path_user "$USER_HOME/.config/systemd/user/battery-monitor.sh"
  copy_with_owner "$REPO_PATH/i3/.config/systemd/user/battery-monitor.service" "$USER_HOME/.config/systemd/user/battery-monitor.service"
  copy_with_owner "$REPO_PATH/i3/.config/systemd/user/battery-monitor.sh" "$USER_HOME/.config/systemd/user/battery-monitor.sh"
  run sudo chmod 755 "$USER_HOME/.config/systemd/user/battery-monitor.sh" || true

  log "Config files copied and permissions set."
}

## ---- Battery-monitor service reload (user systemd) ----
manage_battery_service() {
  log "Reloading user systemd and restarting battery-monitor.service (if available)..."
  # Run daemon commands as the real user (do not use <UID> token)
  if $DRY_RUN; then
    echo "[DRY] systemctl --user daemon-reexec"
    echo "[DRY] systemctl --user daemon-reload"
    echo "[DRY] systemctl --user restart battery-monitor.service"
    return 0
  fi

  # Use runuser or sudo -u to run systemctl --user as the real user
  sudo -u "$REAL_USER" systemctl --user daemon-reexec 2>/dev/null || warn "daemon-reexec failed (may be no user systemd)"
  sudo -u "$REAL_USER" systemctl --user daemon-reload 2>/dev/null || warn "daemon-reload failed"
  sudo -u "$REAL_USER" systemctl --user restart battery-monitor.service 2>/dev/null || warn "battery-monitor.service restart failed or unit not found"
}

## ---- Wallpapers management ----
manage_wallpapers() {
  local src_dir="$REPO_PATH/wallpaper"
  local user_pics="$USER_HOME/Pictures"
  local sys_dir="/usr/share/backgrounds/kali"
  local files=(wallpaper.jpg wallpaper-1.jpg wallpaper-2.jpg)

  log "Copying wallpapers to user Pictures..."
  run sudo mkdir -p "$user_pics"
  for f in "${files[@]}"; do
    if [ -f "$src_dir/$f" ]; then
      run sudo cp -a "$src_dir/$f" "$user_pics/" || warn "Failed to copy $f to $user_pics"
      run sudo chown "$REAL_USER":"$REAL_USER" "$user_pics/$f" || true
    else
      warn "Wallpaper not found in repo: $f"
    fi
  done

  # Ensure system folder exists
  run sudo mkdir -p "$sys_dir"

  # For each target system file, rename existing with timestamp, then copy replacements (rotation)
  declare -A mapping=(
    ["login.svg"]="wallpaper.jpg"
    ["kali-maze-16x9.jpg"]="wallpaper.jpg"
    ["kali-tiles-16x9.jpg"]="wallpaper-2.jpg"
    ["kali-waves-16x9.png"]="wallpaper-1.jpg"
    ["kali-oleo-16x9.png"]="wallpaper.jpg"
    ["kali-tiles-purple-16x9.jpg"]="wallpaper-2.jpg"
    ["login-blurred"]="wallpaper-2.jpg"
  )

  for target in "${!mapping[@]}"; do
    srcfile="${mapping[$target]}"
    if [ -f "$sys_dir/$target" ]; then
      local bakname="${target}.${TIMESTAMP}.bak"
      log "Renaming existing system wallpaper: $sys_dir/$target -> $sys_dir/$bakname"
      run sudo mv "$sys_dir/$target" "$sys_dir/$bakname" || warn "Could not rename $sys_dir/$target"
    fi
    if [ -f "$src_dir/$srcfile" ]; then
      log "Copying $srcfile -> $sys_dir/$target"
      run sudo cp -a "$src_dir/$srcfile" "$sys_dir/$target" || warn "Failed to copy wallpaper $srcfile -> $target"
    else
      warn "Source wallpaper missing in repo: $srcfile"
    fi
  done
  log "Wallpapers updated (user + system)."
}

## ---- GRUB theme management ----
manage_grub_theme() {
  local src="$REPO_PATH/grub"
  local t1="/boot/grub/themes/kali"
  local t2="/usr/share/grub/themes"

  log "Installing GRUB theme assets..."
  run sudo mkdir -p "$t1" "$t2"
  run sudo rm -rf "$t1"/* "$t2"/* || true
  run sudo cp -a "$src/"* "$t1/" 2>/dev/null || warn "Failed copying to $t1"
  run sudo cp -a "$src/"* "$t2/" 2>/dev/null || warn "Failed copying to $t2"
  log "GRUB theme assets copied."
}

## ---- Finalization: make scripts executable, restart i3 if running ----
finalize() {
  log "Finalizing: setting executable bits and ownership..."

  run sudo chmod -R 755 "$USER_HOME/.config/i3/scripts/" || true
  run sudo chmod -R 755 "$USER_HOME/.local/bin/" || true
  run sudo chown -R "$REAL_USER":"$REAL_USER" "$USER_HOME/.config/i3" || true
  run sudo chown -R "$REAL_USER":"$REAL_USER" "$USER_HOME/.local" || true

  # If i3 is currently running, restart it as the real user
  if pgrep -x i3 >/dev/null 2>&1 || pgrep -f "i3" >/dev/null 2>&1; then
    log "Detected i3 process. Attempting to restart i3 (i3-msg restart) as $REAL_USER."
    if $DRY_RUN; then
      echo "[DRY] sudo -u \"$REAL_USER\" i3-msg restart"
    else
      sudo -u "$REAL_USER" i3-msg restart 2>/dev/null || warn "i3-msg restart failed (DISPLAY/XAUTH may differ)."
    fi
  else
    log "i3 not detected. Skipping i3 restart to avoid affecting other DEs."
  fi
}

## ---- App installation helpers ----
install_telegram() {
  local src="$REPO_PATH/i3/.local/bin/Telegram"
  local dst="/usr/local/bin/telegram"
  if [ -f "$src" ]; then
    run sudo rm -f "$dst" || true
    run sudo cp -a "$src" "$dst"
    run sudo chmod 755 "$dst"
    log "Telegram binary installed to $dst"
  else
    warn "Telegram binary not found in repo: $src"
  fi
}

install_brave() {
  log "Installing Brave Nightly..."
  run bash -c "curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly sudo -E bash -"
  run sudo apt install -y brave-browser-nightly || warn "brave install failed"
}

install_vscode() {
  local tmp="/tmp/code_latest_$$.deb"
  run sudo rm -f "$tmp" || true
  log "Downloading VS Code .deb..."
  run wget -O "$tmp" "https://update.code.visualstudio.com/latest/linux-deb-x64/stable" || { warn "VSCode download failed"; return 1; }
  log "Installing VS Code..."
  run sudo dpkg -i "$tmp" || true
  run sudo apt install -f -y || warn "Fixed dependencies for VSCode (if any)."
  run rm -f "$tmp"
  log "VS Code installation attempted."
}

install_rustscan() {
  local tmp="/tmp/rustscan_$$.deb"
  run sudo rm -f "$tmp" || true
  log "Downloading RustScan .deb..."
  run wget -O "$tmp" "https://github.com/RustScan/RustScan/releases/latest/download/rustscan_amd64.deb" || warn "RustScan download failed"
  run sudo dpkg -i "$tmp" || true
  run sudo apt install -f -y || true
  run rm -f "$tmp"
  log "RustScan installation attempted."
}

install_spotify() {
  log "Installing Spotify via apt (adding repo)..."
  run sudo apt-get install -y curl gnupg apt-transport-https || true
  run curl -sS https://download.spotify.com/debian/pubkey_0D811D58.gpg | sudo gpg --dearmour -o /usr/share/keyrings/spotify-archive-keyring.gpg || warn "Spotify key add failed"
  run echo "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list >/dev/null
  run sudo apt update -y
  run sudo apt install -y spotify-client || warn "Spotify install failed"
  log "Spotify installation attempted."
}

install_selected_apps() {
  local selection=("$@")
  log "Installing selected apps: ${selection[*]}"
  for choice in "${selection[@]}"; do
    case "$choice" in
      1) install_telegram ;;
      2) install_brave ;;
      3) install_vscode ;;
      4) install_rustscan ;;
      5) install_spotify ;;
      *) warn "Unknown app choice: $choice" ;;
    esac
  done
}

## ---- Single combined user prompt (config choice + app selection) ----
get_user_choices() {
  echo
  cat <<'PROMPT'
** ONE-TIME INPUT REQUIRED **
Choose config action (one digit) AND apps to install (numbers or 'a' for all, 'n' for none).
Enter both on a single line separated by a semicolon ';'
Examples:
  1; a        -> Remove existing configs AND install all apps
  2; n        -> Skip config replacement AND install no apps
  1; 1 3 5    -> Remove configs and install Telegram, VS Code, Spotify

Config choices:
  1) Remove configs (delete existing, no backups) and copy repo configs
  2) Skip configs (do not change existing configs)

Apps (choose numbers separated by space OR 'a' for all OR 'n' for none):
  1) Telegram
  2) Brave Nightly
  3) Visual Studio Code
  4) RustScan
  5) Spotify

Enter input now (format: <1|2>;<a|n|list>): 
PROMPT
  read -r USER_INPUT
  # Parse
  CONFIG_CHOICE="$(echo "$USER_INPUT" | awk -F';' '{print $1}' | tr -d '[:space:]' )"
  APP_PART="$(echo "$USER_INPUT" | awk -F';' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' )"
  # defaults if empty
  if [ -z "$CONFIG_CHOICE" ]; then CONFIG_CHOICE="2"; fi
  if [ -z "$APP_PART" ]; then APP_PART="n"; fi

  # build array of apps to install
  if [ "$APP_PART" = "a" ] || [ "$APP_PART" = "A" ]; then
    APP_ARRAY=(1 2 3 4 5)
  elif [ "$APP_PART" = "n" ] || [ "$APP_PART" = "N" ]; then
    APP_ARRAY=()
  else
    # split spaces into array
    read -r -a APP_ARRAY <<< "$APP_PART"
  fi

  # Validate config choice
  if [ "$CONFIG_CHOICE" != "1" ] && [ "$CONFIG_CHOICE" != "2" ]; then
    warn "Invalid config choice provided; defaulting to '2' (skip)."
    CONFIG_CHOICE="2"
  fi

  # Return values via globals
  USER_CONFIG_CHOICE="$CONFIG_CHOICE"
  USER_APP_SELECTION=("${APP_ARRAY[@]}")
}

## ---- Summary print ----
print_summary() {
  echo
  echo "===== Setup Summary ====="
  for l in "${LOGS[@]}"; do
    echo "$l"
  done
  echo "========================="
}

## ---- Main flow ----
main() {
  check_requirements

  # Step: locate or clone repo
  if ! locate_or_clone_repo; then
    err "Repository required. Exiting."
    print_summary
    exit 1
  fi

  # Verify repo structure
  if ! validate_repo_structure; then
    err "Repo missing required folders. Exiting."
    print_summary
    exit 1
  fi

  # Ask user for config + app choices (single interaction)
  get_user_choices

  # If config choice is "1", we replace; if "2", we skip
  if [ "$USER_CONFIG_CHOICE" = "1" ]; then
    manage_configs "remove"
  else
    manage_configs "skip"
  fi

  # Install dependencies (non-optional)
  install_packages

  # Wallpapers
  manage_wallpapers

  # GRUB theme
  manage_grub_theme

  # Battery service reload
  manage_battery_service

  # Finalization
  finalize

  # Install selected apps (only those user chose)
  if [ ${#USER_APP_SELECTION[@]} -gt 0 ]; then
    # If 'a' used earlier, array populated with all
    install_selected_apps "${USER_APP_SELECTION[@]}"
  else
    log "No apps selected for installation."
  fi

  # Completed
  log "Setup script finished. Printing summary..."
  print_summary
}

# Run main
main "$@"

# End of script
