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

# Mirror the complete interactive run (stdout and stderr) to a separate
# transcript while retaining the structured setup log used by modules.
start_transcript_logging || true

run_distro
run_packages
run_pipx
run_grub
run_config_files
run_wallpapers
main_sep
run_security
run_services
run_report
