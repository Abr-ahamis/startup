#!/usr/bin/env bash
# Download Broadcom BCM43142 driver packages locally, transfer them to Debian,
# and install them offline through neo -> su - root.
set -uo pipefail

REMOTE="${1:-neo@192.168.1.7}"
BUNDLE="${TMPDIR:-/tmp}/startup-broadcom-$(date +%Y%m%d-%H%M%S)"
CONTROL_DIR="${TMPDIR:-/tmp}/startup-broadcom-ssh-$$"
CONTROL_SOCKET="$CONTROL_DIR/control"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }

for command_name in ssh scp apt-get; do
  command -v "$command_name" >/dev/null 2>&1 || fail "$command_name is required on the downloading machine."
done

mkdir -p "$BUNDLE" "$CONTROL_DIR" || fail "Could not create temporary directories"
# Keep the bundle and log for troubleshooting; only the SSH control directory
# is disposable.
trap 'rm -rf -- "$CONTROL_DIR"' EXIT

SSH_OPTIONS=(-o ConnectTimeout=15 -o ControlMaster=auto -o ControlPersist=60 -o "ControlPath=$CONTROL_SOCKET")

info "Checking the remote kernel..."
REMOTE_KERNEL="$(ssh "${SSH_OPTIONS[@]}" "$REMOTE" 'uname -r')" || fail "Could not connect to $REMOTE"
[[ -n "$REMOTE_KERNEL" ]] || fail "The remote kernel version is empty."
info "Remote kernel: $REMOTE_KERNEL"
REMOTE_ARCH="$(ssh "${SSH_OPTIONS[@]}" "$REMOTE" 'dpkg --print-architecture')" || fail "Could not determine the remote Debian architecture."
[[ "$REMOTE_ARCH" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || fail "Invalid remote architecture: $REMOTE_ARCH"
info "Remote architecture: $REMOTE_ARCH"

# Build a temporary Debian package cache locally.  This avoids using Kali
# packages and ensures the headers match the remote Debian kernel exactly.
DEBIAN_APT="$BUNDLE/debian-apt"
mkdir -p "$DEBIAN_APT/lists/partial" "$DEBIAN_APT/archives/partial"
printf '%s\n' \
  'deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware' \
  'deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware' \
  'deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware' \
  >"$DEBIAN_APT/sources.list"

APT_OPTIONS=(
  -o "APT::Architecture=$REMOTE_ARCH"
  -o "Dir::Etc::sourcelist=$DEBIAN_APT/sources.list"
  -o Dir::Etc::sourceparts=-
  -o "Dir::State::lists=$DEBIAN_APT/lists"
  -o "Dir::Cache::archives=$DEBIAN_APT/archives"
  -o Acquire::Languages=none
)

info "Refreshing the local Debian package cache only..."
apt-get "${APT_OPTIONS[@]}" update >>"$BUNDLE/download.log" 2>&1 || fail "Local Debian index refresh failed. See $BUNDLE/download.log"
info "Downloading Debian packages locally..."
apt-get "${APT_OPTIONS[@]}" --download-only --yes --no-install-recommends \
  install broadcom-sta-dkms "linux-headers-$REMOTE_KERNEL" \
  >>"$BUNDLE/download.log" 2>&1 || fail "Exact Debian driver/header download failed. See $BUNDLE/download.log"
find "$DEBIAN_APT/archives" -maxdepth 1 -type f -name '*.deb' -exec cp -a {} "$BUNDLE/" \;
compgen -G "$BUNDLE/*.deb" >/dev/null || fail "No Debian packages were downloaded."

REMOTE_DIR="/tmp/startup-broadcom-$$"
info "Transferring packages to $REMOTE..."
ssh "${SSH_OPTIONS[@]}" "$REMOTE" "mkdir -p '$REMOTE_DIR'" || fail "Could not create the remote staging directory."
scp "${SSH_OPTIONS[@]}" "$BUNDLE"/*.deb "$REMOTE:$REMOTE_DIR/" || fail "Package transfer failed."

info "Installing packages offline as root..."
remote_install="set -u
status=0
dpkg -i '$REMOTE_DIR'/*.deb || status=1
dpkg --configure -a || status=1
apt-get -f install --no-download -y || status=1
/usr/sbin/depmod -a || status=1
/usr/sbin/modprobe wl || status=1
systemctl restart NetworkManager || status=1
command -v rfkill >/dev/null 2>&1 && rfkill unblock wifi || true
command -v nmcli >/dev/null 2>&1 && nmcli radio wifi on || status=1
echo DRIVER_STATUS
/usr/sbin/lsmod | grep -q '^wl' || status=1
ip -br link || true
command -v nmcli >/dev/null 2>&1 && nmcli device status || true
rm -rf '$REMOTE_DIR'
exit \"\$status\""
ssh "${SSH_OPTIONS[@]}" -tt "$REMOTE" "su - root -c $(printf '%q' "$remote_install")" || fail "Remote installation or driver loading failed. Local bundle: $BUNDLE"

ok "Broadcom driver installation and Wi-Fi verification completed. Local log: $BUNDLE/download.log"
