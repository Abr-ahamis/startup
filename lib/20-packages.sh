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
    debian:core) echo sway swaybg swayidle swaylock i3blocks wofi foot flameshot nemo brightnessctl pamixer wl-clipboard grim slurp dex git curl wget unzip pipx btop gnome-keyring seahorse gnupg age apparmor bubblewrap cryptsetup fontconfig jq file gammastep blueman sudo grub2-common;;
    arch:core) echo sway swaybg swayidle swaylock i3blocks wofi foot flameshot nemo brightnessctl pamixer wl-clipboard grim slurp dex git curl wget unzip pipx btop gnome-keyring seahorse gnupg age apparmor bubblewrap cryptsetup fontconfig jq file gammastep blueman;;
    *) return 1;;
  esac
}

package_installed() { case "$PKG_MANAGER" in apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qx 'install ok installed';; pacman) pacman -Q "$1" >/dev/null 2>&1;; esac; }
package_available() { case "$PKG_MANAGER" in apt) apt-cache show "$1" >/dev/null 2>&1;; pacman) pacman -Si "$1" >/dev/null 2>&1;; esac; }
package_progress() {
  local package="$1" percent="$2" state="$3" filled empty bar=''
  filled=$((percent / 5)); empty=$((20 - filled))
  bar="$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' "$empty" '' | tr ' ' '-')"
  printf '\r[?] %-20s [%s] %3d%% %s' "$package" "$bar" "$percent" "$state"
}

install_package() {
  local package="$1" pid percent=0 rc
  case "$PKG_MANAGER" in
    apt)
      # sudo is authenticated before package jobs are started.  Starting it in
      # a separate session can lose that context and make every package fail.
      if [[ "${SETUP_REINSTALL:-0}" == 1 ]]; then
        run_as_root env DEBIAN_FRONTEND=noninteractive timeout 20m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -o Dpkg::Use-Pty=0 install -y --reinstall --no-install-recommends "$package" >>"$SETUP_LOG_FILE" 2>&1 &
      else
        run_as_root env DEBIAN_FRONTEND=noninteractive timeout 20m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$package" >>"$SETUP_LOG_FILE" 2>&1 &
      fi
      ;;
    pacman)
      if [[ "${SETUP_REINSTALL:-0}" == 1 ]]; then run_as_root timeout --foreground 20m pacman -S --noconfirm "$package"; else run_as_root timeout --foreground 20m pacman -S --needed --noconfirm "$package"; fi >>"$SETUP_LOG_FILE" 2>&1 &
      ;;
  esac
  pid=$!
  SETUP_ACTIVE_PID="$pid"
  printf '%s\n' "$pid" >"$SETUP_ACTIVE_PID_FILE"
  while kill -0 "$pid" 2>/dev/null; do
    package_progress "$package" "$percent" "installing"
    (( percent < 90 )) && percent=$((percent + 5))
    sleep 0.2
  done
  wait "$pid"; rc=$?
  SETUP_ACTIVE_PID=""
  rm -f -- "$SETUP_ACTIVE_PID_FILE"
  if (( rc == 0 )) && package_installed "$package"; then
    package_progress "$package" 100 "installed"
    printf '\n'
    return 0
  fi
  package_progress "$package" 100 "failed"
  printf '\n'
  return 1
}

install_packages() {
  local package failed=0 rc
  (( $# )) || return 0
  # APT resolves dependencies and downloads much faster in one transaction.
  # Keep it attached to this terminal's authenticated sudo session; never run
  # concurrent APT commands.
  if [[ "$PKG_MANAGER" == apt ]]; then
    info "Installing $# package(s) in one APT transaction."
    if [[ "${SETUP_REINSTALL:-0}" == 1 ]]; then
      run_as_root env DEBIAN_FRONTEND=noninteractive timeout 20m apt-get \
        -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" \
        -o Dpkg::Use-Pty=0 -o Acquire::Retries=3 -o Acquire::Queue-Mode=host \
        install -y --reinstall --no-install-recommends "$@" >>"$SETUP_LOG_FILE" 2>&1
    else
      run_as_root env DEBIAN_FRONTEND=noninteractive timeout 20m apt-get \
        -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" \
        -o Dpkg::Use-Pty=0 -o Acquire::Retries=3 -o Acquire::Queue-Mode=host \
        install -y --no-install-recommends "$@" >>"$SETUP_LOG_FILE" 2>&1
    fi
    rc=$?
    if (( rc != 0 )); then
      for package in "$@"; do package_progress "$package" 100 "failed"; printf '\n'; done
    fi
    return "$rc"
  fi
  for package in "$@"; do
    install_package "$package" || failed=1
  done
  return "$failed"
}

remove_packages() {
  local package failed=0 pid percent rc
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
    pid=$!; percent=0; SETUP_ACTIVE_PID="$pid"; printf '%s\n' "$pid" >"$SETUP_ACTIVE_PID_FILE"
    while kill -0 "$pid" 2>/dev/null; do package_progress "$package" "$percent" "removing"; (( percent < 90 )) && percent=$((percent + 5)); sleep 0.2; done
    wait "$pid"; rc=$?; SETUP_ACTIVE_PID=""; rm -f -- "$SETUP_ACTIVE_PID_FILE"
    if (( rc == 0 )) && ! package_installed "$package"; then package_progress "$package" 100 "removed"; printf '\n'; else package_progress "$package" 100 "failed"; printf '\n'; failed=1; fi
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
    if package_installed "$pkg"; then ok "$pkg is already installed"; else missing+=("$pkg"); fi
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
  section_setup "Pre-install backup"
  if ! run_as_root install -d -m 700 "$SETUP_BACKUP_DIR"; then
    warn "Cannot create installer backup directory: $SETUP_BACKUP_DIR. Package installation will continue safely."
  else
    _setup_log_write INFO "Backup directory ready: $SETUP_BACKUP_DIR"
    backup_ready=1
    backup_package_selections
  fi
  if (( ${#SETUP_REMOVE_PACKAGES[@]} )); then
    remove_packages "${SETUP_REMOVE_PACKAGES[@]}" || warn "One or more requested removals failed"
  fi
  section_setup "Installing REQUIRED packages"
  # Refresh package metadata only (never upgrade installed packages), and
  # repair interrupted Debian transactions before installing anything.
  if [[ "$PKG_MANAGER" == apt ]]; then
    check_package_disk_space || return 1
    info "Refreshing APT....."
    run_as_root env DEBIAN_FRONTEND=noninteractive timeout 5m apt-get \
      -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -o Acquire::Retries=3 -o Acquire::Queue-Mode=host \
      update >>"$SETUP_LOG_FILE" 2>&1 || warn "APT package-index refresh failed; cached metadata will be used."
   
    run_as_root dpkg --configure -a >>"$SETUP_LOG_FILE" 2>&1 || warn "dpkg --configure -a could not complete; installation will continue only if APT can repair it."
    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -f install -y >>"$SETUP_LOG_FILE" 2>&1 || warn "APT dependency repair failed; installation will continue."
    # Authenticate while attached to the terminal; package jobs run in the
    # background and must never block waiting for a hidden sudo prompt.
    run_as_root true || return 1
  fi
  collect_required_packages
  MISSING_PACKAGES=()
  local total="${#REQUIRED_PACKAGES[@]}" index=0 pkg
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    index=$((index + 1))
    if package_installed "$pkg" && [[ "${SETUP_REINSTALL:-0}" != 1 ]]; then
      ok "$pkg installed"
    else
      MISSING_PACKAGES+=("$pkg")
    fi
  done
  if (( ${#MISSING_PACKAGES[@]} )); then
    info "Installing ${#MISSING_PACKAGES[@]} missing package(s). Detailed APT output: $SETUP_LOG_FILE"
    if ! install_packages "${MISSING_PACKAGES[@]}"; then
      warn "Package installation failed; repairing the package manager and retrying once."
      if [[ "$PKG_MANAGER" == apt ]]; then
        run_as_root dpkg --configure -a >>"$SETUP_LOG_FILE" 2>&1 || true
        run_as_root apt-get -f install -y >>"$SETUP_LOG_FILE" 2>&1 || true
      fi
      install_packages "${MISSING_PACKAGES[@]}" || warn "Package installation still has failures; inspect $SETUP_LOG_FILE."
    fi
    for pkg in "${MISSING_PACKAGES[@]}"; do
      if package_installed "$pkg"; then ok "$pkg installed and verified"; else warn "$pkg failed to install"; FAILED_REQUIRED_PACKAGES+=("$pkg"); fi
    done
  else
    ok "All $total required packages are already installed."
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
