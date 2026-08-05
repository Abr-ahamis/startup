#!/usr/bin/env bash
# ==================================================
# Setup — modular installer + hardening layer
#
# Usage:
#   sudo ./setup.sh                  # automated standard installation
#   sudo ./setup.sh --yes            # auto-yes everywhere (non-interactive)
#   sudo ./setup.sh --skip-security  # run all stages except the security layer
#   sudo ./setup.sh --only-security  # run only credential integration checks
#   sudo ./setup.sh --help
#
# Requires: bash 4+, root or sudo, and the project layout:
#   ./setup.sh
#   ./lib/00-common.sh ... 90-report.sh
#   ./grub/
#   ./sway/.config/...
#   ./sway/.local/bin/...
#   ./sway/.local/share/fonts/...
#   ./wallpaper/IMG1.jpg
#   ./wallpaper/IMG2.jpg
#   ./install/script.sh   (optional)
# ==================================================

# Individual operations are checked and logged.  Do not use `set -e`: a single
# unavailable package or optional desktop component must not abort the installer.
set -uo pipefail

SETUP_AUTO_YES=0
SETUP_SKIP_SECURITY=0
SETUP_ONLY_SECURITY=0
SETUP_CREATE_PRO=0
SETUP_REINSTALL=0
SETUP_REMOVE_PACKAGES=()

print_help() {
  cat <<'EOF'
Setup — modular installer + hardening layer

Usage:
  sudo ./setup.sh [options]

Options:
  --yes             Auto-answer yes to every prompt (non-interactive)
  -pro              Create/update the optional pro user and ask about sudo access
  --skip-security   Run all stages except the security layer
  --only-security   Run only the security layer (assumes packages already installed)
  --reinstall       Reinstall the required package set
  --remove PACKAGE  Remove one explicitly named package (repeatable)
  --help            Show this help and exit

Environment:
  SUDO_USER / USER  Target user (defaults to $USER)
  HOME              Used as fallback for target home
  SETUP_APT_LOCK_TIMEOUT  Seconds to wait for an APT lock (default: 20)

Stages (in order):
  1. System detection
  2. Package installation (Debian/Ubuntu/Mint/Kali and Arch)
  3. pipx: autotiling
  4. GRUB files
  5. .config / .local/bin / fonts / permissions
  6. Wallpaper scan and replacement
  7. User services + Sway reload + optional tools
  8. Credential integration checks
  9. Final report
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)             SETUP_AUTO_YES=1; shift;;
    -pro|--pro)        SETUP_CREATE_PRO=1; shift;;
    --skip-security)   SETUP_SKIP_SECURITY=1; shift;;
    --only-security)   SETUP_ONLY_SECURITY=1; shift;;
    --reinstall)       SETUP_REINSTALL=1; shift;;
    --remove)
      [[ $# -ge 2 && "$2" != -* ]] || { printf 'ERROR: --remove needs a package name\n' >&2; exit 1; }
      SETUP_REMOVE_PACKAGES+=("$2"); shift 2;;
    -h|--help)         print_help; exit 0;;
    *) printf 'ERROR: Unknown argument: %s\n' "$1" >&2; print_help; exit 1;;
  esac
done

export SETUP_AUTO_YES SETUP_REINSTALL

# ---------- Locate script dir ----------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

if [[ ! -d "$LIB_DIR" ]]; then
  echo "ERROR: lib/ directory not found at $LIB_DIR" >&2
  echo "       Make sure you run this from the setup project root." >&2
  exit 1
fi

# ---------- Validate and source modules in order ----------
modules=(00-common.sh 10-distro.sh 20-packages.sh 25-users.sh 30-pipx.sh 40-grub.sh 50-config-files.sh 60-wallpapers.sh 70-services.sh 75-theme.sh 80-security.sh 90-report.sh 95-gnome-keybindings.sh)
for module in "${modules[@]}"; do
  if [[ ! -r "$LIB_DIR/$module" ]]; then
    printf 'ERROR: Required module is missing or unreadable: %s\n' "$LIB_DIR/$module" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$LIB_DIR/$module"
done

# Mirror the complete interactive run (stdout and stderr) to a separate
# transcript while retaining the structured setup log used by modules.
start_transcript_logging || true

# Keep the progress denominator truthful for abbreviated runs.
if [[ "$SETUP_ONLY_SECURITY" == "1" ]]; then
  SETUP_STAGE_TOTAL=2
elif [[ "$SETUP_SKIP_SECURITY" == "1" ]]; then
  SETUP_STAGE_TOTAL=8
fi

# ---------- Run stages (no banner — System Info is the first output) ----------
if [[ "$SETUP_AUTO_YES" == "1" ]]; then
  info "AUTO-YES mode: every prompt will be answered yes"
fi
if [[ "$SETUP_SKIP_SECURITY" == "1" ]]; then
  info "Skipping security layer (--skip-security)"
fi
if [[ "$SETUP_ONLY_SECURITY" == "1" ]]; then
  info "Running only the security layer (--only-security)"
fi

run_distro
if [[ "$SETUP_ONLY_SECURITY" != "1" ]]; then
  stage "Package installation"
  run_packages
  stage "Optional autotiling"
  run_pipx
  stage "GTK theme"
  run_theme
  stage "GRUB theme"
  run_grub
  stage "User configuration"
  run_config_files
  stage "Wallpapers"
  run_wallpapers
  stage "User services and Sway"
  run_services
fi

run_gnome_desktop_setup || warn "GNOME desktop settings could not be configured; see $SETUP_LOG_FILE"

if [[ "$SETUP_SKIP_SECURITY" != "1" ]]; then
  stage "Credential protection"
  run_security
fi

stage "Final report"
run_report
