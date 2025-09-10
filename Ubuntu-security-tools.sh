#!/usr/bin/env bash
# install_kali_tools_safe.sh
# Safe-ish helper to add Kali repo + install common Kali tools on Ubuntu.
# WARNING: mixing repos can break things. This script uses apt pinning and explicit -t installs to reduce risk.
# Run as root: sudo ./install_kali_tools_safe.sh

set -euo pipefail
IFS=$'\n\t'

LOG="/var/log/kali_tools_installer.log"
BACKUP_DIR="/etc/apt/backup-kali-installer-$(date +%Y%m%d-%H%M%S)"
KALI_KEYRING="/usr/share/keyrings/kali-archive-keyring.gpg"
KALI_SOURCES_LIST="/etc/apt/sources.list.d/kali-rolling.list"
KALI_PREFS="/etc/apt/preferences.d/99kali-pin"

# Curated list of commonly used Kali packages (edit as you want)
PACKAGES=(
  nmap
  masscan
  wireshark
  tshark
  tcpdump
  burpsuite
  sqlmap
  hydra
  john
  hashcat
  aircrack-ng
  metasploit-framework
  nikto
  wpscan
  gobuster
  dirb
  wfuzz
  smbclient
  crackmapexec
  sslscan
  netcat
  sshpass
  responder
  exploitdb
  hash-identifier
  foremost
  binwalk
  radare2
  apktool
  ettercap-graphical
)

# Helpers
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}
die() { echo "ERROR: $*" | tee -a "$LOG" >&2; exit 1; }

ensure_root() {
  if [ "$EUID" -ne 0 ]; then
    die "This script must be run as root. Use sudo."
  fi
}

detect_os() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    log "Detected OS: $NAME ($ID) $VERSION_CODENAME"
  else
    die "Cannot detect OS. /etc/os-release missing."
  fi

  if [ "${ID:-}" != "ubuntu" ]; then
    log "Warning: This script was written for Ubuntu. Detected ID=${ID:-unknown}. Continue at your own risk."
  fi
}

backup_apt_files() {
  log "Backing up apt configuration to $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  cp -a /etc/apt/sources.list "$BACKUP_DIR/" || true
  mkdir -p "$BACKUP_DIR/sources.list.d"
  cp -a /etc/apt/sources.list.d/* "$BACKUP_DIR/sources.list.d/" 2>/dev/null || true
  cp -a /etc/apt/preferences* "$BACKUP_DIR/" 2>/dev/null || true
  log "Backup complete."
}

add_kali_repo_and_key() {
  log "Adding Kali signing key (dearmored) to $KALI_KEYRING"
  mkdir -p "$(dirname "$KALI_KEYRING")"
  # dearmor to avoid apt-key usage (apt-key deprecated)
  if ! command -v gpg >/dev/null 2>&1; then
    log "gpg not found, installing gnupg..."
    apt-get update -y && apt-get install -y gnupg dirmngr || die "Failed to install gnupg"
  fi
  wget -q -O - https://archive.kali.org/archive-key.asc | gpg --dearmor | tee "$KALI_KEYRING" >/dev/null || die "Failed to fetch/dearmor Kali key"

  log "Creating Kali sources list at $KALI_SOURCES_LIST (signed-by used)"
  cat > "$KALI_SOURCES_LIST" <<EOF
deb [signed-by=$KALI_KEYRING] http://http.kali.org/kali kali-rolling main contrib non-free
EOF
  log "Kali repository added but pinned to low priority by preferences file (next step)."
}

create_apt_pinning() {
  log "Creating apt pinning file $KALI_PREFS to avoid accidental upgrades from Kali"
  cat > "$KALI_PREFS" <<'EOF'
# Prevent Kali packages from automatically replacing Ubuntu packages.
# To install a package from Kali explicitly use: apt install -t kali-rolling <package>
Package: *
Pin: origin "http.kali.org"
Pin-Priority: 100
EOF
  log "Apt pinning created. Default priority for Kali origin set to 100 (low)."
}

apt_update_fix() {
  log "Updating apt cache..."
  apt-get update -o Acquire::AllowInsecureRepositories=false || {
    log "apt-get update failed; trying apt-get update --allow-unauthenticated as fallback (not ideal)."
    apt-get update || die "apt-get update failed."
  }
}

try_install_pkg() {
  local pkg="$1"
  log "----"
  log "Attempting install of package: $pkg"

  # First try normal install (Ubuntu repo preferred)
  if apt-get -y install "$pkg"; then
    log "Installed $pkg from default (Ubuntu) repository."
    return 0
  fi

  log "First attempt failed for $pkg. Trying explicit install from Kali (-t kali-rolling)."
  # Try from kali-rolling explicitly
  if apt-get -y -t kali-rolling install "$pkg"; then
    log "Installed $pkg from kali-rolling repository."
    return 0
  fi

  # If still fails, try to fix broken deps then retry one more time
  log "Attempting apt --fix-broken install and retry for $pkg."
  apt-get -y --fix-broken install || true
  if apt-get -y -t kali-rolling install "$pkg"; then
    log "Installed $pkg from kali-rolling after fix-broken."
    return 0
  fi

  log "Failed to install $pkg. See /var/log/kali_tools_installer.log for details."
  return 1
}

main_install_loop() {
  log "Beginning package installation loop. This can take some time."
  local installed=0 failed=0
  for pkg in "${PACKAGES[@]}"; do
    if try_install_pkg "$pkg"; then
      installed=$((installed+1))
    else
      failed=$((failed+1))
    fi
  done

  log "Installation loop finished. Installed: $installed, Failed: $failed"
  log "Check the log for per-package details: $LOG"
}

final_steps() {
  log "Cleaning up apt caches and running autoremove"
  apt-get -y autoremove || true
  apt-get -y autoclean || true
  log "Final apt policy (top lines):"
  apt-cache policy | head -n 40 | tee -a "$LOG"
  log "Finished."
  log "IMPORTANT: If you installed anything using kali-rolling you may want to reboot to ensure services/libraries are consistent."
  log "If you want to remove the Kali repo later, remove $KALI_SOURCES_LIST and $KALI_PREFS (and restore from backup in $BACKUP_DIR)."
}

# Execution
ensure_root
detect_os
backup_apt_files
add_kali_repo_and_key
create_apt_pinning
apt_update_fix

# Check apt is functional
if ! apt-get -y update; then
  log "apt-get update still failed after adding Kali repo. Restoring backups and exiting."
  cp -a "$BACKUP_DIR/sources.list" /etc/apt/sources.list 2>/dev/null || true
  rm -f "$KALI_SOURCES_LIST"
  die "apt-get update failed - cannot proceed safely."
fi

main_install_loop
final_steps

exit 0
