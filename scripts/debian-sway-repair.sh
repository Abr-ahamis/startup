#!/usr/bin/env bash
# Rebuild the project's managed Sway files, prepare wallpapers, repair GRUB,
# ensure the `pro` account, then reload (or safely start) Sway.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
TARGET_USER="${STARTUP_TARGET_USER:-${SUDO_USER:-${USER:-}}}"
LOG_FILE="/var/log/startup-sway-repair.log"
GRUB_FILE="/etc/default/grub"
WALLPAPER_DIR="/usr/share/backgrounds/gnome"
MANAGED_WALLPAPER_DIR="$WALLPAPER_DIR/startup"
BACKUP_ROOT="/var/backups/startup-sway-repair/$(date +%Y%m%d-%H%M%S)"
GRUB_THEME_SOURCE="$PROJECT_DIR/grub"
GRUB_THEME_DEST="/boot/grub/themes/startup"
if [[ -r /etc/os-release ]]; then
  # Kali keeps its distribution theme under /usr/share/grub/themes/kali;
  # other supported systems use the project-local /boot theme path.
  . /etc/os-release
  [[ "${ID:-}" == kali ]] && GRUB_THEME_DEST="/usr/share/grub/themes/kali"
fi

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }
warn() { log "[WARN] $*" >&2; }
fail() { log "[FAIL] $*" >&2; }

if (( EUID != 0 )); then
  printf 'Please run as root: sudo %q\n' "$0" >&2
  exit 1
fi
if [[ -z "$TARGET_USER" ]] || ! id "$TARGET_USER" >/dev/null 2>&1; then
  printf 'A valid target user is required. Run with sudo from that user account or set STARTUP_TARGET_USER.\n' >&2
  exit 1
fi

TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
mkdir -p -m 700 "$BACKUP_ROOT" /etc/startup-sway-repair || exit 1
touch "$LOG_FILE" && chmod 600 "$LOG_FILE"

replace_or_add_grub_line() {
  local key="${1:-}" value="${2:-}" replacement
  [[ -n "$key" ]] || { warn 'GRUB key is empty'; return 1; }
  if grep -q -- "^${key}=" "$GRUB_FILE"; then
    replacement="${value//\\/\\\\}"
    replacement="${replacement//&/\\&}"
    sed -i "s|^${key}=.*|${key}=${replacement}|" "$GRUB_FILE" || { warn "Could not replace $key"; return 1; }
  else
    printf '%s=%s\n' "$key" "$value" >> "$GRUB_FILE" || { warn "Could not add $key"; return 1; }
  fi
}

repair_grub() {
  if [[ ! -f "$GRUB_FILE" ]]; then
    warn "$GRUB_FILE is missing; creating it."
    install -m 644 /dev/null "$GRUB_FILE" || { fail "Cannot create $GRUB_FILE"; return 1; }
  fi
  cp -a "$GRUB_FILE" "$BACKUP_ROOT/grub" || { fail "Cannot back up $GRUB_FILE"; return 1; }
  replace_or_add_grub_line GRUB_DEFAULT '"0"'
  replace_or_add_grub_line GRUB_TIMEOUT '"2"'
  replace_or_add_grub_line GRUB_TIMEOUT_STYLE menu
  replace_or_add_grub_line GRUB_DISTRIBUTOR '"`( . /etc/os-release && echo ${NAME} )`"'
  replace_or_add_grub_line GRUB_CMDLINE_LINUX_DEFAULT '"quiet"'
  replace_or_add_grub_line GRUB_CMDLINE_LINUX '""'
  replace_or_add_grub_line GRUB_DISABLE_OS_PROBER '"false"'
  chmod 644 "$GRUB_FILE"
}

regenerate_grub() {
  if command -v update-grub >/dev/null 2>&1; then
    update-grub >>"$LOG_FILE" 2>&1 && log '[OK] GRUB configuration regenerated.' || warn 'update-grub failed; inspect the log and backup.'
  elif command -v grub-mkconfig >/dev/null 2>&1 && [[ -d /boot/grub ]]; then
    grub-mkconfig -o /boot/grub/grub.cfg >>"$LOG_FILE" 2>&1 && log '[OK] GRUB configuration regenerated.' || warn 'grub-mkconfig failed; inspect the log and backup.'
  else
    warn 'No usable GRUB configuration generator was found.'
  fi
}

install_grub_theme() {
  [[ -f "$GRUB_THEME_SOURCE/theme.txt" && -f "$GRUB_THEME_SOURCE/grub-16x9.png" ]] || { warn "GRUB theme assets are missing: $GRUB_THEME_SOURCE"; return 1; }
  [[ -d /boot/grub ]] || { warn '/boot/grub is unavailable; cannot install the GRUB theme.'; return 1; }
  [[ -f "$GRUB_FILE" ]] && cp -a "$GRUB_FILE" "$BACKUP_ROOT/grub.before-theme" || true
  rm -rf -- "$GRUB_THEME_DEST" || return 1
  install -d -m 755 "$GRUB_THEME_DEST" || return 1
  cp -a "$GRUB_THEME_SOURCE/." "$GRUB_THEME_DEST/" || return 1
  replace_or_add_grub_line GRUB_THEME "\"$GRUB_THEME_DEST/theme.txt\""
  regenerate_grub
  log '[OK] GRUB theme installed, configured, and regenerated.'
}

install_debian_packages() {
  command -v apt-get >/dev/null 2>&1 || return 1
  DEBIAN_FRONTEND=noninteractive timeout --foreground 20m apt-get install -y --no-install-recommends "$@" >>"$LOG_FILE" 2>&1
}

find_git_libsecret_helper() {
  local helper
  for helper in /usr/local/libexec/git-core/git-credential-libsecret /usr/lib/git-core/git-credential-libsecret /usr/libexec/git-core/git-credential-libsecret; do
    [[ -x "$helper" ]] && { printf '%s\n' "$helper"; return 0; }
  done
  return 1
}

configure_git_libsecret() {
  local helper source_dir=/usr/share/doc/git/contrib/credential/libsecret
  command -v git >/dev/null 2>&1 || install_debian_packages git || return 1
  helper="$(find_git_libsecret_helper || true)"
  if [[ -z "$helper" ]]; then
    install_debian_packages build-essential pkg-config libsecret-1-dev || return 1
    [[ -f "$source_dir/Makefile" ]] || return 1
    make -C "$source_dir" >>"$LOG_FILE" 2>&1 || return 1
    install -D -m 755 "$source_dir/git-credential-libsecret" /usr/local/libexec/git-core/git-credential-libsecret || return 1
    helper="$(find_git_libsecret_helper || true)"
  fi
  [[ -n "$helper" ]] || return 1
  runuser -u "$TARGET_USER" -- git config --global credential.helper "$helper" || return 1
  [[ "$(runuser -u "$TARGET_USER" -- git config --global --get credential.helper 2>/dev/null || true)" == "$helper" ]]
}

configure_pam_keyring() {
  local pam=/etc/pam.d/login module='' line
  install_debian_packages gnome-keyring libsecret-tools libpam-gnome-keyring || return 1
  for module in /usr/lib/*/security/pam_gnome_keyring.so /usr/lib/security/pam_gnome_keyring.so; do [[ -f "$module" ]] && break; module=''; done
  [[ -n "$module" && -f "$pam" ]] || return 1
  cp -a "$pam" "$BACKUP_ROOT/login.pam.bak" || return 1
  for line in 'auth optional pam_gnome_keyring.so' 'session optional pam_gnome_keyring.so auto_start'; do
    grep -qxF -- "$line" "$pam" || printf '%s\n' "$line" >> "$pam"
  done
  grep -qxF -- 'auth optional pam_gnome_keyring.so' "$pam" && grep -qxF -- 'session optional pam_gnome_keyring.so auto_start' "$pam"
}

replace_tree() {
  local source="${1:-}" destination="${2:-}" label="${3:-files}" relative backup
  [[ -d "$source" ]] || { warn "$label source is missing: $source"; return 0; }
  [[ "$destination" == "$TARGET_HOME"/* ]] || { fail "Refusing unsafe replacement target: $destination"; return 1; }
  relative="${destination#"$TARGET_HOME"/}"; backup="$BACKUP_ROOT/$relative"
  if [[ -e "$destination" || -L "$destination" ]]; then
    mkdir -p "$(dirname "$backup")" && cp -a "$destination" "$backup" || { warn "Could not back up $destination; leaving it unchanged."; return 1; }
    rm -rf -- "$destination" || { warn "Could not remove $destination"; return 1; }
  fi
  install -d -m 755 "$destination" && cp -a "$source/." "$destination/" || { warn "Could not rewrite $label"; return 1; }
  chown -R "$TARGET_USER:$TARGET_GROUP" "$destination" || warn "Could not set ownership on $destination"
  find "$destination" -type d -exec chmod 755 {} + 2>/dev/null || warn "Could not set directory modes for $label"
  find "$destination" -type f -exec chmod 644 {} + 2>/dev/null || warn "Could not set file modes for $label"
  find "$destination" -type f -name '*.sh' -exec chmod 755 {} + 2>/dev/null || warn "Could not set executable bits for $label"
  find "$destination" -xtype l -delete 2>/dev/null || warn "Could not remove broken links from $label"
  log "[OK] Replaced $label."
}

replace_managed_files() {
  local config
  for config in foot i3blocks sway flameshot wofi systemd; do
    replace_tree "$PROJECT_DIR/sway/.config/$config" "$TARGET_HOME/.config/$config" "$config configuration"
  done
  replace_tree "$PROJECT_DIR/sway/.local/bin" "$TARGET_HOME/.local/bin" 'user commands'
  replace_tree "$PROJECT_DIR/sway/.local/share/fonts" "$TARGET_HOME/.local/share/fonts" fonts
  runuser -u "$TARGET_USER" -- fc-cache -f "$TARGET_HOME/.local/share/fonts" >>"$LOG_FILE" 2>&1 || warn 'Font cache refresh failed.'
}

prepare_gnome_wallpapers() {
  local source="$PROJECT_DIR/wallpaper" image count=0
  [[ -d "$source" ]] || { warn "Wallpaper source is missing: $source"; return 0; }
  install -d -m 755 "$WALLPAPER_DIR" || { warn "Cannot create $WALLPAPER_DIR"; return 1; }
  if [[ -e "$MANAGED_WALLPAPER_DIR" ]]; then
    cp -a "$MANAGED_WALLPAPER_DIR" "$BACKUP_ROOT/gnome-wallpapers" || { warn 'Could not back up managed wallpapers; leaving them unchanged.'; return 1; }
    rm -rf -- "$MANAGED_WALLPAPER_DIR" || { warn 'Could not remove managed wallpapers.'; return 1; }
  fi
  install -d -m 755 "$MANAGED_WALLPAPER_DIR" || return 1
  for image in "$source"/*; do
    [[ -f "$image" ]] || continue
    case "${image##*.}" in jpg|jpeg|png|webp|jxl|svg) install -m 644 "$image" "$MANAGED_WALLPAPER_DIR/$(basename "$image")" && ((count+=1));; *) warn "Skipping unsupported wallpaper: $image";; esac
  done
  rm -f /etc/startup-sway-repair/wallpaper-sources.conf
  printf 'GNOME_BACKGROUND_DIR=%q\nMANAGED_BACKGROUND_DIR=%q\n' "$WALLPAPER_DIR" "$MANAGED_WALLPAPER_DIR" > /etc/startup-sway-repair/wallpaper-sources.conf
  chmod 644 /etc/startup-sway-repair/wallpaper-sources.conf
  log "[OK] Replaced $count managed wallpaper(s); existing GNOME assets (including .jxl and .svg) were preserved."
}

ask_pro_sudo() {
  local reply group grant
  while true; do
    read -r -p 'Grant user pro sudo/root privileges? [y/n] ' reply || reply=n
    case "${reply,,}" in y|yes) grant=yes; break;; n|no|'') grant=no; break;; *) printf 'Please answer yes or no.\n' >&2;; esac
  done
  group=sudo; getent group sudo >/dev/null 2>&1 || group=wheel
  if [[ "$grant" == yes ]]; then
    getent group "$group" >/dev/null 2>&1 && usermod -aG "$group" pro && log "[OK] pro added to $group." || warn "No sudo-capable group is available."
  else
    getent group "$group" >/dev/null 2>&1 && gpasswd -d pro "$group" >/dev/null 2>&1 || true
    log '[OK] pro does not have sudo privileges.'
  fi
}

ensure_pro_user() {
  if ! id pro >/dev/null 2>&1; then
    useradd -m -s /bin/bash pro && log '[OK] Created user pro.' || { warn 'Could not create user pro.'; return 1; }
  else
    log '[OK] User pro already exists; updating requested privileges.'
  fi
  ask_pro_sudo
}

find_sway_socket() {
  local runtime="/run/user/$TARGET_UID"
  [[ -d "$runtime" ]] || return 1
  find "$runtime" -maxdepth 1 -type s -name 'sway-ipc.*.sock' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {print $2}'
}

reload_or_start_sway() {
  local runtime="/run/user/$TARGET_UID" socket attempt
  printf 'User services, xdg-desktop-portal helper, Sway\n'
  log '[INFO] Reloading sway...'
  socket="$(find_sway_socket || true)"
  if [[ -n "$socket" ]] && runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="$runtime" SWAYSOCK="$socket" swaymsg reload >>"$LOG_FILE" 2>&1; then
    runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="$runtime" SWAYSOCK="$socket" swaymsg -t get_version >>"$LOG_FILE" 2>&1 && { log '[INFO] Sway reload confirmed.'; log '[INFO] For portal diagnosis, run: ~/.config/sway/scripts/fix-sway-portals.sh status'; return 0; }
  fi
  if pgrep -u "$TARGET_USER" -x sway >/dev/null; then warn 'Sway is running but its IPC reload failed; inspect the log for the socket error.'; return 1; fi
  if ! command -v sway >/dev/null 2>&1; then warn 'Sway is not installed; cannot start it.'; return 1; fi
  if [[ "${SETUP_START_SWAY:-0}" != 1 && " ${XDG_CURRENT_DESKTOP:-} ${DESKTOP_SESSION:-} " != *sway* ]]; then warn 'Sway is not running; GNOME or another desktop session was detected and left unchanged. Set SETUP_START_SWAY=1 to start Sway explicitly.'; return 0; fi
  if [[ ! -d "$runtime" ]]; then warn "No active runtime directory for $TARGET_USER; cannot start Sway safely."; return 1; fi
  log '[INFO] No Sway session found; starting Sway for the target user.'
  runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="$runtime" XDG_CURRENT_DESKTOP=sway sway >>"$LOG_FILE" 2>&1 &
  for attempt in {1..20}; do
    sleep 1; socket="$(find_sway_socket || true)"
    [[ -n "$socket" ]] && runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="$runtime" SWAYSOCK="$socket" swaymsg reload >>"$LOG_FILE" 2>&1 && runuser -u "$TARGET_USER" -- env XDG_RUNTIME_DIR="$runtime" SWAYSOCK="$socket" swaymsg -t get_version >>"$LOG_FILE" 2>&1 && { log '[INFO] Sway reload confirmed.'; return 0; }
  done
  warn 'Sway did not start within 20 seconds. GNOME and other desktop sessions were left untouched.'
  return 1
}

repair_exit() {
  local rc=$?
  if (( rc == 0 )); then
    reload_or_start_sway || true
  else
    log "[INFO] Repair exited with status $rc; Sway was left unchanged."
  fi
}
repair_interrupted() {
  log '[INFO] Interrupted; stopping without reloading or starting Sway.'
  exit 130
}
trap repair_exit EXIT
trap repair_interrupted INT TERM HUP

# Do not refresh APT on every repair run.  `apt-get install` uses the local
# cache immediately; a refresh is only useful when an install actually fails.
ensure_pro_user || true
replace_managed_files
prepare_gnome_wallpapers
repair_grub
install_grub_theme
configure_git_libsecret && log '[OK] Git libsecret credential helper configured and verified.' || warn 'Git libsecret configuration could not be completed.'
configure_pam_keyring && log '[OK] PAM GNOME Keyring integration configured and verified.' || warn 'PAM GNOME Keyring integration could not be completed.'
log "[INFO] Repair tasks completed. Backups: $BACKUP_ROOT"
