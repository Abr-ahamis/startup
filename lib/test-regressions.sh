#!/usr/bin/env bash
# Focused offline regression tests for installer verification edge cases.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# These are normally initialized by 00-common.sh. The functions under test do
# not use them, but 20-packages.sh initializes its backup path while loading.
SETUP_BASE_DIR=/tmp/startup-regression-test
SETUP_TIMESTAMP=test
source "$SCRIPT_DIR/lib/20-packages.sh"
source "$SCRIPT_DIR/lib/40-grub.sh"
source "$SCRIPT_DIR/lib/50-config-files.sh"
source "$SCRIPT_DIR/lib/80-security.sh"
source "$SCRIPT_DIR/lib/70-services.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

grub_test_tmp="$(mktemp -d)"
trap 'rm -rf -- "$grub_test_tmp"' EXIT
run_as_root() { "$@"; }
mkdir -p "$grub_test_tmp/system-bin"
touch "$grub_test_tmp/system-bin/startup-test-admin-command" "$grub_test_tmp/system-bin/startup-test-grub-command"
chmod +x "$grub_test_tmp/system-bin/"*
PACKAGE_SYSTEM_COMMAND_DIRS="$grub_test_tmp/system-bin"
GRUB_SYSTEM_COMMAND_DIRS="$grub_test_tmp/system-bin"
[[ "$(package_command_path startup-test-admin-command)" == "$grub_test_tmp/system-bin/startup-test-admin-command" ]] || fail 'package command lookup must search standard system command directories'
[[ "$(grub_command_path startup-test-grub-command)" == "$grub_test_tmp/system-bin/startup-test-grub-command" ]] || fail 'GRUB command lookup must search standard system command directories'
unset PACKAGE_SYSTEM_COMMAND_DIRS GRUB_SYSTEM_COMMAND_DIRS
grub_prepare_theme_parent "$grub_test_tmp/boot/grub/themes/startup" || fail 'GRUB theme parent could not be created'
[[ -d "$grub_test_tmp/boot/grub/themes" ]] || fail 'missing GRUB themes parent was not created'

SETUP_RUNTIME_DIR="$grub_test_tmp/runtime"
mkdir -p "$SETUP_RUNTIME_DIR"
foot() {
  local config=''
  while (( $# )); do
    case "$1" in
      --config) config="$2"; shift 2;;
      *) shift;;
    esac
  done
  grep -qxF '[colors-dark]' "$config" && return 1
  grep -qxF '[colors]' "$config"
}
prepare_foot_config_source || fail 'legacy Foot parser was not given a compatible config'
[[ "$FOOT_CONFIG_SOURCE" != "$SCRIPT_DIR/sway/.config/foot" ]] || fail 'legacy Foot config did not use an adapted staging tree'
grep -qxF '[colors]' "$FOOT_CONFIG_SOURCE/foot.ini" || fail 'legacy Foot config section was not adapted'
grep -qxF '[colors-dark]' "$SCRIPT_DIR/sway/.config/foot/foot.ini" || fail 'adapter modified the repository config'
foot() { return 0; }
prepare_foot_config_source || fail 'modern Foot config check failed'
[[ "$FOOT_CONFIG_SOURCE" == "$SCRIPT_DIR/sway/.config/foot" ]] || fail 'modern Foot config was unnecessarily adapted'

[[ "$(package_expected_command bluez)" == bluetoothd ]] || fail 'BlueZ must be verified by bluetoothd, not a distro-specific path'
[[ "$(package_expected_command gtklock)" == gtklock ]] || fail 'GTKlock must be independently verified by its executable'
[[ "$(package_expected_command keepassxc)" == keepassxc ]] || fail 'KeePassXC must be verified by its executable'
[[ "$(package_expected_command cmake)" == cmake ]] || fail 'CMake must be verified on battery monitor builds'
[[ "$(package_expected_command rustscan)" == rustscan ]] || fail 'RustScan must be verified by its executable'
[[ "$(package_expected_command caido)" == caido ]] || fail 'Caido must be verified by its executable'
[[ "$(package_expected_command proton-vpn-gnome-desktop)" == protonvpn-app ]] || fail 'APT Proton VPN package must verify its launcher'
[[ "$(package_expected_command proton-vpn-gtk-app)" == protonvpn-app ]] || fail 'Arch Proton VPN package must verify its launcher'
grep -q 'core) echo .*rustscan caido' "$SCRIPT_DIR/lib/distros/kali.sh" || fail 'Kali package profile must include RustScan and Caido'
if grep -Fq 'include $target_config' "$SCRIPT_DIR/lib/90-report.sh"; then
  fail "nested Sway preview must not run the user's full startup configuration"
fi
grep -Fq 'STARTUP_ENABLE_SWAY_PREVIEW' "$SCRIPT_DIR/lib/90-report.sh" || fail 'nested Sway preview must be opt-in outside an active Sway session'
if rg -ni 'burpsuite|burp suite' "$SCRIPT_DIR/lib/distros"; then
  fail 'Kali distro profiles must not install or configure Burp Suite'
fi
package_name_approved grub-customizer || fail 'optional grub-customizer must remain an approved package'
(
  DISTRO_ID=kali PKG_MANAGER=apt APT_OFFICIAL_REPO_RETRY_DONE=1
  SETUP_COLOR_INFO='' SETUP_COLOR_RST='' SETUP_COLOR_OK=''
  second_package_attempted=0
  package_name_approved() { return 0; }
  run_package_command() {
    case "$1" in
      'apt install unavailable-kali-package') return 1;;
      'apt install later-kali-package') second_package_attempted=1; return 0;;
    esac
  }
  _setup_log_write() { :; }
  warn() { :; }
  if package_install_batch unavailable-kali-package later-kali-package; then
    exit 1
  fi
  [[ "$second_package_attempted" == 1 ]]
) || fail 'a Kali package failure prevented later packages from being attempted'
(
  DISTRO_ID=debian PKG_MANAGER=apt APT_OFFICIAL_REPO_RETRY_DONE=1
  SETUP_COLOR_INFO='' SETUP_COLOR_RST='' SETUP_COLOR_OK=''
  second_package_attempted=0
  package_name_approved() { return 0; }
  run_package_command() {
    case "$1" in
      'apt install unavailable-package') return 1;;
      'apt install later-package') second_package_attempted=1; return 0;;
    esac
  }
  _setup_log_write() { :; }
  if package_install_batch unavailable-package later-package; then
    exit 1
  fi
  [[ "$second_package_attempted" == 0 ]]
) || fail 'Kali-only package continuation changed Debian package behavior'
(
  package_for() { printf '%s\n' proton-vpn-gnome-desktop; }
  package_installed() { [[ "$1" == proton-vpn-gnome-desktop ]]; }
  package_verify() { [[ "$1" == proton-vpn-gnome-desktop && "${PROTONVPN_TEST_VERIFY:-0}" == 1 ]]; }
  PROTONVPN_TEST_VERIFY=1 protonvpn_installed
) || fail 'Proton VPN installed check did not recognize an installed, verified app'
if (
  package_for() { printf '%s\n' proton-vpn-gnome-desktop; }
  package_installed() { [[ "$1" == proton-vpn-gnome-desktop ]]; }
  package_verify() { return 1; }
  protonvpn_installed
); then
  fail 'Proton VPN installed check accepted an unverified app'
fi
info() { :; }
warn() { TEST_WARNING="$*"; }
SETUP_REQUIRED_FAILURES=()
package_installed() { return 1; }
package_available() { return 1; }
install_optional_grub_customizer || fail 'missing optional grub-customizer should not fail package setup'
[[ "${#SETUP_REQUIRED_FAILURES[@]}" == 0 ]] || fail 'missing optional grub-customizer must not create a required package failure'

# A transient Proton DNS failure must be bounded, leave DNS configuration
# alone, and not invoke curl with an unresolved host or fail the installer.
PROTONVPN_RETRY_DELAY=0
STARTUP_APT_SOURCE_DIR="$grub_test_tmp/proton-apts"
mkdir -p "$STARTUP_APT_SOURCE_DIR/sources.list.d"
protonvpn_dns_available() { return 1; }
curl() { fail 'Proton VPN download ran despite failed DNS resolution'; }
if install_protonvpn_apt proton-vpn-gnome-desktop; then
  fail 'Proton VPN setup should report a failed DNS bootstrap to its optional caller'
fi
[[ "$TEST_WARNING" == *'repo.protonvpn.com could not be resolved'* ]] || fail 'Proton VPN DNS failure was not explained'
unset -f protonvpn_dns_available curl
unset PROTONVPN_RETRY_DELAY STARTUP_APT_SOURCE_DIR

# The one known Debian 13 APT source typo is repaired with a backup. Other
# Debian-family distributions and Arch must not have their repository files
# rewritten by that Debian-specific compatibility fix.
apt_fixture="$grub_test_tmp/apt"
mkdir -p "$apt_fixture/sources.list.d"
printf '%s\n' 'deb http://debian.org trixie-security main contrib non-free-firmware' > "$apt_fixture/sources.list.d/trixie.list"
SETUP_BACKUP_DIR="$grub_test_tmp/backups"
STARTUP_APT_SOURCE_DIR="$apt_fixture"
DISTRO_ID=debian VERSION_CODENAME=trixie
repair_debian_trixie_security_source || fail 'Debian 13 invalid security source was not repaired'
grep -qxF 'deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware' "$apt_fixture/sources.list.d/trixie.list" || fail 'Debian security source repair produced an invalid entry'
grep -qxF 'deb http://debian.org trixie-security main contrib non-free-firmware' "$SETUP_BACKUP_DIR/apt-sources/sources.list.d/trixie.list" || fail 'original Debian source was not backed up'
printf '%s\n' 'deb http://debian.org trixie-security main' > "$apt_fixture/sources.list.d/other.list"
DISTRO_ID=ubuntu VERSION_CODENAME=trixie
repair_debian_trixie_security_source || fail 'Ubuntu source check unexpectedly failed'
grep -qxF 'deb http://debian.org trixie-security main' "$apt_fixture/sources.list.d/other.list" || fail 'Debian-only repair modified Ubuntu configuration'
DISTRO_ID=arch
repair_debian_trixie_security_source || fail 'Arch source check unexpectedly failed'
grep -qxF 'deb http://debian.org trixie-security main' "$apt_fixture/sources.list.d/other.list" || fail 'Debian-only repair modified Arch configuration'
unset STARTUP_APT_SOURCE_DIR

# Remove the known duplicate trixie-security line while retaining all package
# components in the dedicated security source and backing up both files.
apt_dupe_fixture="$grub_test_tmp/apt-duplicate"
mkdir -p "$apt_dupe_fixture/sources.list.d"
printf '%s\n' 'deb https://security.debian.org/debian-security trixie-security main' > "$apt_dupe_fixture/sources.list.d/security.list"
printf '%s\n' \
  'deb http://deb.debian.org/debian trixie main contrib non-free-firmware' \
  'deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware' \
  > "$apt_dupe_fixture/sources.list.d/trixie-main.list"
STARTUP_APT_SOURCE_DIR="$apt_dupe_fixture"
SETUP_BACKUP_DIR="$grub_test_tmp/apt-duplicate-backups"
DISTRO_ID=debian VERSION_CODENAME=trixie
repair_debian_trixie_security_source || fail 'duplicate Debian security source repair failed'
grep -qxF 'deb https://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware' "$apt_dupe_fixture/sources.list.d/security.list" || fail 'security source consolidation did not preserve all components'
grep -qxF 'deb http://deb.debian.org/debian trixie main contrib non-free-firmware' "$apt_dupe_fixture/sources.list.d/trixie-main.list" || fail 'security source consolidation changed the Debian main repository'
if grep -q 'trixie-security' "$apt_dupe_fixture/sources.list.d/trixie-main.list"; then
  fail 'duplicate Debian security source was not removed'
fi
[[ -f "$SETUP_BACKUP_DIR/apt-sources/sources.list.d/security.list" && -f "$SETUP_BACKUP_DIR/apt-sources/sources.list.d/trixie-main.list" ]] || fail 'duplicate Debian security sources were not backed up'
unset STARTUP_APT_SOURCE_DIR

# Missing official APT sources are added per detected distribution in a new
# deb822 file. Existing third-party sources stay untouched and repeated runs
# do not duplicate the generated source file.
repo_fixture_root="$grub_test_tmp/official-repositories"
repo_keyring_dir="$repo_fixture_root/keyrings"
mkdir -p "$repo_keyring_dir"
for keyring in debian-archive-keyring.gpg kali-archive-keyring.gpg ubuntu-archive-keyring.gpg linuxmint-keyring.gpg; do
  touch "$repo_keyring_dir/$keyring"
done
for spec in 'debian|trixie|' 'kali||' 'ubuntu|noble|' 'linuxmint|zena|noble'; do
  IFS='|' read -r DISTRO_ID VERSION_CODENAME UBUNTU_CODENAME <<< "$spec"
  apt_fixture="$repo_fixture_root/$DISTRO_ID/etc/apt"
  mkdir -p "$apt_fixture/sources.list.d"
  printf '%s\n' 'deb https://vendor.example/stable main' > "$apt_fixture/sources.list.d/vendor.list"
  STARTUP_APT_SOURCE_DIR="$apt_fixture"
  STARTUP_KEYRING_DIR="$repo_keyring_dir"
  PKG_MANAGER=apt
  DISTRO_PRETTY="$DISTRO_ID"
  ensure_official_apt_repositories || fail "official repository setup failed for $DISTRO_ID"
  [[ "$OFFICIAL_REPOSITORY_CHANGED" == 1 ]] || fail "official repositories were not added for $DISTRO_ID"
  repo_file="$apt_fixture/sources.list.d/neo-startup-official.sources"
  [[ -s "$repo_file" ]] || fail "official repository file was not created for $DISTRO_ID"
  grep -q 'vendor.example' "$apt_fixture/sources.list.d/vendor.list" || fail "third-party source changed for $DISTRO_ID"
  case "$DISTRO_ID" in
    debian) grep -q 'Suites: trixie trixie-updates' "$repo_file" && grep -q 'trixie-security' "$repo_file" || fail 'Debian suite configuration is incorrect';;
    kali) grep -q 'URIs: http://http.kali.org/kali/' "$repo_file" && grep -q 'Suites: kali-rolling' "$repo_file" || fail 'Kali repository configuration is incorrect';;
    ubuntu) grep -q 'Suites: noble noble-updates noble-backports' "$repo_file" && grep -q 'noble-security' "$repo_file" || fail 'Ubuntu suite configuration is incorrect';;
    linuxmint) grep -q 'Suites: zena' "$repo_file" && grep -q 'Suites: noble noble-updates noble-backports' "$repo_file" || fail 'Linux Mint and Ubuntu base repository configuration is incorrect';;
  esac
  ensure_official_apt_repositories || fail "repeat official repository check failed for $DISTRO_ID"
  [[ "$OFFICIAL_REPOSITORY_CHANGED" == 0 ]] || fail "official repositories were duplicated for $DISTRO_ID"
done
unset STARTUP_APT_SOURCE_DIR STARTUP_KEYRING_DIR

# A failed metadata refresh triggers one official-source check and one retry.
refresh_fixture="$repo_fixture_root/refresh-failure/etc/apt"
mkdir -p "$refresh_fixture/sources.list.d"
STARTUP_APT_SOURCE_DIR="$refresh_fixture"
STARTUP_KEYRING_DIR="$repo_keyring_dir"
DISTRO_ID=ubuntu DISTRO_PRETTY=Ubuntu VERSION_CODENAME=noble PKG_MANAGER=apt
refresh_calls=0
run_package_command() {
  local label="$1"
  ((refresh_calls += 1))
  [[ "$label" == 'apt metadata refresh' ]] && return 1
  [[ "$label" == 'APT metadata refresh retry' ]] && return 0
  return 1
}
refresh_package_metadata || fail 'failed APT refresh did not recover after adding official Ubuntu sources'
[[ "$refresh_calls" == 2 && -s "$refresh_fixture/sources.list.d/neo-startup-official.sources" ]] || fail 'APT recovery did not add sources and retry exactly once'
unset STARTUP_APT_SOURCE_DIR STARTUP_KEYRING_DIR
unset -f run_package_command

# Arch recovery fills missing official repositories and the mirror, backs up
# files that it appends to, preserves custom sections, and is idempotent.
pacman_fixture="$repo_fixture_root/arch"
mkdir -p "$pacman_fixture/etc/pacman.d"
printf '%s\n' '[options]' 'Architecture = auto' '' '[custom-repo]' 'Server = https://packages.example/$repo/os/$arch' \
  > "$pacman_fixture/etc/pacman.conf"
printf '%s\n' '# no active mirrors' > "$pacman_fixture/etc/pacman.d/mirrorlist"
STARTUP_PACMAN_CONF="$pacman_fixture/etc/pacman.conf"
STARTUP_PACMAN_MIRRORLIST="$pacman_fixture/etc/pacman.d/mirrorlist"
SETUP_BACKUP_DIR="$pacman_fixture/backups"
DISTRO_ID=arch DISTRO_FAMILY=arch DISTRO_PRETTY='Arch Linux' PKG_MANAGER=pacman
ensure_official_pacman_repositories || fail 'Arch official repository repair failed'
[[ "$OFFICIAL_REPOSITORY_CHANGED" == 1 ]] || fail 'Arch repo repair did not report changes'
grep -qxF '[core]' "$STARTUP_PACMAN_CONF" && grep -qxF '[extra]' "$STARTUP_PACMAN_CONF" || fail 'Arch core/extra repositories were not added'
grep -qxF 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' "$STARTUP_PACMAN_MIRRORLIST" || fail 'official Arch mirror was not added'
grep -q 'packages.example' "$STARTUP_PACMAN_CONF" || fail 'custom pacman repository was changed'
[[ -f "$SETUP_BACKUP_DIR/package-sources/${STARTUP_PACMAN_CONF#/}" && -f "$SETUP_BACKUP_DIR/package-sources/${STARTUP_PACMAN_MIRRORLIST#/}" ]] || fail 'pacman configuration backups were not created'
ensure_official_pacman_repositories || fail 'repeat Arch repository check failed'
[[ "$OFFICIAL_REPOSITORY_CHANGED" == 0 ]] || fail 'Arch repository repair was not idempotent'
malformed_arch="$repo_fixture_root/arch-missing-includes"
mkdir -p "$malformed_arch/etc/pacman.d"
printf '%s\n' '[options]' '[core]' '# Include = /etc/pacman.d/mirrorlist' '[extra]' '# Include = /etc/pacman.d/mirrorlist' \
  > "$malformed_arch/etc/pacman.conf"
printf '%s\n' 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' > "$malformed_arch/etc/pacman.d/mirrorlist"
STARTUP_PACMAN_CONF="$malformed_arch/etc/pacman.conf"
STARTUP_PACMAN_MIRRORLIST="$malformed_arch/etc/pacman.d/mirrorlist"
SETUP_BACKUP_DIR="$malformed_arch/backups"
ensure_official_pacman_repositories || fail 'Arch missing repository includes were not repaired'
[[ "$(grep -c '^Include = /etc/pacman.d/mirrorlist$' "$STARTUP_PACMAN_CONF")" == 2 ]] || fail 'Arch active repository includes were not inserted in existing sections'
unset STARTUP_PACMAN_CONF STARTUP_PACMAN_MIRRORLIST

# Build the Git helper from a private target-user copy, never in the packaged
# documentation directory, then install the artifact through the root helper.
git_helper_source="$grub_test_tmp/git-helper-source"
git_helper_install="$grub_test_tmp/git-helper-install/git-credential-libsecret"
mkdir -p "$git_helper_source"
touch "$git_helper_source/Makefile" "$git_helper_source/git-credential-libsecret.c"
SETUP_RUNTIME_DIR="$grub_test_tmp/git-helper-runtime"
SETUP_LOG_FILE="$grub_test_tmp/git-helper-build.log"
DISTRO_FAMILY=debian PKG_MANAGER=apt
STARTUP_GIT_LIBSECRET_SOURCE_DIR="$git_helper_source"
STARTUP_GIT_LIBSECRET_INSTALL_PATH="$git_helper_install"
package_installed() { return 0; }
run_as_target() {
  if [[ "$1" == timeout ]]; then
    install -m 700 /dev/null "$SETUP_RUNTIME_DIR/git-libsecret-build/git-credential-libsecret"
    return
  fi
  "$@"
}
ok_indented() { :; }
security_build_git_helper || fail 'Git libsecret helper build/install path failed'
[[ -x "$git_helper_install" ]] || fail 'Git libsecret helper was not installed from its private build directory'
[[ ! -e "$git_helper_source/git-credential-libsecret" ]] || fail 'Git helper build polluted the packaged source directory'
unset STARTUP_GIT_LIBSECRET_SOURCE_DIR STARTUP_GIT_LIBSECRET_INSTALL_PATH

theme='/boot/grub/themes/startup/theme.txt'
grub_cfg_theme_matches "$theme" 'set theme=($root)/grub/themes/startup/theme.txt' || fail 'GRUB root-relative /boot theme reference was rejected'
grub_cfg_theme_matches "$theme" "set theme=$theme" || fail 'literal GRUB theme reference was rejected'
grub_cfg_theme_matches "$theme" 'if background_image "/boot/grub/themes/startup/grub-16x9.png"; then' || fail 'literal GRUB background reference was rejected'
grub_cfg_theme_matches "$theme" 'if background_image "($root)/grub/themes/startup/grub-16x9.png"; then' || fail 'GRUB root-relative background reference was rejected'
if grub_cfg_theme_matches "$theme" 'set theme=($root)/grub/themes/other/theme.txt'; then
  fail 'different GRUB theme reference was accepted'
fi
if grub_cfg_theme_matches "$theme" 'set theme=($root)/boot/grub/themes/startup/theme.txt'; then
  fail 'incorrect root-relative GRUB theme reference was accepted'
fi

# Repository resources are stored under sway/.config and deployed into the
# target user's ~/.config. A stale source path makes every configuration copy
# fail after package installation, so keep the layout contract explicit.
for resource in foot i3blocks sway flameshot wofi startup; do
  [[ -d "$SCRIPT_DIR/sway/.config/$resource" ]] || fail "missing managed resource: sway/.config/$resource"
done
if grep -q 'sway/.config/systemd' "$SCRIPT_DIR/lib/50-config-files.sh"; then
  fail 'configuration deployment must not require an empty systemd source directory'
fi
[[ -d "$SCRIPT_DIR/battery-monitor/src" && -f "$SCRIPT_DIR/battery-monitor/CMakeLists.txt" ]] || fail 'C++ battery monitor project is missing its build files'
[[ -x "$SCRIPT_DIR/sway/.local/bin/sway-battery-monitor.sh" ]] || fail 'Sway-only battery monitor launcher is missing or not executable'
[[ ! -e "$SCRIPT_DIR/sway/.config/systemd/user/neo-battery-monitor.service" ]] || fail 'battery monitor must not be enabled as a default user service'
[[ ! -e "$SCRIPT_DIR/sway/.config/systemd/user/battery-monitor.service" ]] || fail 'legacy battery monitor service is still shipped'
[[ ! -e "$SCRIPT_DIR/sway/.local/bin/battery-monitor.sh" ]] || fail 'legacy battery monitor script is still shipped'
grep -q 'build_install_battery_monitor' "$SCRIPT_DIR/lib/50-config-files.sh" || fail 'configuration stage does not build the C++ battery monitor'
grep -q 'sway-battery-monitor.sh' "$SCRIPT_DIR/sway/.local/bin/startup-session.sh" || fail 'Sway session does not start the battery monitor launcher'
grep -q 'SWAYSOCK' "$SCRIPT_DIR/sway/.local/bin/sway-battery-monitor.sh" || fail 'battery monitor launcher is not gated on Sway'
grep -q 'swaymsg -m -t subscribe' "$SCRIPT_DIR/sway/.local/bin/sway-opacity-control.sh" || fail 'opacity watcher must use Sway events rather than periodic tree polling'
grep -q 'apply_opacity_to_container' "$SCRIPT_DIR/sway/.local/bin/sway-opacity-control.sh" || fail 'opacity watcher must update only a newly created window'
grep -q 'coproc SWAY_EVENT_STREAM' "$SCRIPT_DIR/sway/.local/bin/wofi-popup.sh" || fail 'Wofi focus tracking must use an event stream'
if grep -q 'swaymsg -t get_tree' "$SCRIPT_DIR/sway/.local/bin/wofi-popup.sh"; then
  fail 'Wofi focus tracking must not poll the full Sway tree'
fi
grep -q 'i3blocks_public_ip_' "$SCRIPT_DIR/sway/.config/i3blocks/scripts/bar/ip.sh" && grep -q '< 300' "$SCRIPT_DIR/sway/.config/i3blocks/scripts/bar/ip.sh" || fail 'i3blocks public IP request must use a five-minute cache'
[[ -x "$SCRIPT_DIR/sway/.local/bin/refresh-fast-status.sh" && -x "$SCRIPT_DIR/sway/.local/bin/monitor-status-events.sh" ]] || fail 'Sway status refresh helpers must be executable'
grep -q 'sleep 0.7' "$SCRIPT_DIR/sway/.local/bin/refresh-fast-status.sh" && grep -q -- '-RTMIN+12' "$SCRIPT_DIR/sway/.local/bin/refresh-fast-status.sh" || fail 'CPU, RAM, and network speed must refresh every 0.7 seconds'
grep -q 'nmcli monitor' "$SCRIPT_DIR/sway/.local/bin/monitor-status-events.sh" && grep -q 'dbus-monitor --system' "$SCRIPT_DIR/sway/.local/bin/monitor-status-events.sh" && grep -q 'udevadm monitor --kernel --subsystem-match=power_supply' "$SCRIPT_DIR/sway/.local/bin/monitor-status-events.sh" || fail 'network, Bluetooth, and battery blocks must refresh on system events'
grep -q 'for signal in {10..19}' "$SCRIPT_DIR/sway/.local/bin/startup-session.sh" || fail 'Sway session start/reload must refresh all i3blocks status signals'
for block in network_speed cpu ram ip interface wifi_adapter_1 wifi_adapter_2 bluetooth battery; do
  grep -A7 "^\[$block\]$" "$SCRIPT_DIR/sway/.config/i3blocks/config" | grep -qx 'interval=once' || fail "$block must wait for its configured event or signal"
done

# Legacy files are backed up and removed without touching the new service.
migration_home="$grub_test_tmp/migration-home"
TARGET_HOME="$migration_home"
SETUP_BACKUP_DIR="$grub_test_tmp/migration-backups"
mkdir -p "$TARGET_HOME/.config/systemd/user/default.target.wants" "$TARGET_HOME/.local/bin"
printf '%s\n' 'legacy unit' > "$TARGET_HOME/.config/systemd/user/battery-monitor.service"
printf '%s\n' 'legacy script' > "$TARGET_HOME/.local/bin/battery-monitor.sh"
printf '%s\n' 'new service' > "$TARGET_HOME/.config/systemd/user/neo-battery-monitor.service"
ln -s "$TARGET_HOME/.config/systemd/user/battery-monitor.service" \
  "$TARGET_HOME/.config/systemd/user/default.target.wants/battery-monitor.service"
ln -s "$TARGET_HOME/.config/systemd/user/neo-battery-monitor.service" \
  "$TARGET_HOME/.config/systemd/user/default.target.wants/neo-battery-monitor.service"
target_session_available() { return 1; }
remove_legacy_battery_monitor || fail 'legacy battery monitor migration failed'
[[ ! -e "$TARGET_HOME/.config/systemd/user/battery-monitor.service" && ! -e "$TARGET_HOME/.local/bin/battery-monitor.sh" ]] || fail 'legacy battery files were not removed'
[[ ! -e "$TARGET_HOME/.config/systemd/user/neo-battery-monitor.service" ]] || fail 'default-target C++ battery service was not removed'
[[ -f "$SETUP_BACKUP_DIR/legacy-battery-monitor/battery-monitor.service" && -f "$SETUP_BACKUP_DIR/legacy-battery-monitor/neo-battery-monitor.service" && -f "$SETUP_BACKUP_DIR/legacy-battery-monitor/battery-monitor.sh" ]] || fail 'previous battery files were not backed up'
[[ -x "$SCRIPT_DIR/sway/.local/bin/logout-session.sh" ]] || fail 'GDM-aware Sway logout helper must be executable'
if grep -q 'sway/config/' "$SCRIPT_DIR/lib/50-config-files.sh"; then
  fail 'configuration installer still references the obsolete sway/config source layout'
fi
grep -q '^\[colors-dark\]$' "$SCRIPT_DIR/sway/.config/foot/foot.ini" || fail 'Foot config must use [colors-dark]'
if grep -q '^\[colors\]$' "$SCRIPT_DIR/sway/.config/foot/foot.ini"; then
  fail 'Foot config still uses deprecated [colors]'
fi
grep -q '^bindsym Ctrl+Alt+Delete exec \$close_all$' "$SCRIPT_DIR/sway/.config/sway/config" || fail 'Ctrl+Alt+Delete must invoke the close-all-windows helper'
grep -q '"Ctrl + Alt + Delete|Close all application windows"' "$SCRIPT_DIR/sway/.config/sway/scripts/key-help-wofi.sh" || fail 'key help does not describe close-all behavior'
grep -q '^bindsym Ctrl+Alt+l exec ~/.local/bin/lock-screen.sh$' "$SCRIPT_DIR/sway/.config/sway/config" || fail 'Ctrl+Alt+L must invoke the lock helper'
grep -q '^bindsym Alt+Shift+backslash exec \$term2$' "$SCRIPT_DIR/sway/.config/sway/config" || fail 'Alt+Shift+Backslash must launch the secondary terminal'
grep -Fq 'bindsym $mod+Shift+f floating toggle, sticky toggle, resize set width 800 px height 600 px' "$SCRIPT_DIR/sway/.config/sway/config" || fail 'Super+Shift+F must toggle floating/sticky and set the window size'
grep -q '^bindsym Ctrl+Alt+t exec ~/.local/bin/system-monitor.sh$' "$SCRIPT_DIR/sway/.config/sway/config" || fail 'Ctrl+Alt+T must open the system monitor'
grep -q '^bindsym Print exec \$screenshot$' "$SCRIPT_DIR/sway/.config/sway/config" || fail 'Print must remain a screenshot shortcut'
if grep -Eq '^bindsym \$mod\+Ctrl\+(l|a|b|w|t|c|Delete|n|comma|v)([[:space:]]|$)' "$SCRIPT_DIR/sway/.config/sway/config"; then
  fail 'system controls must not retain duplicate Super+Ctrl bindings'
fi
grep -q '^bindsym Alt+Shift+p exec \$launcher keepassxc$' "$SCRIPT_DIR/sway/.config/sway/config" || fail 'Alt+Shift+P must launch KeePassXC in Sway'
grep -q '^bindsym Ctrl+Alt+e exec ~/.local/bin/logout-session.sh$' "$SCRIPT_DIR/sway/.config/sway/config" || fail 'Ctrl+Alt+E must use GDM-aware logout'
grep -q 'Logout)' "$SCRIPT_DIR/sway/.config/sway/scripts/power-menu.sh" && grep -q 'logout-session.sh' "$SCRIPT_DIR/sway/.config/sway/scripts/power-menu.sh" || fail 'Sway power menu logout must use the GDM-aware helper'
grep -q 'exec swaymsg exit' "$SCRIPT_DIR/sway/.local/bin/logout-session.sh" || fail 'GDM-launched Sway logout must return to the GDM greeter'
grep -q 'session_service.*== gdm' "$SCRIPT_DIR/sway/.local/bin/logout-session.sh" || fail 'Sway logout must only exit directly when the session belongs to GDM'
grep -q 'sudo -n -- "$root_helper" "$session_id"' "$SCRIPT_DIR/sway/.local/bin/logout-session.sh" || fail 'TTY-launched Sway logout must use non-interactive restricted authorization'
grep -q 'sudo -n -- "$systemctl_path" start display-manager.service' "$SCRIPT_DIR/sway/.local/bin/logout-session.sh" || fail 'TTY-launched Sway logout must start GDM without an interactive terminal prompt'
[[ -x "$SCRIPT_DIR/scr/gdm/startup-gdm-logout" ]] || fail 'restricted GDM logout helper must be executable'
grep -q 'systemctl_rule=.*NOPASSWD: /usr/bin/systemctl start display-manager.service' "$SCRIPT_DIR/lib/50-config-files.sh" || fail 'installer must grant only the requested GDM start command without a password'
grep -q 'loginctl activate' "$SCRIPT_DIR/scr/gdm/startup-gdm-logout" || fail 'restricted helper must activate GDM greeter before logout'
grep -q 'loginctl terminate-session' "$SCRIPT_DIR/scr/gdm/startup-gdm-logout" || fail 'restricted helper must end only the validated Sway session'
if grep -Eq '^[[:space:]]*(sudo|pkexec)[[:space:]]' "$SCRIPT_DIR/scr/gdm/startup-gdm-logout"; then
  fail 'root-side logout helper must not recursively request authorization'
fi
[[ -x "$SCRIPT_DIR/sway/.local/bin/setup-gdm-scale.sh" ]] || fail 'GDM text-scale setup utility must be executable'
grep -q 'text-scaling-factor=0.8' "$SCRIPT_DIR/sway/.local/bin/setup-gdm-scale.sh" || fail 'GDM appearance setup must apply 80 percent text scaling'
grep -q 'logout-session.sh' "$SCRIPT_DIR/sway/.config/i3blocks/scripts/menu/power_menu.sh" || fail 'terminal power menu must share the GDM-aware Sway logout helper'
if grep -q 'pkill -KILL -u' "$SCRIPT_DIR/sway/.config/i3blocks/scripts/menu/power_menu.sh"; then
  fail 'terminal power menu must not kill all user processes to log out'
fi
grep -q 'keepassxc) launch_first keepassxc /snap/bin/keepassxc' "$SCRIPT_DIR/sway/.config/sway/scripts/launch-app.sh" || fail 'application launcher must support native and Snap KeePassXC commands'
grep -q 'startup-keepassxc.*<Super><Shift>p.*KeePassXC password manager' "$SCRIPT_DIR/lib/95-gnome-keybindings.sh" || fail 'GNOME must receive the KeePassXC shortcut'
grep -Fq 'STARTUP_CONFIGURE_GNOME' "$SCRIPT_DIR/lib/95-gnome-keybindings.sh" || fail 'GNOME changes must be opt-in to avoid stalling the current desktop session'
grep -Fq "gnome_set_verified org.gnome.desktop.interface icon-theme \"'Adwaita'\"" "$SCRIPT_DIR/lib/95-gnome-keybindings.sh" || fail 'GNOME setup must set the Adwaita icon theme'
grep -q 'gnome_set_verified org.gnome.desktop.interface text-scaling-factor 0\.8' "$SCRIPT_DIR/lib/95-gnome-keybindings.sh" || fail 'GNOME setup must set 80 percent text scaling'
grep -q 'Alt + Shift + P|KeePassXC password manager' "$SCRIPT_DIR/sway/.config/sway/scripts/key-help-wofi.sh" || fail 'Sway key help must list KeePassXC'
grep -q 'Alt + Shift + Backslash|Secondary terminal' "$SCRIPT_DIR/sway/.config/sway/scripts/key-help-wofi.sh" || fail 'Sway key help must list the secondary terminal shortcut'
grep -q 'timeout 1800 .*lock-screen.sh' "$SCRIPT_DIR/sway/.local/bin/start-swayidle.sh" || fail 'Sway idle configuration must lock after inactivity'
grep -q 'before-sleep .*lock-screen.sh' "$SCRIPT_DIR/sway/.local/bin/start-swayidle.sh" || fail 'Sway idle configuration must lock before sleep'
grep -q 'SWAYSOCK' "$SCRIPT_DIR/sway/.local/bin/lock-screen.sh" || fail 'GTKlock helper must refuse to run outside a Sway session'
grep -q 'swaymsg -t get_version' "$SCRIPT_DIR/sway/.local/bin/lock-screen.sh" || fail 'GTKlock helper must confirm the active compositor is Sway'
grep -q 'exec gtklock ' "$SCRIPT_DIR/sway/.local/bin/lock-screen.sh" || fail 'Sway lock helper must launch GTKlock'
if grep -Eq '(^|[[:space:]])(exec[[:space:]]+)?swaylock([[:space:]]|$)' "$SCRIPT_DIR/sway/.local/bin/lock-screen.sh"; then
  fail 'Sway lock helper must not fall back to swaylock'
fi
grep -q 'core) echo .*gtklock' "$SCRIPT_DIR/lib/distros/debian.sh" || fail 'Debian package profile must include GTKlock'
grep -q 'core) echo .*gtklock' "$SCRIPT_DIR/lib/distros/arch.sh" || fail 'Arch package profile must include GTKlock'
if rg -l 'gtklock' "$SCRIPT_DIR/sway/.config/gnome" "$SCRIPT_DIR/sway/.config/autostart" "$SCRIPT_DIR/sway/.config/systemd" 2>/dev/null | grep -q .; then
  fail 'GTKlock must not be wired into GNOME, autostart, or user service config'
fi
grep -q 'swaymsg -t get_tree' "$SCRIPT_DIR/sway/.config/sway/scripts/close-all-windows.sh" || fail 'close-all helper must enumerate the Sway tree'

printf 'Regression checks passed.\n'
