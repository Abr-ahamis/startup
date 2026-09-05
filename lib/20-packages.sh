#!/usr/bin/env bash
# Package abstraction. Logical features are mapped per supported distribution family.

if [[ -n "${__SETUP_PACKAGES_LOADED:-}" ]]; then return 0; fi
__SETUP_PACKAGES_LOADED=1

SETUP_BACKUP_DIR="$SETUP_BASE_DIR/installer-backups/$SETUP_TIMESTAMP"
FAILED_REQUIRED_PACKAGES=() REQUIRED_PACKAGES=() MISSING_PACKAGES=()
# A short default prevents an installer appearing stuck behind another package
# manager.  Override with SETUP_APT_LOCK_TIMEOUT=SECONDS when needed.
SETUP_APT_LOCK_TIMEOUT="${SETUP_APT_LOCK_TIMEOUT:-20}"

package_for() {
  local feature="$1"
  case "$DISTRO_FAMILY:$feature" in
    debian:python) echo python3;; arch:python) echo python;;
    debian:notify) echo libnotify-bin;; arch:notify) echo libnotify;;
    debian:network) echo network-manager network-manager-gnome;; arch:network) echo networkmanager network-manager-applet;;
    debian:secret) echo libsecret-1-0 libsecret-tools;; arch:secret) echo libsecret;;
    debian:keyring_pam) echo libpam-gnome-keyring;; arch:keyring_pam) echo gnome-keyring;;
    debian:git_libsecret) echo build-essential pkg-config libsecret-1-dev;; arch:git_libsecret) echo base-devel pkgconf libsecret;;
    debian:portal) echo xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk;; arch:portal) echo xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk;;
    debian:audio) echo pipewire pipewire-pulse wireplumber;; arch:audio) echo pipewire pipewire-pulse wireplumber;;
    debian:clipboard|arch:clipboard) echo cliphist;;
    debian:bluetooth) echo bluez;; arch:bluetooth) echo bluez-utils;;
    debian:core) echo swaybg swayidle swaylock wofi foot dex gammastep flameshot grim slurp pipewire pipewire-pulse wireplumber pamixer wl-clipboard cliphist network-manager network-manager-gnome bluez blueman rfkill xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk dbus-user-session brightnessctl dunst libnotify-bin fontconfig jq curl gnome-keyring grub-customizer timeshift libsecret-1-0 libsecret-tools seahorse gnupg age apparmor bubblewrap cryptsetup build-essential pkg-config libsecret-1-dev libpam-gnome-keyring git grub2-common;;
    arch:core) echo swaybg swayidle swaylock wofi foot dex gammastep flameshot grim slurp pipewire pipewire-pulse wireplumber pamixer wl-clipboard cliphist networkmanager network-manager-applet bluez bluez-utils blueman rfkill xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk dbus brightnessctl dunst libnotify fontconfig jq curl gnome-keyring timeshift libsecret seahorse gnupg age apparmor bubblewrap cryptsetup base-devel pkgconf git;;
    *) return 1;;
  esac
}

package_installed() { case "$PKG_MANAGER" in apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qx 'install ok installed';; pacman) pacman -Q "$1" >/dev/null 2>&1;; esac; }
package_available() { case "$PKG_MANAGER" in apt) apt-cache show "$1" >/dev/null 2>&1;; pacman) pacman -Si "$1" >/dev/null 2>&1;; esac; }

prepare_grub_customizer() {
  [[ "$DISTRO_ID" == ubuntu ]] || return 0
  package_installed grub-customizer || package_available grub-customizer && return 0
  command -v add-apt-repository >/dev/null 2>&1 || return 1
  timeout --foreground 90s add-apt-repository --yes ppa:danielrichter2007/grub-customizer >>"$SETUP_LOG_FILE" 2>&1 || return 1
  timeout --foreground 180s apt-get update >>"$SETUP_LOG_FILE" 2>&1
}

repair_apt() {
  info "Repairing APT/dpkg state."
  run_as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 10m apt-get -f install -y >>"$SETUP_LOG_FILE" 2>&1 || true
  run_as_root timeout --foreground 5m dpkg --configure -a >>"$SETUP_LOG_FILE" 2>&1 || true
}

package_display_name() {
  case "$1" in
    libsecret-1-0) printf '%s' 'libsecret-1-0' ;;
    libsecret-tools) printf '%s' 'libsecret-tools' ;;
    gnome-keyring) printf '%s' 'GNOME Keyring' ;;
    seahorse) printf '%s' 'Seahorse' ;;
    gnupg) printf '%s' 'GnuPG' ;;
    age) printf '%s' 'Age encryption' ;;
    apparmor) printf '%s' 'AppArmor' ;;
    bubblewrap) printf '%s' 'Bubblewrap' ;;
    cryptsetup) printf '%s' 'Cryptsetup' ;;
    *) printf '%s' "$1" ;;
  esac
}

package_done() {
  local package="$1" label
  label="$(package_display_name "$package")"
  case "$package" in
    libsecret-1-0|libsecret-tools) ok_indented "installed: $label" ;;
    *) ok_indented "installed: $label" ;;
  esac
}

package_progress() {
  local percent="$1" package="$2" filled empty bar
  filled=$(( percent * 45 / 100 )); empty=$((45 - filled)); bar=''
  printf -v bar '%*s' "$filled" ''; bar="${bar// /#}"
  local remainder; printf -v remainder '%*s' "$empty" ''; remainder="${remainder// /-}"
  printf '  [▶ WORK] [%s%s] %3d%%  %s install: %s\n' "$bar" "$remainder" "$percent" "$PKG_MANAGER" "$package"
}

install_package() {
  local package="$1" pid rc
  _setup_log_write INFO "Installing package: $package (manager=$PKG_MANAGER)"
  package_progress 0 "$package"
  case "$PKG_MANAGER" in
    apt)
      run_as_root env DEBIAN_FRONTEND=noninteractive timeout 20m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$package" >>"$SETUP_LOG_FILE" 2>&1 &
      ;;
    pacman)
      run_as_root timeout --foreground 20m pacman -S --needed --noconfirm "$package" >>"$SETUP_LOG_FILE" 2>&1 &
      ;;
  esac
  pid=$!
  SETUP_ACTIVE_PID="$pid"
  printf '%s\n' "$pid" >"$SETUP_ACTIVE_PID_FILE"
  while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
  wait "$pid"; rc=$?
  SETUP_ACTIVE_PID=""
  rm -f -- "$SETUP_ACTIVE_PID_FILE"
  if (( rc == 0 )) && package_installed "$package"; then
    package_progress 100 "$package"
    package_done "$package"
    return 0
  fi
  warn "$package failed to install; see $SETUP_LOG_FILE"
  return 1
}

install_packages() {
  local package failed=0
  (( $# )) || return 0
  for package in "$@"; do
    install_package "$package" || failed=1
  done
  return "$failed"
}

remove_packages() {
  local package failed=0 pid rc
  (( $# )) || return 0
  for package in "$@"; do
    case "$PKG_MANAGER" in
      apt)
        run_as_root env DEBIAN_FRONTEND=noninteractive timeout 20m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -o Dpkg::Use-Pty=0 remove -y "$package" >>"$SETUP_LOG_FILE" 2>&1 &
        ;;
      pacman)
        if (( EUID == 0 )); then setsid timeout --foreground 20m pacman -Rns --noconfirm "$package" >>"$SETUP_LOG_FILE" 2>&1 & else setsid sudo timeout --foreground 20m pacman -Rns --noconfirm "$package" >>"$SETUP_LOG_FILE" 2>&1 & fi
        ;;
    esac
    pid=$!; SETUP_ACTIVE_PID="$pid"; printf '%s\n' "$pid" >"$SETUP_ACTIVE_PID_FILE"
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    wait "$pid"; rc=$?; SETUP_ACTIVE_PID=""; rm -f -- "$SETUP_ACTIVE_PID_FILE"
    if (( rc == 0 )) && ! package_installed "$package"; then ok "$package removed"; else warn "$package could not be removed; see $SETUP_LOG_FILE"; failed=1; fi
  done
  return "$failed"
}

collect_required_packages() {
  local feature pkg package_list
  local -A seen=()
  REQUIRED_PACKAGES=()
  for feature in core network secret portal audio clipboard bluetooth python notify; do
    package_list="$(package_for "$feature")" || { warn "No package mapping for feature '$feature'"; continue; }
    for pkg in $package_list; do
      [[ -n "${seen[$pkg]:-}" ]] && continue
      seen["$pkg"]=1
      REQUIRED_PACKAGES+=("$pkg")
    done
  done
}

# Used by the optional security repair stage.  The main stage above deliberately
# installs all missing packages in one fast transaction.
install_feature() {
  local feature="$1" pkg package_list
  local missing=()
  package_list="$(package_for "$feature")" || { warn "No package mapping for feature '$feature'"; return 1; }
  for pkg in $package_list; do
    if ! package_installed "$pkg"; then missing+=("$pkg"); fi
  done
  (( ${#missing[@]} )) || return 0
  install_packages "${missing[@]}"
}

backup_package_selections() {
  case "$PKG_MANAGER" in
    apt)
      run_as_root sh -c 'dpkg --get-selections > "$1"' sh "$SETUP_BACKUP_DIR/dpkg-selections.txt" || warn "Could not back up dpkg selections"
      run_as_root sh -c 'apt-mark showmanual > "$1"' sh "$SETUP_BACKUP_DIR/apt-manual.txt" || warn "Could not back up APT manual selections"
      ;;
    pacman)
      run_as_root pacman -Qqe >"$SETUP_BACKUP_DIR/pacman-explicit.txt" 2>/dev/null || warn "Could not back up pacman selections"
      ;;
  esac
}

check_package_disk_space() {
  local available_kib
  available_kib="$(df -Pk /var/cache/apt 2>/dev/null | awk 'NR == 2 { print $4 }')"
  [[ "$available_kib" =~ ^[0-9]+$ ]] || return 0
  if (( available_kib < 524288 )); then
    warn "Only $((available_kib / 1024)) MiB is free on the package filesystem. Free at least 512 MiB, then run the installer again."
    return 1
  fi
}

run_packages() {
  local backup_ready=0
  cleanup_previous_package_process
  _setup_log_write SECTION "Pre-install backup"
  if ! run_as_root install -d -m 700 "$SETUP_BACKUP_DIR"; then
    warn "Cannot create installer backup directory: $SETUP_BACKUP_DIR. Package installation will continue safely."
  else
    # Ensure the installer backup directory is owned by the target user so
    # non-root steps can read/write reports and backups when appropriate.
    run_as_root chown -R "$TARGET_USER:$TARGET_GROUP" "$SETUP_BACKUP_DIR" || warn "Could not set ownership on $SETUP_BACKUP_DIR"
    _setup_log_write INFO "Backup directory ready: $SETUP_BACKUP_DIR"
    backup_ready=1
    backup_package_selections
  fi
  printf '  ──────────────────────────────────────────────────────────────────────\n'
  printf '  ▶  installation progress\n'
  printf '  ──────────────────────────────────────────────────────────────────────\n'
  # Refresh package metadata only (never upgrade installed packages), and
  # repair interrupted Debian transactions before installing anything.
  if [[ "$PKG_MANAGER" == apt ]]; then
    check_package_disk_space || return 1
    # Authenticate while attached to the terminal; package jobs run in the
    # background and must never block waiting for a hidden sudo prompt.
    run_as_root true || return 1
  fi
  prepare_grub_customizer || _setup_log_write WARN 'GRUB Customizer repository preparation was unavailable.'
  collect_required_packages
  MISSING_PACKAGES=()
  local total="${#REQUIRED_PACKAGES[@]}" index=0 pkg
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    index=$((index + 1))
    if package_installed "$pkg"; then
      package_done "$pkg"
    elif package_available "$pkg"; then
      MISSING_PACKAGES+=("$pkg")
    else
      FAILED_REQUIRED_PACKAGES+=("$pkg")
      printf '  %s[WARN]%s unavailable: %s\n' "$SETUP_COLOR_WARN" "$SETUP_COLOR_RST" "$pkg"
    fi
  done
  if (( ${#MISSING_PACKAGES[@]} )); then
    if ! install_packages "${MISSING_PACKAGES[@]}"; then
      if [[ "$PKG_MANAGER" == apt ]]; then
        _setup_log_write INFO "Package install failed; running repair commands and retrying once."
        repair_apt
      fi
      install_packages "${MISSING_PACKAGES[@]}" || true
    fi
    for pkg in "${MISSING_PACKAGES[@]}"; do
      if ! package_installed "$pkg"; then
        FAILED_REQUIRED_PACKAGES+=("$pkg")
      fi
    done
    if (( ${#FAILED_REQUIRED_PACKAGES[@]} )); then
      _setup_log_write WARN "Packages failed: ${FAILED_REQUIRED_PACKAGES[*]}"
    else
      ok_indented "All required packages installed. [${#REQUIRED_PACKAGES[@]} components]"
    fi
  else
    ok_indented "All required packages installed. [${#REQUIRED_PACKAGES[@]} components]"
  fi
  if (( backup_ready )); then
    # The backup directory is intentionally root-only.  The elevated tee owns
    # the redirection, avoiding the old "Permission denied" report failure.
    if ! printf 'Distro: %s\nRequired: %s\nMissing before install: %s\nFailed: %s\n' \
      "$DISTRO_PRETTY" "${REQUIRED_PACKAGES[*]}" "${MISSING_PACKAGES[*]:-(none)}" "${FAILED_REQUIRED_PACKAGES[*]:-(none)}" \
      | run_as_root tee "$SETUP_BACKUP_DIR/install-report.txt" >/dev/null; then
      warn "Could not write package report"
    else
      run_as_root chmod 600 "$SETUP_BACKUP_DIR/install-report.txt" || warn "Could not secure package report permissions"
    fi
  fi
}
