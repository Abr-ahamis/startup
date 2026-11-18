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
package_name_approved grub-customizer || fail 'optional grub-customizer must remain an approved package'
info() { :; }
SETUP_REQUIRED_FAILURES=()
package_installed() { return 1; }
package_available() { return 1; }
install_optional_grub_customizer || fail 'missing optional grub-customizer should not fail package setup'
[[ "${#SETUP_REQUIRED_FAILURES[@]}" == 0 ]] || fail 'missing optional grub-customizer must not create a required package failure'

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
for resource in foot i3blocks sway flameshot wofi systemd startup; do
  [[ -d "$SCRIPT_DIR/sway/.config/$resource" ]] || fail "missing managed resource: sway/.config/$resource"
done
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
