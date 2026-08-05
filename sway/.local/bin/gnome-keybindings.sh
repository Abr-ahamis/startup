#!/usr/bin/env bash
set -euo pipefail

if (( $# < 4 )); then
  echo "Usage: $0 <binding-name> <shortcut> <label> <command>" >&2
  exit 2
fi

binding_name="$1"
shortcut="$2"
label="$3"
command="$4"
key_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/${binding_name}/"

if ! command -v gsettings >/dev/null 2>&1; then
  echo "gsettings is not available; skipping GNOME keybinding setup." >&2
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to manage GNOME keybindings." >&2
  exit 0
fi

python3 - "$key_path" <<'PY'
import subprocess
import sys
path = sys.argv[1]
try:
    out = subprocess.check_output([
        'gsettings', 'get', 'org.gnome.settings-daemon.plugins.media-keys', 'custom-keybindings'
    ], text=True, stderr=subprocess.DEVNULL)
except subprocess.CalledProcessError:
    out = '[]'
try:
    items = eval(out.strip() or '[]')
except Exception:
    items = []
if isinstance(items, str):
    items = [items]
if path not in items:
    items.append(path)
subprocess.check_call([
    'gsettings', 'set', 'org.gnome.settings-daemon.plugins.media-keys', 'custom-keybindings', str(items)
])
PY

gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${key_path}" name "$label"
gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${key_path}" command "$command"
gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${key_path}" binding "$shortcut"
