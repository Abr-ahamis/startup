#!/usr/bin/env bash
# Package discovery, one-transaction installation, and independent verification.
if [[ -n "${__SETUP_PACKAGES_LOADED:-}" ]]; then return 0; fi
__SETUP_PACKAGES_LOADED=1
SETUP_BACKUP_DIR="$SETUP_BASE_DIR/installer-backups/$SETUP_TIMESTAMP"
FAILED_REQUIRED_PACKAGES=() REQUIRED_PACKAGES=() MISSING_PACKAGES=() INVALID_PACKAGES=()
SETUP_APT_LOCK_TIMEOUT="${SETUP_APT_LOCK_TIMEOUT:-60}"
APT_OFFICIAL_REPO_RETRY_DONE=0

load_distro_package_profile() {
  [[ "${__SETUP_PACKAGE_PROFILE_LOADED_FOR:-}" == "$DISTRO_ID" ]] && return 0
  local profile="$SCRIPT_DIR/lib/distros/$DISTRO_ID.sh"
  [[ -f "$profile" ]] || profile="$SCRIPT_DIR/lib/distros/default.sh"
  # Profiles provide distro-specific package lists and call the family
  # defaults for features they do not override.
  # shellcheck source=/dev/null
  source "$profile" || return 1
  __SETUP_PACKAGE_PROFILE_LOADED_FOR="$DISTRO_ID"
  DISTRO_PACKAGE_PROFILE="$profile"
}

package_for() {
  local feature="$1"
  load_distro_package_profile || return 1
  distro_package_for "$feature"
}
package_get_version() { case "$PKG_MANAGER" in apt) dpkg-query -W -f='${Version}' "$1" 2>/dev/null;; pacman) pacman -Q "$1" 2>/dev/null | awk '{print $2}';; esac; }
package_expected_command() {
  case "$1" in
    sway|swaybg|swayidle|swaylock|gtklock|keepassxc|i3blocks|wofi|foot|dex|gammastep|flameshot|grim|slurp|pipewire|pipewire-pulse|wireplumber|pamixer|cliphist|rfkill|brightnessctl|dunst|jq|curl|timeshift|seahorse|age|cryptsetup|git|python3|pkg-config|rustscan|caido) printf '%s\n' "$1" ;;
    neovim) printf '%s\n' nvim ;;
    cmake) printf '%s\n' cmake ;;
    pulseaudio-utils|libpulse) printf '%s\n' pactl ;;
    mate-polkit) printf '%s\n' /usr/libexec/polkit-mate-authentication-agent-1 ;;
    polkit-gnome) printf '%s\n' /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ;;
    wl-clipboard) echo wl-copy;; network-manager|networkmanager) echo nmcli;; network-manager-gnome|network-manager-applet) echo nm-applet;;
    # bluetoothd moved from /usr/lib/bluetooth to /usr/libexec/bluetooth on
    # Ubuntu 24.04. Verify the daemon through its supported command name so
    # this remains valid across both layouts.
    bluez) printf '%s\n' bluetoothd;; bluez-utils) echo bluetoothctl;; blueman) echo blueman-manager;; libnotify-bin|libnotify) echo notify-send;; fontconfig) echo fc-cache;;
    gnome-keyring) echo gnome-keyring-daemon;; grub-customizer) echo grub-customizer;; libsecret-tools) echo secret-tool;; gnupg) echo gpg;; apparmor) echo aa-status;; bubblewrap) echo bwrap;;
    proton-vpn-gnome-desktop|proton-vpn-gtk-app) printf '%s\n' protonvpn-app ;;
  esac
}
# Installer sessions often run with a desktop user's PATH, which omits the
# administrative sbin directories. Resolve installed system tools there too.
package_command_path() {
  local command_name="$1" directory candidate
  local search_dirs="${PACKAGE_SYSTEM_COMMAND_DIRS:-/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin:/usr/libexec:/usr/libexec/bluetooth:/usr/lib/bluetooth}"
  if [[ "$command_name" == /* ]]; then
    [[ -x "$command_name" ]] && { printf '%s\n' "$command_name"; return 0; }
    return 1
  fi
  candidate="$(command -v -- "$command_name" 2>/dev/null)" && { printf '%s\n' "$candidate"; return 0; }
  local IFS=:
  for directory in $search_dirs; do
    [[ -x "$directory/$command_name" && ! -d "$directory/$command_name" ]] || continue
    printf '%s\n' "$directory/$command_name"
    return 0
  done
  return 1
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
  if [[ -n "$expected_command" ]] && ! package_command_path "$expected_command" >/dev/null; then
    PACKAGE_VERIFY_REASON="database is installed but expected executable is absent: $expected_command"; record_verification "$package" FAILED "$PACKAGE_VERIFY_REASON"; return 1
  fi
  PACKAGE_VERIFY_REASON="version=$version${expected_command:+ command=$expected_command}"; record_verification "$package" OK "$PACKAGE_VERIFY_REASON"
}
package_available() { case "$PKG_MANAGER" in apt) apt-cache show "$1" >/dev/null 2>&1;; pacman) pacman -Si "$1" >/dev/null 2>&1;; esac; }
package_done() { local version; version="$(package_get_version "$1")"; ok_indented "verified: $1${version:+ ($version)}"; }
package_name_valid() { [[ "$1" =~ ^[[:alnum:]][[:alnum:]+.-]*$ ]]; }
package_name_approved() {
  local package="$1" feature candidate
  case "$package" in
    adw-gtk3|adw-gtk3-kali|autotiling|brightnessctl|curl|grub-customizer|gtklock|jq|keepassxc|snap|software-properties-common|sudo) return 0;;
  esac
  for feature in core network secret portal audio clipboard bluetooth python notify protonvpn; do
    for candidate in $(package_for "$feature"); do
      [[ "$package" == "$candidate" ]] && return 0
    done
  done
  return 1
}
run_package_command() {
  local label="$1"; shift
  local pid rc spin='|/-\\' spin_index=0
  local -a priority=() runner=()
  # Keep package metadata, extraction, and boot-config generation from
  # monopolizing a desktop session. Both utilities are optional; package
  # behavior is unchanged when a platform does not provide one.
  command -v nice >/dev/null 2>&1 && priority+=(nice -n 10)
  command -v ionice >/dev/null 2>&1 && priority+=(ionice -c 2 -n 7)
  _setup_log_write COMMAND "$label: $(printf '%q ' "$@")"
  if [[ "${1:-}" == run_as_root ]]; then
    shift
    runner=(run_as_root "${priority[@]}" "$@")
  else
    runner=("${priority[@]}" "$@")
  fi
  "${runner[@]}" >>"$SETUP_LOG_FILE" 2>&1 &
  pid=$!
  SETUP_ACTIVE_PID="$pid"
  printf '%s\n' "$pid" >"$SETUP_ACTIVE_PID_FILE"
  while kill -0 "$pid" 2>/dev/null; do
    if [[ -t 1 ]]; then
      printf '\r%s[WORK]%s %s %s elapsed %s' "$SETUP_COLOR_INFO" "$SETUP_COLOR_RST" "${spin:spin_index++%4:1}" "$label" "$(elapsed_time)"
    fi
    sleep 0.5
  done
  wait "$pid"
  rc=$?
  SETUP_ACTIVE_PID=''
  rm -f -- "$SETUP_ACTIVE_PID_FILE"
  [[ -t 1 ]] && printf '\r\033[2K'
  _setup_log_write COMMAND "$label: exit=$rc"
  return "$rc"
}
repair_apt() { info 'Repairing interrupted APT/dpkg state before one retry.'; run_package_command 'dpkg configure' run_as_root timeout --foreground 5m dpkg --configure -a && run_package_command 'apt dependency repair' run_as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 10m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -f install -y; }
refresh_package_metadata() {
  # APT metadata is refreshed once before availability decisions.  Pacman is
  # intentionally not given a standalone -Sy: that can create a partial upgrade.
  [[ "$PKG_MANAGER" != apt ]] || repair_debian_trixie_security_source || return 1
  [[ "$PKG_MANAGER" != apt ]] && return 0
  if run_package_command 'apt metadata refresh' run_as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 10m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -o Acquire::Retries=2 update; then
    return 0
  fi
  info 'APT metadata refresh failed; checking this distribution’s official repositories and retrying once.'
  ensure_official_apt_repositories || return 1
  run_package_command 'APT metadata refresh retry' run_as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 10m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -o Acquire::Retries=2 update
}
backup_apt_source_once() {
  local apt_dir="$1" file="$2" relative backup
  relative="${file#"$apt_dir"/}"
  backup="$SETUP_BACKUP_DIR/apt-sources/$relative"
  run_as_root install -d -m 700 "$(dirname -- "$backup")" || return 1
  run_as_root test -e "$backup" || run_as_root cp -a -- "$file" "$backup"
}
apt_source_matches() {
  local apt_dir="${STARTUP_APT_SOURCE_DIR:-/etc/apt}" pattern file
  pattern="$1"
  local -a source_files=()
  [[ -f "$apt_dir/sources.list" ]] && source_files+=("$apt_dir/sources.list")
  shopt -s nullglob
  source_files+=("$apt_dir"/sources.list.d/*.list "$apt_dir"/sources.list.d/*.sources)
  shopt -u nullglob
  ((${#source_files[@]})) || return 1
  for file in "${source_files[@]}"; do
    grep -Eiq "^[[:space:]]*(deb([[:space:]]+\\[[^]]*\\])?[[:space:]]+|URIs:[[:space:]]*)${pattern}" "$file" && return 0
  done
  return 1
}
ensure_official_apt_repositories() {
  local apt_dir="${STARTUP_APT_SOURCE_DIR:-/etc/apt}"
  local keyring_dir="${STARTUP_KEYRING_DIR:-/usr/share/keyrings}"
  local codename base_codename mint_codename target temp contents='' changed=0
  target="$apt_dir/sources.list.d/neo-startup-official.sources"
  OFFICIAL_REPOSITORY_CHANGED=0
  [[ "$PKG_MANAGER" == apt ]] || return 0

  case "$DISTRO_ID" in
    debian)
      codename="${VERSION_CODENAME:-}"
      [[ "$codename" =~ ^[a-z][a-z0-9-]*$ ]] || { warn 'Cannot add Debian repositories: VERSION_CODENAME is missing or invalid.'; return 1; }
      [[ -r "$keyring_dir/debian-archive-keyring.gpg" ]] || { warn 'Cannot add Debian repositories: the Debian archive keyring is missing.'; return 1; }
      if ! apt_source_matches 'https?://([a-z0-9-]+\.)*debian\.org/debian/?([[:space:]]|$)'; then
        contents+="Types: deb\nURIs: https://deb.debian.org/debian\nSuites: $codename $codename-updates\nComponents: main contrib non-free non-free-firmware\nSigned-By: $keyring_dir/debian-archive-keyring.gpg\n\n"
        changed=1
      fi
      if ! apt_source_matches 'https?://security\.debian\.org/debian-security/?([[:space:]]|$)'; then
        contents+="Types: deb\nURIs: https://security.debian.org/debian-security\nSuites: $codename-security\nComponents: main contrib non-free non-free-firmware\nSigned-By: $keyring_dir/debian-archive-keyring.gpg\n\n"
        changed=1
      fi
      ;;
    kali)
      [[ -r "$keyring_dir/kali-archive-keyring.gpg" ]] || { warn 'Cannot add Kali repositories: the Kali archive keyring is missing.'; return 1; }
      if ! apt_source_matches 'https?://http\.kali\.org/kali/?([[:space:]]|$)'; then
        contents+=$'Types: deb\nURIs: http://http.kali.org/kali/\nSuites: kali-rolling\nComponents: main contrib non-free non-free-firmware\nSigned-By: '"$keyring_dir"$'/kali-archive-keyring.gpg\n\n'
        changed=1
      fi
      ;;
    ubuntu)
      codename="${VERSION_CODENAME:-}"
      [[ "$codename" =~ ^[a-z][a-z0-9-]*$ ]] || { warn 'Cannot add Ubuntu repositories: VERSION_CODENAME is missing or invalid.'; return 1; }
      [[ -r "$keyring_dir/ubuntu-archive-keyring.gpg" ]] || { warn 'Cannot add Ubuntu repositories: the Ubuntu archive keyring is missing.'; return 1; }
      if ! apt_source_matches 'https?://([a-z0-9-]+\.)?archive\.ubuntu\.com/ubuntu/?([[:space:]]|$)'; then
        contents+="Types: deb\nURIs: https://archive.ubuntu.com/ubuntu\nSuites: $codename $codename-updates $codename-backports\nComponents: main restricted universe multiverse\nSigned-By: $keyring_dir/ubuntu-archive-keyring.gpg\n\n"
        changed=1
      fi
      if ! apt_source_matches 'https?://security\.ubuntu\.com/ubuntu/?([[:space:]]|$)'; then
        contents+="Types: deb\nURIs: https://security.ubuntu.com/ubuntu\nSuites: $codename-security\nComponents: main restricted universe multiverse\nSigned-By: $keyring_dir/ubuntu-archive-keyring.gpg\n\n"
        changed=1
      fi
      ;;
    linuxmint)
      mint_codename="${VERSION_CODENAME:-}"
      base_codename="${UBUNTU_CODENAME:-}"
      [[ "$mint_codename" =~ ^[a-z][a-z0-9-]*$ && "$base_codename" =~ ^[a-z][a-z0-9-]*$ ]] || {
        warn 'Cannot add Linux Mint repositories: Mint and Ubuntu base codenames must both be available.'; return 1;
      }
      [[ -r "$keyring_dir/linuxmint-keyring.gpg" && -r "$keyring_dir/ubuntu-archive-keyring.gpg" ]] || {
        warn 'Cannot add Linux Mint repositories: the Mint or Ubuntu archive keyring is missing.'; return 1;
      }
      if ! apt_source_matches 'https?://packages\.linuxmint\.com/?([[:space:]]|$)'; then
        contents+="Types: deb\nURIs: http://packages.linuxmint.com\nSuites: $mint_codename\nComponents: main upstream import backport\nSigned-By: $keyring_dir/linuxmint-keyring.gpg\n\n"
        changed=1
      fi
      if ! apt_source_matches 'https?://([a-z0-9-]+\.)?archive\.ubuntu\.com/ubuntu/?([[:space:]]|$)'; then
        contents+="Types: deb\nURIs: https://archive.ubuntu.com/ubuntu\nSuites: $base_codename $base_codename-updates $base_codename-backports\nComponents: main restricted universe multiverse\nSigned-By: $keyring_dir/ubuntu-archive-keyring.gpg\n\n"
        changed=1
      fi
      if ! apt_source_matches 'https?://security\.ubuntu\.com/ubuntu/?([[:space:]]|$)'; then
        contents+="Types: deb\nURIs: https://security.ubuntu.com/ubuntu\nSuites: $base_codename-security\nComponents: main restricted universe multiverse\nSigned-By: $keyring_dir/ubuntu-archive-keyring.gpg\n\n"
        changed=1
      fi
      ;;
    *)
      warn "No automatic APT repository template is defined for $DISTRO_ID; preserving its existing repository configuration."
      return 1
      ;;
  esac

  (( changed == 1 )) || { info "Official $DISTRO_PRETTY repositories are already configured; leaving repository files unchanged."; return 0; }
  if [[ -e "$target" ]]; then
    warn "Cannot add missing official repositories because $target already exists; preserving that file."
    return 1
  fi
  temp="$(mktemp "${TMPDIR:-/tmp}/neo-startup-apt-sources.XXXXXX")" || return 1
  printf '%b' "$contents" >"$temp" || { rm -f -- "$temp"; return 1; }
  if ! run_as_root install -d -m 755 "$apt_dir/sources.list.d" ||
      ! run_as_root install -D -m 644 -- "$temp" "$target"; then
    rm -f -- "$temp"
    required_failure "Could not add official $DISTRO_PRETTY repositories at $target."
    return 1
  fi
  rm -f -- "$temp"
  OFFICIAL_REPOSITORY_CHANGED=1
  info "Added missing official $DISTRO_PRETTY repositories in $target; unrelated sources were preserved."
}
backup_repository_file_once() {
  local file="$1" relative backup
  [[ -e "$file" ]] || return 0
  relative="${file#/}"
  backup="$SETUP_BACKUP_DIR/package-sources/$relative"
  run_as_root install -d -m 700 "$(dirname -- "$backup")" || return 1
  run_as_root test -e "$backup" || run_as_root cp -a -- "$file" "$backup"
}
pacman_repo_has_active_source() {
  local repo="$1" pacman_conf="${STARTUP_PACMAN_CONF:-/etc/pacman.conf}"
  [[ -f "$pacman_conf" ]] || return 1
  awk -v repo="$repo" '
    /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
      section=$0
      gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", section)
      next
    }
    section == repo && $0 !~ /^[[:space:]]*#/ && $0 ~ /^[[:space:]]*(Include|Server)[[:space:]]*=/ { found=1 }
    END { exit found ? 0 : 1 }
  ' "$pacman_conf"
}
ensure_official_pacman_repositories() {
  local pacman_conf="${STARTUP_PACMAN_CONF:-/etc/pacman.conf}"
  local mirrorlist="${STARTUP_PACMAN_MIRRORLIST:-/etc/pacman.d/mirrorlist}"
  local temp changed=0 append_conf='' add_core_include=0 add_extra_include=0
  OFFICIAL_REPOSITORY_CHANGED=0
  [[ "$PKG_MANAGER" == pacman && "$DISTRO_FAMILY" == arch ]] || return 0

  if [[ ! -f "$pacman_conf" ]]; then
    append_conf+=$'\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n'
    changed=1
  else
    if ! grep -Eq '^[[:space:]]*\[core\][[:space:]]*$' "$pacman_conf"; then
      append_conf+=$'\n[core]\nInclude = /etc/pacman.d/mirrorlist\n'
      changed=1
    elif ! pacman_repo_has_active_source core; then
      add_core_include=1
      changed=1
    fi
    if ! grep -Eq '^[[:space:]]*\[extra\][[:space:]]*$' "$pacman_conf"; then
      append_conf+=$'\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n'
      changed=1
    elif ! pacman_repo_has_active_source extra; then
      add_extra_include=1
      changed=1
    fi
  fi
  if [[ ! -f "$mirrorlist" ]] || ! grep -Eq '^[[:space:]]*Server[[:space:]]*=' "$mirrorlist"; then
    changed=1
  fi
  (( changed == 1 )) || { info 'Official Arch core and extra repositories already have an active mirror; leaving pacman configuration unchanged.'; return 0; }

  if [[ -e "$pacman_conf" ]]; then
    backup_repository_file_once "$pacman_conf" || { required_failure "Could not back up $pacman_conf before repair."; return 1; }
  fi
  if [[ -e "$mirrorlist" ]]; then
    backup_repository_file_once "$mirrorlist" || { required_failure "Could not back up $mirrorlist before repair."; return 1; }
  fi
  run_as_root install -d -m 755 "$(dirname -- "$pacman_conf")" "$(dirname -- "$mirrorlist")" || return 1
  if (( add_core_include || add_extra_include )); then
    temp="$(mktemp "${TMPDIR:-/tmp}/neo-startup-pacman-sections.XXXXXX")" || return 1
    awk -v add_core="$add_core_include" -v add_extra="$add_extra_include" '
      { print }
      /^[[:space:]]*\[core\][[:space:]]*$/ && add_core { print "Include = /etc/pacman.d/mirrorlist" }
      /^[[:space:]]*\[extra\][[:space:]]*$/ && add_extra { print "Include = /etc/pacman.d/mirrorlist" }
    ' "$pacman_conf" >"$temp" || { rm -f -- "$temp"; return 1; }
    run_as_root install -m 644 -- "$temp" "$pacman_conf" || { rm -f -- "$temp"; return 1; }
    rm -f -- "$temp"
  fi
  if [[ -n "$append_conf" ]]; then
    temp="$(mktemp "${TMPDIR:-/tmp}/neo-startup-pacman-conf.XXXXXX")" || return 1
    printf '%s' "$append_conf" >"$temp" || { rm -f -- "$temp"; return 1; }
    if ! run_as_root sh -c 'cat "$1" >> "$2"' sh "$temp" "$pacman_conf"; then
      rm -f -- "$temp"
      required_failure "Could not add the official core/extra repository sections to $pacman_conf."
      return 1
    fi
    rm -f -- "$temp"
  fi
  if [[ ! -f "$mirrorlist" ]] || ! grep -Eq '^[[:space:]]*Server[[:space:]]*=' "$mirrorlist"; then
    run_as_root sh -c 'printf "%s\\n" "Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" >> "$1"' sh "$mirrorlist" || {
      required_failure "Could not add an official Arch mirror to $mirrorlist."
      return 1
    }
  fi
  OFFICIAL_REPOSITORY_CHANGED=1
  info "Added missing official Arch core/extra repository configuration; existing pacman settings were backed up and preserved."
}
repair_debian_trixie_security_source() {
  # Debian 13's security archive is hosted at security.debian.org/debian-security.
  # Repair only the known-invalid legacy source form that caused APT to fail;
  # Ubuntu, Kali, Arch, deb822 sources, and all other entries remain untouched.
  [[ "$DISTRO_ID" == debian && "${VERSION_CODENAME:-}" == trixie ]] || return 0
  local apt_dir="${STARTUP_APT_SOURCE_DIR:-/etc/apt}" file
  local primary="$apt_dir/sources.list.d/security.list"
  local secondary="$apt_dir/sources.list.d/trixie-main.list"
  local -a candidates=()
  [[ -f "$apt_dir/sources.list" ]] && candidates+=("$apt_dir/sources.list")
  shopt -s nullglob
  candidates+=("$apt_dir"/sources.list.d/*.list)
  shopt -u nullglob
  for file in "${candidates[@]}"; do
    # Match only an active traditional deb line using the bare Debian web host
    # for the trixie-security suite. Never touch comments or valid mirrors.
    grep -Eq '^[[:space:]]*deb([[:space:]]+\[[^]]*\])?[[:space:]]+https?://(www\.)?debian\.org[[:space:]]+trixie-security([[:space:]]|$)' "$file" || continue
    backup_apt_source_once "$apt_dir" "$file" || {
        required_failure "Cannot back up invalid Debian security source: $file"
        return 1
      }
    run_as_root sed -E -i 's#(^[[:space:]]*deb([[:space:]]+\[[^]]*\])?[[:space:]]+https?://)(www\.)?debian\.org([[:space:]]+trixie-security([[:space:]]|$))#\1security.debian.org/debian-security\4#' "$file" || {
      required_failure "Cannot repair Debian trixie-security source: $file (backup: $SETUP_BACKUP_DIR/apt-sources/${file#"$apt_dir"/})"
      return 1
    }
    printf '[INFO] Repaired Debian 13 security repository in %s\n' "$file"
  done

  # A previous repair may leave the same security archive in both of these
  # known Debian 13 list files. Preserve the union of components in the
  # dedicated security.list entry, then remove only the duplicate security
  # line from trixie-main.list. Back up both files before changing either.
  if [[ -f "$primary" && ! -L "$primary" && -f "$secondary" && ! -L "$secondary" ]] &&
      grep -Eq '^[[:space:]]*deb[[:space:]]+https?://security\.debian\.org/debian-security[[:space:]]+trixie-security([[:space:]]|$)' "$primary" &&
      grep -Eq '^[[:space:]]*deb[[:space:]]+https?://security\.debian\.org/debian-security[[:space:]]+trixie-security([[:space:]]|$)' "$secondary"; then
    for file in "$primary" "$secondary"; do
      backup_apt_source_once "$apt_dir" "$file" || {
          required_failure "Cannot back up duplicate Debian security source: $file"
          return 1
        }
    done
    run_as_root sed -E -i \
      -e '/^[[:space:]]*deb[[:space:]]+https?:\/\/security\.debian\.org\/debian-security[[:space:]]+trixie-security([[:space:]]|$)/ { /[[:space:]]contrib([[:space:]]|$)/! s/$/ contrib/; /[[:space:]]non-free([[:space:]]|$)/! s/$/ non-free/; /[[:space:]]non-free-firmware([[:space:]]|$)/! s/$/ non-free-firmware/; }' \
      "$primary" || {
        required_failure "Cannot preserve Debian security repository components in $primary"
        return 1
      }
    run_as_root sed -E -i \
      '/^[[:space:]]*deb[[:space:]]+https?:\/\/security\.debian\.org\/debian-security[[:space:]]+trixie-security([[:space:]]|$)/d' \
      "$secondary" || {
        required_failure "Cannot remove duplicate Debian security source from $secondary"
        return 1
      }
    printf '[INFO] Consolidated duplicate Debian 13 security entries; backup: %s/apt-sources/sources.list.d\n' "$SETUP_BACKUP_DIR"
  fi
  return 0
}
package_install_batch() {
  local package kali_package_failure=0
  (( $# )) || return 0
  for package in "$@"; do
    if ! package_name_valid "$package" || ! package_name_approved "$package"; then
      required_failure "Refusing unapproved package name: $package"
      return 1
    fi
  done
  for package in "$@"; do
    printf '%s[ ~~ ]%s %s: installing ...\n' "$SETUP_COLOR_INFO" "$SETUP_COLOR_RST" "$package"
    _setup_log_write INSTALL "package=$package requested-manager=$PKG_MANAGER"
    case "$PKG_MANAGER" in
      apt)
        if ! run_package_command "apt install $package" run_as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 30m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$package"; then
          if (( APT_OFFICIAL_REPO_RETRY_DONE == 0 )); then
            APT_OFFICIAL_REPO_RETRY_DONE=1
            info "APT could not install $package; checking official repositories before one retry."
            if ! ensure_official_apt_repositories || ! refresh_package_metadata ||
                ! run_package_command "APT install retry $package" run_as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 30m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$package"; then
              if [[ "$DISTRO_ID" == kali ]]; then
                warn "Kali package $package still failed after its repository retry; continuing with the remaining packages."
                kali_package_failure=1
                continue
              fi
              return 1
            fi
          else
            if [[ "$DISTRO_ID" == kali ]]; then
              warn "Kali package $package failed; continuing with the remaining packages."
              kali_package_failure=1
              continue
            fi
            return 1
          fi
        fi
        ;;
      pacman)
        if ! run_package_command "pacman install $package" run_as_root timeout --foreground 30m pacman -S --needed --noconfirm "$package"; then
          ensure_official_pacman_repositories || return 1
          info "Arch package installation failed; retrying with pacman -Syu, which performs the full system upgrade required for a safe repository refresh."
          run_package_command "pacman full sync and install $package" run_as_root timeout --foreground 60m pacman -Syu --needed --noconfirm "$package" || return 1
        fi
        ;;
      *) return 1;;
    esac || return 1
    printf '%s[ OK ]%s %s: installed\n' "$SETUP_COLOR_OK" "$SETUP_COLOR_RST" "$package"
    _setup_log_write OK "package=$package installed"
  done
  (( kali_package_failure == 0 ))
}
install_packages() {
  local p
  local -A seen=()
  local -a todo=()
  for p in "$@"; do
    if ! package_name_valid "$p" || ! package_name_approved "$p"; then
      required_failure "Refusing unapproved package name: $p"
      return 1
    fi
    [[ -z "${seen[$p]:-}" ]] || continue
    seen[$p]=1
    package_verify "$p" || todo+=("$p")
  done
  (( ${#todo[@]} == 0 )) || package_install_batch "${todo[@]}"
}
install_package() { install_packages "$1"; }
remove_packages() { (( $# )) || return 0; case "$PKG_MANAGER" in apt) run_package_command 'apt batch remove' run_as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 20m apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" remove -y "$@";; pacman) run_package_command 'pacman batch remove' run_as_root timeout --foreground 20m pacman -Rns --noconfirm "$@";; esac; }
collect_required_packages() { local feature pkg list; local -A seen=(); REQUIRED_PACKAGES=(); for feature in core network secret portal audio clipboard bluetooth python notify; do list="$(package_for "$feature")" || { required_failure "No package mapping for required feature: $feature"; continue; }; for pkg in $list; do [[ -n "${seen[$pkg]:-}" ]] && continue; seen[$pkg]=1; REQUIRED_PACKAGES+=("$pkg"); done; done; }
install_feature() { local list; list="$(package_for "$1")" || return 1; local -a p=(); read -r -a p <<<"$list"; install_packages "${p[@]}"; }
backup_package_selections() { case "$PKG_MANAGER" in apt) run_as_root sh -c 'dpkg --get-selections > "$1"' sh "$SETUP_BACKUP_DIR/dpkg-selections.txt" || warn 'Could not back up dpkg selections';; pacman) run_as_root sh -c 'pacman -Qqe > "$1"' sh "$SETUP_BACKUP_DIR/pacman-explicit.txt" || warn 'Could not back up pacman selections';; esac; }
ensure_ubuntu_keepassxc_ppa() {
  [[ "$DISTRO_ID" == ubuntu ]] || return 0
  if grep -Rqs 'phoerious/keepassxc' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    return 0
  fi
  if ! command -v add-apt-repository >/dev/null 2>&1; then
    package_install_batch software-properties-common || {
      required_failure 'Cannot install software-properties-common to configure the KeePassXC Ubuntu PPA.'
      return 1
    }
  fi
  run_package_command 'add KeePassXC Ubuntu PPA' run_as_root timeout --foreground 5m add-apt-repository -y ppa:phoerious/keepassxc || {
    required_failure 'Could not add ppa:phoerious/keepassxc on Ubuntu.'
    return 1
  }
  refresh_package_metadata || {
    required_failure 'APT metadata refresh failed after adding the KeePassXC PPA.'
    return 1
  }
}
keepassxc_snap_installed() {
  local snap_list
  command -v snap >/dev/null 2>&1 || return 1
  snap_list="$(run_as_root snap list keepassxc 2>/dev/null || true)"
  [[ -n "$snap_list" ]] || return 1
  [[ -x /snap/bin/keepassxc ]] || command -v keepassxc >/dev/null 2>&1
}
install_keepassxc() {
  local package snap_list
  package="$(package_for keepassxc)" || { required_failure "No KeePassXC package mapping for $DISTRO_FAMILY."; return 1; }
  if keepassxc_snap_installed; then
    ok_indented 'KeePassXC snap is already installed and its launcher is available.'
    return 0
  fi
  if package_installed "$package"; then
    package_verify "$package" && return 0
  fi
  if package_available "$package"; then
    install_package "$package" || { required_failure 'KeePassXC package installation failed.'; return 1; }
    package_verify "$package" || { required_failure "KeePassXC verification failed: $PACKAGE_VERIFY_REASON"; return 1; }
    ok_indented "KeePassXC installed and verified from $PKG_MANAGER repositories."
    return 0
  fi
  if command -v snap >/dev/null 2>&1; then
    snap_list="$(run_as_root snap list keepassxc 2>/dev/null || true)"
    if [[ -n "$snap_list" ]]; then
      required_failure 'KeePassXC snap is installed but its launcher is unavailable.'
      return 1
    fi
    info 'Native KeePassXC package is unavailable; installing the official Snap package.'
    run_package_command 'snap install keepassxc' run_as_root timeout --foreground 20m snap install keepassxc || {
      required_failure 'KeePassXC Snap installation failed.'
      return 1
    }
    keepassxc_snap_installed || { required_failure 'KeePassXC snap installation could not be verified or its launcher is unavailable.'; return 1; }
    ok_indented 'KeePassXC snap installed and verified.'
    return 0
  fi
  required_failure 'KeePassXC is unavailable from native repositories and Snap is not installed.'
  return 1
}
install_optional_grub_customizer() {
  # GRUB theme deployment uses grub-mkconfig/update-grub directly. The GUI
  # customizer is a convenience package and is absent from some supported
  # Ubuntu-derived repositories (including some Linux Mint configurations).
  if package_installed grub-customizer; then
    if package_verify grub-customizer; then package_done grub-customizer; else warn "Optional grub-customizer is installed but failed verification: $PACKAGE_VERIFY_REASON"; fi
    return 0
  fi
  if ! package_available grub-customizer; then
    info 'Optional grub-customizer is unavailable from the configured repositories; skipping it.'
    return 0
  fi
  if package_install_batch grub-customizer && package_verify grub-customizer; then
    package_done grub-customizer
  else
    warn 'Optional grub-customizer could not be installed or verified; GRUB theme setup does not depend on it.'
  fi
  return 0
}

protonvpn_dns_available() {
  command -v getent >/dev/null 2>&1 && getent ahosts repo.protonvpn.com >/dev/null 2>&1
}

protonvpn_installed() {
  local package
  package="$(package_for protonvpn)" || return 1
  package_installed "$package" || return 1
  package_verify "$package"
}

install_protonvpn_apt() {
  local package="$1" attempt temp_dir deb_file release_package_added=0
  local release_version='1.0.10' release_sha256='c8a9fffb4ebdd63db08ce7f11c9b0ac394064ae6a210feb9ab63a0f7d8d060a7'
  local release_url="https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_${release_version}_all.deb"

  if package_installed protonvpn-stable-release; then
    : # Preserve an existing repository configuration.
  elif apt_source_matches 'https?://repo\.protonvpn\.com/debian/?([[:space:]]|$)'; then
    : # The official Proton source is already configured.
  else
    if ! command -v curl >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1; then
      warn 'Proton VPN skipped: curl and sha256sum are required to securely configure its official APT repository.'
      return 1
    fi

    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/neo-protonvpn.XXXXXX")" || {
      warn 'Proton VPN skipped: could not create a temporary download directory.'
      return 1
    }
    deb_file="$temp_dir/protonvpn-stable-release_${release_version}_all.deb"
    for attempt in 1 2 3; do
      rm -f -- "$deb_file"
      if protonvpn_dns_available &&
          curl --fail --location --silent --show-error --connect-timeout 8 --max-time 30 \
            --output "$deb_file" "$release_url"; then
        break
      fi
      if (( attempt < 3 )); then
        info "Proton VPN repository host lookup/download failed; retrying ($attempt/3)."
        sleep "${PROTONVPN_RETRY_DELAY:-2}"
      fi
    done
    if [[ ! -s "$deb_file" ]]; then
      rm -rf -- "$temp_dir"
      warn 'Proton VPN was not installed: repo.protonvpn.com could not be resolved or reached after 3 attempts. Check the system DNS/network and rerun the installer; DNS settings were left unchanged.'
      return 1
    fi
    if ! printf '%s  %s\n' "$release_sha256" "$deb_file" | sha256sum --check --status; then
      rm -rf -- "$temp_dir"
      warn 'Proton VPN was not installed: the official repository package checksum did not match.'
      return 1
    fi
    if ! run_package_command 'install Proton VPN official APT repository package' \
        run_as_root dpkg -i "$deb_file"; then
      rm -rf -- "$temp_dir"
      warn 'Proton VPN was not installed: its official APT repository package could not be installed.'
      return 1
    fi
    release_package_added=1
    rm -rf -- "$temp_dir"
  fi

  if ! run_package_command 'refresh Proton VPN APT repository' run_as_root env \
      DEBIAN_FRONTEND=noninteractive timeout --foreground 5m \
      apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" -o Acquire::Retries=2 update; then
    if (( release_package_added == 1 )); then
      run_package_command 'remove newly added Proton VPN repository after refresh failure' \
        run_as_root dpkg --purge protonvpn-stable-release || true
    fi
    warn 'Proton VPN was not installed: APT could not refresh the Proton repository. Any repository package added in this attempt was rolled back; system DNS was not changed.'
    return 1
  fi
  if ! run_package_command 'install Proton VPN application' run_as_root env \
      DEBIAN_FRONTEND=noninteractive timeout --foreground 30m \
      apt-get -o "DPkg::Lock::Timeout=$SETUP_APT_LOCK_TIMEOUT" \
      -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$package" ||
      ! package_verify "$package"; then
    warn 'Proton VPN repository is configured, but the application did not install or verify. Review the setup log and retry when repository access is available.'
    return 1
  fi
  package_done "$package"
  ok_indented 'Proton VPN installed and verified from its official APT repository.'
}

install_protonvpn() {
  local package
  package="$(package_for protonvpn)" || { warn "Proton VPN has no package mapping for $DISTRO_PRETTY; skipping."; return 0; }
  if protonvpn_installed; then
    package_done "$package"
    info 'Proton VPN is already installed and its launcher is available; skipping installation.'
    return 0
  fi
  if package_installed "$package"; then
    warn "Proton VPN is present but failed verification: $PACKAGE_VERIFY_REASON"
    return 1
  fi

  info "Installing Proton VPN using the $PKG_MANAGER package path for $DISTRO_PRETTY."
  case "$PKG_MANAGER" in
    apt)
      install_protonvpn_apt "$package" || return 1
      ;;
    pacman)
      # Arch ships the Proton GUI package in its official Extra repository.
      # Keep this optional install from triggering an unexpected full upgrade.
      if ! run_package_command 'install Proton VPN from Arch Extra' \
          run_as_root timeout --foreground 30m pacman -S --needed --noconfirm "$package" ||
          ! package_verify "$package"; then
        warn 'Proton VPN was not installed from the Arch repositories; no unrelated system upgrade was started.'
        return 1
      fi
      package_done "$package"
      ok_indented 'Proton VPN installed and verified from Arch Extra.'
      ;;
    *)
      warn "Proton VPN is not configured for package manager $PKG_MANAGER; skipping."
      return 1
      ;;
  esac
}

run_packages() {
  local pkg unavailable=0
  cleanup_previous_package_process
  APT_OFFICIAL_REPO_RETRY_DONE=0
  run_as_root install -d -m 700 "$SETUP_BACKUP_DIR" || { required_failure "Cannot create backup directory: $SETUP_BACKUP_DIR"; return 1; }
  backup_package_selections
  refresh_package_metadata || { required_failure 'APT metadata refresh failed; package availability cannot be trusted'; return 1; }
  ensure_ubuntu_keepassxc_ppa || return 1
  collect_required_packages
  MISSING_PACKAGES=() INVALID_PACKAGES=() FAILED_REQUIRED_PACKAGES=()
  if [[ "$PKG_MANAGER" == apt ]]; then
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
      package_installed "$pkg" || package_available "$pkg" || { unavailable=1; break; }
    done
    if (( unavailable )); then
      info 'Some required packages are absent from the configured APT indexes; ensuring this OS official repositories are configured.'
      if ensure_official_apt_repositories && (( OFFICIAL_REPOSITORY_CHANGED )); then
        refresh_package_metadata || { required_failure 'APT metadata refresh failed after adding official repositories'; return 1; }
      fi
    fi
  elif [[ "$PKG_MANAGER" == pacman ]]; then
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
      package_installed "$pkg" || package_available "$pkg" || { unavailable=1; break; }
    done
    if (( unavailable )); then
      ensure_official_pacman_repositories || { required_failure 'Could not verify official Arch repositories'; return 1; }
      info 'Refreshing Arch repositories with pacman -Syu because required packages are missing from the current package indexes.'
      run_package_command 'pacman full system sync and upgrade' run_as_root timeout --foreground 60m pacman -Syu --noconfirm || {
        required_failure 'Arch pacman -Syu failed while refreshing the official repositories.'
        return 1
      }
    fi
  fi
  for pkg in "${REQUIRED_PACKAGES[@]}"; do if package_verify "$pkg"; then package_done "$pkg"; elif package_available "$pkg"; then MISSING_PACKAGES+=("$pkg"); [[ "$PACKAGE_VERIFY_REASON" != 'package database does not report installed' ]] && INVALID_PACKAGES+=("$pkg"); else FAILED_REQUIRED_PACKAGES+=("$pkg"); required_failure "Required package unavailable in configured repositories: $pkg"; fi; done
  if (( ${#MISSING_PACKAGES[@]} )); then
    info "Installing ${#MISSING_PACKAGES[@]} missing/invalid package(s) sequentially with $PKG_MANAGER."
    if ! package_install_batch "${MISSING_PACKAGES[@]}" && [[ "$PKG_MANAGER" == apt ]]; then
      if repair_apt; then package_install_batch "${MISSING_PACKAGES[@]}" || _setup_log_write ERROR 'APT retry failed'; else _setup_log_write ERROR 'APT repair failed'; fi
    fi
  fi
  for pkg in "${REQUIRED_PACKAGES[@]}"; do if package_verify "$pkg"; then package_done "$pkg"; else FAILED_REQUIRED_PACKAGES+=("$pkg"); required_failure "Required package verification failed: $pkg ($PACKAGE_VERIFY_REASON)"; fi; done
  (( ${#FAILED_REQUIRED_PACKAGES[@]} == 0 )) || return 1
  install_keepassxc || return 1
  install_optional_grub_customizer
  install_protonvpn || true
  ok_indented "All required packages independently verified. [${#REQUIRED_PACKAGES[@]} components]"
}
