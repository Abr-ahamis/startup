#!/usr/bin/env bash
# Omarchy Login + Lock Screen Customizer
# v2.0.0
#
# Changes:
#   1. Plymouth/LUKS unlock screen -> fullscreen selected image + centered entry.
#   2. SDDM login screen -> fullscreen selected image + centered login.
#   3. Omarchy desktop lock screen -> selected image via the Omarchy Quickshell lock plugin.
#   4. SDDM autologin disabled so the SDDM login can actually be shown at boot.
#
# Usage:
#   ./omarchy-loginscreen.sh
#   ./omarchy-loginscreen.sh --image /home/neo/Pictures/IMG1.jpg
#   ./omarchy-loginscreen.sh --preview
#   ./omarchy-loginscreen.sh --restore

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_NAME="Omarchy Login + Lock Screen Customizer"
VERSION="2.0.0"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
REPO_IMAGE="$REPO_DIR/wallpaper/IMG1.jpg"

SUDO_USER_NAME="${SUDO_USER:-}"
if [[ -n "$SUDO_USER_NAME" ]] && id "$SUDO_USER_NAME" &>/dev/null; then
  USER_HOME="$(getent passwd "$SUDO_USER_NAME" | cut -d: -f6)"
else
  USER_HOME="${HOME:-/root}"
fi

PLYMOUTH_DIR="/usr/share/plymouth/themes/omarchy"
PLYMOUTH_SCRIPT="$PLYMOUTH_DIR/omarchy.script"
PLYMOUTH_LOGO="$PLYMOUTH_DIR/logo.png"
PLYMOUTH_PREVIEW="$PLYMOUTH_DIR/preview-unlock.png"
SDDM_DIR="/usr/share/sddm/themes/omarchy"
SDDM_MAIN="$SDDM_DIR/Main.qml"
SDDM_LOGO="$SDDM_DIR/logo.png"
SDDM_AUTLOGIN="/etc/sddm.conf.d/autologin.conf"
SDDM_AUTLOGIN_DISABLED="/etc/sddm.conf.d/autologin.conf.disabled"
SDDM_AUTLOGIN_BACKUP="/etc/sddm.conf.d/autologin.conf.bak"

LOCK_QML="/usr/share/omarchy/shell/plugins/lock/LockView.qml"
LOCK_STATE_DIR="$USER_HOME/.local/share/neo-omarchy-login-customizer"
LOCK_IMAGE="$LOCK_STATE_DIR/lockscreen.png"

STATE_DIR="/var/lib/neo-omarchy-login-customizer"
BACKUP_DIR="$STATE_DIR/backup"
LOG_DIR="$STATE_DIR/logs"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$BACKUP_DIR/$TIMESTAMP"
LOG_FILE="$LOG_DIR/$TIMESTAMP.log"

IMAGE_PATH=""
MODE="install"

write_message() {
  local message="$1" output_fd="${2:-1}"
  printf '%s\n' "$message" >&"$output_fd"
  if [[ -w "$LOG_DIR" ]]; then
    printf '%s\n' "$message" >> "$LOG_FILE"
  fi
}

log()  { write_message "[INFO] $*"; }
ok()   { write_message "[ OK ] $*"; }
warn() { write_message "[WARN] $*" 2; }
die()  { write_message "[FAIL] $*" 2; exit 1; }

trap 'rc=$?; if (( rc != 0 )); then printf "\n"; warn "Operation failed with exit code $rc."; [[ -d "$RUN_DIR" ]] && warn "Backup: $RUN_DIR"; warn "Log: $LOG_FILE"; fi' EXIT

usage() {
  cat <<USAGE
$SCRIPT_NAME v$VERSION

Usage:
  $0                       Ask for image and install
  $0 --image PATH          Install using PATH
  $0 --preview             Preview the current Plymouth theme
  $0 --restore             Restore the latest backup
  $0 --help                Show this help

The default image is:
  $REPO_IMAGE

A different image can be supplied with --image PATH.
USAGE
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || die "This operation needs root, but sudo is not installed."
    [[ -t 0 ]] || die "This operation needs root. Run it from a terminal so sudo can ask for permission."
    printf '[INFO] Administrator permission is required; sudo will ask for your password.\n' >&2
    exec sudo -- "$SCRIPT_DIR/$(basename -- "$0")" "$@"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

init_state() {
  mkdir -p "$BACKUP_DIR" "$LOG_DIR"
  chmod 700 "$STATE_DIR" "$BACKUP_DIR" "$LOG_DIR" 2>/dev/null || true
  : > "$LOG_FILE"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --image)
        [[ $# -ge 2 ]] || die "--image requires a path."
        IMAGE_PATH="$2"
        shift 2
        ;;
      --preview)
        MODE="preview"
        shift
        ;;
      --restore)
        MODE="restore"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

check_omarchy() {
  require_cmd omarchy
  [[ -d "$PLYMOUTH_DIR" ]] || die "Omarchy Plymouth theme not found: $PLYMOUTH_DIR"
  [[ -f "$PLYMOUTH_SCRIPT" ]] || die "Plymouth script not found: $PLYMOUTH_SCRIPT"
  [[ -d "$SDDM_DIR" ]] || die "Omarchy SDDM theme not found: $SDDM_DIR"
  [[ -f "$SDDM_MAIN" ]] || die "SDDM Main.qml not found: $SDDM_MAIN"
  [[ -f "$LOCK_QML" ]] || die "Omarchy Quickshell lock file not found: $LOCK_QML"
}

resolve_image() {
  if [[ -z "$IMAGE_PATH" ]]; then
    printf 'Enter image path (default %s): ' "$REPO_IMAGE"
    read -r IMAGE_PATH || true
    if [[ -z "$IMAGE_PATH" ]]; then
      IMAGE_PATH="$REPO_IMAGE"
    fi
  fi

  IMAGE_PATH="${IMAGE_PATH/#\~\//$USER_HOME/}"

  [[ -f "$IMAGE_PATH" ]] || die "Image file not found: $IMAGE_PATH"
  IMAGE_PATH="$(realpath -e "$IMAGE_PATH")"
  ok "Selected image: $IMAGE_PATH"
}

choose_converter() {
  if command -v magick >/dev/null 2>&1; then
    CONVERTER=(magick)
  elif command -v convert >/dev/null 2>&1; then
    CONVERTER=(convert)
    warn "Using deprecated ImageMagick 'convert'; 'magick' is preferred."
  else
    die "ImageMagick is required. Install it with: sudo pacman -S imagemagick"
  fi
}

backup_one() {
  local src="$1" dst="$2"
  if [[ -e "$src" || -L "$src" ]]; then
    mkdir -p "$(dirname "$RUN_DIR/$dst")"
    cp -a -- "$src" "$RUN_DIR/$dst"
  fi
}

create_backup() {
  mkdir -p "$RUN_DIR"
  chmod 700 "$RUN_DIR"

  backup_one "$PLYMOUTH_SCRIPT" "plymouth/omarchy.script"
  backup_one "$PLYMOUTH_LOGO" "plymouth/logo.png"
  backup_one "$PLYMOUTH_PREVIEW" "plymouth/preview-unlock.png"
  backup_one "$SDDM_MAIN" "sddm/Main.qml"
  backup_one "$SDDM_LOGO" "sddm/logo.png"
  backup_one "$SDDM_AUTLOGIN" "sddm/autologin.conf"
  backup_one "$SDDM_AUTLOGIN_DISABLED" "sddm/autologin.conf.disabled"
  backup_one "$SDDM_AUTLOGIN_BACKUP" "sddm/autologin.conf.bak"
  backup_one "$LOCK_QML" "lock/LockView.qml"
  backup_one "$LOCK_IMAGE" "lock/lockscreen.png"

  cat > "$RUN_DIR/manifest.txt" <<MANIFEST
Neo Omarchy Login + Lock Screen Customizer
Version: $VERSION
Timestamp: $TIMESTAMP
Invoking user: ${SUDO_USER_NAME:-unknown}
User home: $USER_HOME
Image: $IMAGE_PATH
Plymouth script: $PLYMOUTH_SCRIPT
SDDM Main.qml: $SDDM_MAIN
SDDM logo: $SDDM_LOGO
Lock QML: $LOCK_QML
Lock image: $LOCK_IMAGE
MANIFEST

  chmod 600 "$RUN_DIR/manifest.txt"
  printf '%s\n' "$RUN_DIR" > "$STATE_DIR/latest-backup"
  ok "Backup created: $RUN_DIR"
}

install_image() {
  mkdir -p "$LOCK_STATE_DIR"
  chown "$SUDO_USER_NAME:$SUDO_USER_NAME" "$LOCK_STATE_DIR" 2>/dev/null || true

  log "Converting selected image to PNG..."
  "${CONVERTER[@]}" "$IMAGE_PATH" "$PLYMOUTH_LOGO"
  chmod 644 "$PLYMOUTH_LOGO"

  cp -f -- "$PLYMOUTH_LOGO" "$SDDM_LOGO"
  cp -f -- "$PLYMOUTH_LOGO" "$PLYMOUTH_PREVIEW"
  cp -f -- "$PLYMOUTH_LOGO" "$LOCK_IMAGE"

  chmod 644 "$SDDM_LOGO" "$PLYMOUTH_PREVIEW" "$LOCK_IMAGE"
  chown "$SUDO_USER_NAME:$SUDO_USER_NAME" "$LOCK_IMAGE" 2>/dev/null || true

  ok "Image installed for Plymouth, SDDM, and Omarchy lock screen."
}

write_plymouth_script() {
  # Replace the original logo block with a fullscreen cover background.
  python3 - "$PLYMOUTH_SCRIPT" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
new_block = '''#----------------------------------------- Fullscreen Background --------------------------------

background.image = Image("logo.png");

screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

image_width = background.image.GetWidth();
image_height = background.image.GetHeight();

screen_ratio = screen_width / screen_height;
image_ratio = image_width / image_height;

if (screen_ratio > image_ratio) {
  scale_factor = screen_width / image_width;
} else {
  scale_factor = screen_height / image_height;
}

scaled_background = background.image.Scale(
  image_width * scale_factor,
  image_height * scale_factor
);

background.sprite = Sprite(scaled_background);

background.sprite.SetPosition(
  screen_width / 2 - scaled_background.GetWidth() / 2,
  screen_height / 2 - scaled_background.GetHeight() / 2,
  -10000
);

background.sprite.SetOpacity(1);

# Keep the original logo object only for compatibility with existing layout references.
logo.image = Image("oma.png");
logo.sprite = Sprite(logo.image);
logo.sprite.SetOpacity(0);
'''
pattern = re.compile(r'Window\.SetBackgroundTopColor\(0\.101, 0\.105, 0\.149\);\nWindow\.SetBackgroundBottomColor\(0\.101, 0\.105, 0\.149\);\n.*?logo\.sprite\.SetOpacity\(1\);\n', re.S)
if not pattern.search(s):
    raise SystemExit('Plymouth logo block was not recognized; refusing to modify it.')
s = pattern.sub('Window.SetBackgroundTopColor(0.101, 0.105, 0.149);\nWindow.SetBackgroundBottomColor(0.101, 0.105, 0.149);\n\n' + new_block, s, count=1)
s = re.sub(r'^entry\.y = .*?;$', 'entry.y = Window.GetHeight() / 2 - entry.image.GetHeight() / 2;', s, count=1, flags=re.M)
# Remove duplicate centered entry assignments if a prior run left one behind.
lines=[]; seen=False
for line in s.splitlines(True):
    if line.strip() == 'entry.y = Window.GetHeight() / 2 - entry.image.GetHeight() / 2;':
        if seen:
            continue
        seen=True
    lines.append(line)
p.write_text(''.join(lines))
PY
  ok "Plymouth configured for fullscreen image + centered LUKS entry."
}

write_sddm() {
  cat > "$SDDM_MAIN" <<'QML'
import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#000000"

  property string currentUser: userModel.lastUser
  property bool loginFailed: false

  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  Image {
    id: backgroundImage
    anchors.fill: parent
    source: "logo.png"
    fillMode: Image.PreserveAspectCrop
    horizontalAlignment: Image.AlignHCenter
    verticalAlignment: Image.AlignVCenter
    asynchronous: false
    cache: false
    z: 0
  }

  Rectangle {
    anchors.fill: parent
    color: "#000000"
    opacity: 0.18
    z: 1
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.forceActiveFocus()
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 40
    z: 2

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: entry.width
        height: entry.height

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(password.text.length, 21)
            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "\u2022"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          focus: true

          onTextChanged: root.loginFailed = false

          Keys.onPressed: {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              sddm.login(root.currentUser, password.text, root.sessionIndex)
              event.accepted = true
            }
          }
        }
      }
    }
  }

  Component.onCompleted: password.forceActiveFocus()
}
QML
  chmod 644 "$SDDM_MAIN"
  ok "SDDM configured for fullscreen image login."
}

write_lock_qml() {
  # Omarchy 4.x Quickshell lock screen uses LockView.qml and a QML Image whose
  # source is derived from root.backgroundPath. Replace only that source binding.
  python3 - "$LOCK_QML" "$LOCK_IMAGE" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
lock_image = sys.argv[2]
s = p.read_text()
file_url = 'file://' + lock_image
pattern = re.compile(r'(^\s*source\s*:\s*)root\.loadBackground\s*\?\s*root\.fileUrl\(root\.backgroundPath\)\s*:\s*""\s*$', re.M)
replacement = r'\1root.loadBackground ? root.fileUrl("' + file_url.replace('"', '\\"') + '") : ""'
if not pattern.search(s):
    raise SystemExit('Omarchy LockView.qml background source was not recognized; refusing to modify it.')
s = pattern.sub(replacement, s, count=1)
p.write_text(s)
PY
  ok "Omarchy desktop lock screen configured to use the selected image."
}

disable_sddm_autologin() {
  if [[ -f "$SDDM_AUTLOGIN" ]]; then
    [[ -f "$SDDM_AUTLOGIN_BACKUP" ]] || cp -a "$SDDM_AUTLOGIN" "$SDDM_AUTLOGIN_BACKUP"
    mv "$SDDM_AUTLOGIN" "$SDDM_AUTLOGIN_DISABLED"
    ok "SDDM autologin disabled."
  elif [[ -f "$SDDM_AUTLOGIN_DISABLED" ]]; then
    ok "SDDM autologin already disabled."
  else
    warn "No Omarchy autologin.conf found; SDDM may already require login."
  fi
}

verify() {
  grep -q 'source: "logo.png"' "$SDDM_MAIN" || die "SDDM image source missing."
  grep -q 'Image.PreserveAspectCrop' "$SDDM_MAIN" || die "SDDM fullscreen mode missing."
  grep -q 'background.image = Image("logo.png")' "$PLYMOUTH_SCRIPT" || die "Plymouth background source missing."
  grep -q 'entry.y = Window.GetHeight() / 2 - entry.image.GetHeight() / 2;' "$PLYMOUTH_SCRIPT" || die "Plymouth centered LUKS entry missing."
  grep -qF "$LOCK_IMAGE" "$LOCK_QML" || die "Omarchy lock screen image path was not installed."
  file -b "$PLYMOUTH_LOGO" | grep -q '^PNG image data' || die "Plymouth logo is not a real PNG."
  [[ -f "$LOCK_IMAGE" ]] || die "Lock screen image missing."
  ok "All three screens verified: LUKS, SDDM, desktop lock screen."
}

rebuild_boot() {
  log "Rebuilding Omarchy boot image..."
  if command -v limine-mkinitcpio >/dev/null 2>&1; then
    limine-mkinitcpio
  else
    mkinitcpio -P || true
    command -v limine-mkinitcpio >/dev/null 2>&1 || die "limine-mkinitcpio not found."
    limine-mkinitcpio
  fi
  limine-update
  ok "Omarchy UKI rebuilt and Limine updated."
}

restart_shell() {
  if command -v omarchy-restart-shell >/dev/null 2>&1; then
    omarchy-restart-shell || warn "omarchy-restart-shell returned non-zero."
  elif command -v omarchy >/dev/null 2>&1 && omarchy help 2>/dev/null | grep -q 'restart shell'; then
    omarchy restart shell || warn "omarchy restart shell returned non-zero."
  else
    warn "Could not find an Omarchy shell restart command; log out/in to reload the lock screen."
  fi
}

preview() {
  log "Starting Plymouth preview..."
  omarchy plymouth preview || warn "Plymouth preview returned non-zero."
}

latest_backup() {
  local d=""
  if [[ -f "$STATE_DIR/latest-backup" ]]; then
    d="$(cat "$STATE_DIR/latest-backup")"
  fi
  [[ -d "$d" ]] || d="$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
  [[ -d "$d" ]] || die "No backup found."
  printf '%s\n' "$d"
}

restore() {
  local b
  b="$(latest_backup)"
  log "Restoring $b"
  [[ -f "$b/plymouth/omarchy.script" ]] && install -m 0644 "$b/plymouth/omarchy.script" "$PLYMOUTH_SCRIPT"
  [[ -f "$b/plymouth/logo.png" ]] && install -m 0644 "$b/plymouth/logo.png" "$PLYMOUTH_LOGO"
  [[ -f "$b/plymouth/preview-unlock.png" ]] && install -m 0644 "$b/plymouth/preview-unlock.png" "$PLYMOUTH_PREVIEW"
  [[ -f "$b/sddm/Main.qml" ]] && install -m 0644 "$b/sddm/Main.qml" "$SDDM_MAIN"
  [[ -f "$b/sddm/logo.png" ]] && install -m 0644 "$b/sddm/logo.png" "$SDDM_LOGO"
  [[ -f "$b/lock/LockView.qml" ]] && install -m 0644 "$b/lock/LockView.qml" "$LOCK_QML"
  [[ -f "$b/lock/lockscreen.png" ]] && install -m 0644 "$b/lock/lockscreen.png" "$LOCK_IMAGE"

  rm -f "$SDDM_AUTLOGIN" "$SDDM_AUTLOGIN_DISABLED"
  if [[ -f "$b/sddm/autologin.conf" ]]; then
    install -m 0644 "$b/sddm/autologin.conf" "$SDDM_AUTLOGIN"
  elif [[ -f "$b/sddm/autologin.conf.disabled" ]]; then
    install -m 0644 "$b/sddm/autologin.conf.disabled" "$SDDM_AUTLOGIN_DISABLED"
  fi

  rebuild_boot
  restart_shell
  ok "Latest backup restored."
}

main() {
  parse_args "$@"
  require_root "$@"
  init_state

  if [[ "$MODE" == "restore" ]]; then
    check_omarchy
    restore
    exit 0
  fi

  if [[ "$MODE" == "preview" ]]; then
    check_omarchy
    preview
    exit 0
  fi

  require_cmd python3
  require_cmd file
  require_cmd realpath
  require_cmd install
  check_omarchy
  choose_converter
  resolve_image
  create_backup
  install_image
  write_plymouth_script
  write_sddm
  write_lock_qml
  disable_sddm_autologin
  verify
  rebuild_boot
  restart_shell

  echo
  echo "============================================================"
  echo "$SCRIPT_NAME v$VERSION"
  echo "============================================================"
  echo "Image:            $IMAGE_PATH"
  echo "LUKS/Plymouth:    FULLSCREEN + CENTERED UNLOCK"
  echo "SDDM:             FULLSCREEN + CENTERED LOGIN"
  echo "Desktop lock:     CUSTOM IMAGE"
  echo "Backup:            $RUN_DIR"
  echo "Log:               $LOG_FILE"
  echo "============================================================"
  echo

  if [[ -t 0 ]]; then
    read -r -p "Run Plymouth preview now? [Y/n] " a || true
    a="${a:-Y}"
    [[ "$a" =~ ^[Yy]$ ]] && preview

    echo
    read -r -p "Lock the desktop now to test the new lock screen? [y/N] " a || true
    if [[ "$a" =~ ^[Yy]$ ]]; then
      if command -v omarchy-system-lock >/dev/null 2>&1; then
        su - "$SUDO_USER_NAME" -c 'omarchy-system-lock' || warn "Lock command returned non-zero."
      else
        loginctl lock-session || warn "loginctl lock-session returned non-zero."
      fi
    fi

    echo
    read -r -p "Reboot now to test the LUKS screen? [y/N] " a || true
    [[ "$a" =~ ^[Yy]$ ]] && exec reboot
  fi
}

main "$@"
