#!/usr/bin/env bash
# Package discovery, one-transaction installation, and independent verification.
if [[ -n "${__SETUP_PACKAGES_LOADED:-}" ]]; then return 0; fi
__SETUP_PACKAGES_LOADED=1
SETUP_BACKUP_DIR="$SETUP_BASE_DIR/installer-backups/$SETUP_TIMESTAMP"
FAILED_REQUIRED_PACKAGES=() REQUIRED_PACKAGES=() MISSING_PACKAGES=() INVALID_PACKAGES=()
SETUP_APT_LOCK_TIMEOUT="${SETUP_APT_LOCK_TIMEOUT:-60}"

package_for() {
  local feature="$1"
  case "$DISTRO_FAMILY:$feature" in
    debian:python) echo python3;; arch:python) echo python;; debian:notify) echo libnotify-bin;; arch:notify) echo libnotify;;
    debian:network) echo network-manager network-manager-gnome;; arch:network) echo networkmanager network-manager-applet;;
    debian:secret) echo libsecret-1-0 libsecret-tools;; arch:secret) echo libsecret;;
    debian:keyring_pam) echo libpam-gnome-keyring;; arch:keyring_pam) echo gnome-keyring;;
    debian:git_libsecret) echo build-essential pkg-config libsecret-1-dev;; arch:git_libsecret) echo base-devel pkgconf libsecret;;
    debian:portal|arch:portal) echo xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk;; debian:audio|arch:audio) echo pipewire pipewire-pulse wireplumber;;
    debian:clipboard|arch:clipboard) echo cliphist;; debian:bluetooth) echo bluez;; arch:bluetooth) echo bluez-utils;;
    debian:core) echo sway swaybg swayidle swaylock i3blocks wofi foot dex gammastep flameshot grim slurp pipewire pipewire-pulse wireplumber pamixer wl-clipboard cliphist network-manager network-manager-gnome bluez blueman rfkill xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk dbus-user-session brightnessctl dunst libnotify-bin fontconfig jq curl gnome-keyring grub-customizer timeshift libsecret-1-0 libsecret-tools seahorse gnupg age apparmor bubblewrap cryptsetup build-essential pkg-config libsecret-1-dev libpam-gnome-keyring git grub2-common;;
    arch:core) echo sway swaybg swayidle swaylock i3blocks wofi foot dex gammastep flameshot grim slurp pipewire pipewire-pulse wireplumber pamixer wl-clipboard cliphist networkmanager network-manager-applet bluez bluez-utils blueman rfkill xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk dbus brightnessctl dunst libnotify fontconfig jq curl gnome-keyring timeshift libsecret seahorse gnupg age apparmor bubblewrap cryptsetup base-devel pkgconf git;;
    *) return 1;; esac
}
package_get_version() { case "$PKG_MANAGER" in apt) dpkg-query -W -f='${Version}' "$1" 2>/dev/null;; pacman) pacman -Q "$1" 2>/dev/null | awk '{print $2}';; esac; }
package_expected_command() {
  case "$1" in
    sway|swaybg|swayidle|swaylock|i3blocks|wofi|foot|dex|gammastep|flameshot|grim|slurp|pipewire|pipewire-pulse|wireplumber|pamixer|cliphist|rfkill|brightnessctl|dunst|jq|curl|timeshift|seahorse|age|cryptsetup|git|python3|pkg-config) printf '%s\n' "$1" ;;
    wl-clipboard) echo wl-copy;; network-manager|networkmanager) echo nmcli;; network-manager-gnome|network-manager-applet) echo nm-applet;;
    bluez|bluez-utils) echo bluetoothd;; blueman) echo blueman-manager;; libnotify-bin|libnotify) echo notify-send;; fontconfig) echo fc-cache;;
    gnome-keyring) echo gnome-keyring-daemon;; grub-customizer) echo grub-customizer;; libsecret-tools) echo secret-tool;; gnupg) echo gpg;; apparmor) echo aa-status;; bubblewrap) echo bwrap;;
  esac
}
# Check 1: package-database installed state.  Check 2 (below) is distinct.
package_installed() { case "$PKG_MANAGER" in apt) [[ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" == installed ]];; pacman) pacman -Qq "$1" >/dev/null 2>&1;; *) return 1;; esac; }
package_verify() {
  local package="$1" expected="${2:-}" version status
  if ! package_installed "$package"; then PACKAGE_VERIFY_REASON='package database does not report installed'; record_verification "$package" FAILED "$PACKAGE_VERIFY_REASON"; return 1; fi
  version="$(package_get_version "$package")"; [[ -n "$version" ]] || { PACKAGE_VERIFY_REASON='installed package has no version'; record_verification "$package" FAILED "$PACKAGE_VERIFY_REASON"; return 1; }
  [[ -z "$expected" || "$version" == "$expected" ]] || { PACKAGE_VERIFY_REASON="version $version does not equal required $expected"; record_verification "$package" FAILED "$PACKAGE_VERIFY_REASON"; return 1; }
  case "$PKG_MANAGER" in
    apt) status="$(dpkg -s "$package" 2>/dev/null | awk -F': ' '$1=="Status" {print $2}')"; [[ "$status" == 'install ok installed' ]] || { PACKAGE_VERIFY_REASON="dpkg status is ${status:-missing}"; record_verification "$package" FAILED "$PACKAGE_VERIFY_REASON"; return 1; };;
    pacman) pacman -Qi "$package" >/dev/null 2>&1 || { PACKAGE_VERIFY_REASON='pacman -Qi failed'; record_verification "$package" FAILED "$PACKAGE_VERIFY_REASON"; return 1; };; esac
  local expected_command
  expected_command="$(package_expected_command "$package" || true)"
  if [[ -n "$expected_command" ]] && ! command -v "$expected_command" >/dev/null 2>&1; then
    PACKAGE_VERIFY_REASON="database is installed but expected executable is absent: $expected_command"; record_verification "$package" FAILED "$PACKAGE_VERIFY_REASON"; return 1
  fi
  PACKAGE_VERIFY_REASON="version=$version${expected_command:+ command=$expected_command}"; record_verification "$package" OK "$PACKAGE_VERIFY_REASON"
}
package_available() { case "$PKG_MANAGER" in apt) apt-cache show "$1" >/dev/null 2>&1;; pacman) pacman -Si "$1" >/dev/null 2>&1;; esac; }
package_done() { local version; version="$(package_get_version "$1")"; ok_indented "verified: $1${version:+ ($version)}"; }
run_package_command() { local label="$1"; shift; local pid rc; _setup_log_write COMMAND "$label: $(printf '%q ' "$@")"; "$@" >>"$SETUP_LOG_FILE" 2>&1 & pid=$!; SETUP_ACTIVE_PID="$pid"; printf '%s\n' "$pid" >"$SETUP_ACTIVE_PID_FILE"; wait "$pid"; rc=$?; SETUP_ACTIVE_PID=''; rm -f -- "$SETUP_ACTIVE_PID_FILE"; _setup_log_write COMMAND "$label: exit=$rc"; return "$rc"; }
repair_apt() { info 'Repairing interrupted APT/dpkg state before one retry.'; run_package_command 'dpkg configure' run_as_root timeout --foreground 5m dpkg --configure -a && run_package_command 'apt dependency repair' run_as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 10m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -f install -y; }
refresh_package_metadata() {
  # APT metadata is refreshed once before availability decisions.  Pacman is
  # intentionally not given a standalone -Sy: that can create a partial upgrade.
  [[ "$PKG_MANAGER" != apt ]] || run_package_command 'apt metadata refresh' run_as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 10m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" update
}
package_install_batch() {
  local package
  (( $# )) || return 0
  for package in "$@"; do
    printf '  %s[~~]%s installing: %s\n' "$SETUP_COLOR_INFO" "$SETUP_COLOR_RST" "$package"
    _setup_log_write INSTALL "package=$package requested-manager=$PKG_MANAGER"
  done
  case "$PKG_MANAGER" in
    apt) run_package_command 'apt batch install' run_as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 30m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$@";;
    pacman) run_package_command 'pacman batch install' run_as_root timeout --foreground 30m pacman -S --needed --noconfirm "$@";;
    *) return 1;;
  esac
}
install_packages() { local p; local -A seen=(); local -a todo=(); for p in "$@"; do [[ -n "$p" && -z "${seen[$p]:-}" ]] || continue; seen[$p]=1; package_verify "$p" || todo+=("$p"); done; (( ${#todo[@]} == 0 )) || package_install_batch "${todo[@]}"; }
install_package() { install_packages "$1"; }
remove_packages() { (( $# )) || return 0; case "$PKG_MANAGER" in apt) run_package_command 'apt batch remove' run_as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 20m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" remove -y "$@";; pacman) run_package_command 'pacman batch remove' run_as_root timeout --foreground 20m pacman -Rns --noconfirm "$@";; esac; }
collect_required_packages() { local feature pkg list; local -A seen=(); REQUIRED_PACKAGES=(); for feature in core network secret portal audio clipboard bluetooth python notify; do list="$(package_for "$feature")" || { required_failure "No package mapping for required feature: $feature"; continue; }; for pkg in $list; do [[ -n "${seen[$pkg]:-}" ]] && continue; seen[$pkg]=1; REQUIRED_PACKAGES+=("$pkg"); done; done; }
install_feature() { local list; list="$(package_for "$1")" || return 1; local -a p=(); read -r -a p <<<"$list"; install_packages "${p[@]}"; }
backup_package_selections() { case "$PKG_MANAGER" in apt) run_as_root sh -c 'dpkg --get-selections > "$1"' sh "$SETUP_BACKUP_DIR/dpkg-selections.txt" || warn 'Could not back up dpkg selections';; pacman) run_as_root sh -c 'pacman -Qqe > "$1"' sh "$SETUP_BACKUP_DIR/pacman-explicit.txt" || warn 'Could not back up pacman selections';; esac; }
run_packages() {
  local pkg; cleanup_previous_package_process; run_as_root install -d -m 700 "$SETUP_BACKUP_DIR" || { required_failure "Cannot create backup directory: $SETUP_BACKUP_DIR"; return 1; }; backup_package_selections; refresh_package_metadata || { required_failure 'APT metadata refresh failed; package availability cannot be trusted'; return 1; }; collect_required_packages; MISSING_PACKAGES=() INVALID_PACKAGES=() FAILED_REQUIRED_PACKAGES=()
  for pkg in "${REQUIRED_PACKAGES[@]}"; do if package_verify "$pkg"; then package_done "$pkg"; elif package_available "$pkg"; then MISSING_PACKAGES+=("$pkg"); [[ "$PACKAGE_VERIFY_REASON" != 'package database does not report installed' ]] && INVALID_PACKAGES+=("$pkg"); else FAILED_REQUIRED_PACKAGES+=("$pkg"); required_failure "Required package unavailable in configured repositories: $pkg"; fi; done
  if (( ${#MISSING_PACKAGES[@]} )); then
    info "Installing ${#MISSING_PACKAGES[@]} missing/invalid package(s) in one $PKG_MANAGER transaction."
    if ! package_install_batch "${MISSING_PACKAGES[@]}" && [[ "$PKG_MANAGER" == apt ]]; then
      if repair_apt; then package_install_batch "${MISSING_PACKAGES[@]}" || _setup_log_write ERROR 'APT retry failed'; else _setup_log_write ERROR 'APT repair failed'; fi
    fi
  fi
  for pkg in "${REQUIRED_PACKAGES[@]}"; do if package_verify "$pkg"; then package_done "$pkg"; else FAILED_REQUIRED_PACKAGES+=("$pkg"); required_failure "Required package verification failed: $pkg ($PACKAGE_VERIFY_REASON)"; fi; done
  (( ${#FAILED_REQUIRED_PACKAGES[@]} == 0 )) || return 1; ok_indented "All required packages independently verified. [${#REQUIRED_PACKAGES[@]} components]"
}
