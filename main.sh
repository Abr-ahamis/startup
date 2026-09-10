#!/usr/bin/env bash
# Single supported installer entry point. Operations remain independently
# checked/logged; no command-line options are supported.
set -uo pipefail

if (( $# > 0 )); then
  printf '%s\n' 'This installer does not accept command-line options.' 'Run:' '    ./main.sh' 'or:' '    sudo ./main.sh'
  exit 2
fi

# ---------- Locate script dir ----------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

if [[ ! -d "$LIB_DIR" ]]; then
  echo "ERROR: lib/ directory not found at $LIB_DIR" >&2
  echo "       Make sure you run this from the setup project root." >&2
  exit 1
fi

# ---------- Validate and source modules in order ----------
modules=(00-common.sh 10-distro.sh 20-packages.sh 25-users.sh 30-pipx.sh 40-grub.sh 50-config-files.sh 60-wallpapers.sh 70-services.sh 80-security.sh 90-report.sh 95-gnome-keybindings.sh)
for module in "${modules[@]}"; do
  if [[ ! -r "$LIB_DIR/$module" ]]; then
    printf 'ERROR: Required module is missing or unreadable: %s\n' "$LIB_DIR/$module" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$LIB_DIR/$module"
done

if [[ -z "${TARGET_HOME:-}" || "${TARGET_USER:-root}" == root ]]; then
  printf '%s\n' 'ERROR: Could not determine a non-root target user.' \
    'Set STARTUP_TARGET_USER=<user> or run through sudo from that user.' >&2
  exit 1
fi

run_distro || exit 1
run_packages || required_failure 'Package stage failed; later stages may be incomplete.'
run_config_files || required_failure 'Configuration deployment stage failed.'
run_wallpapers || warn 'Wallpaper stage failed.'
run_security || warn 'Security integration stage failed or was deferred.'
run_services || warn 'Service/session stage failed or was deferred.'
run_grub || required_failure 'GRUB stage failed.'
run_report
