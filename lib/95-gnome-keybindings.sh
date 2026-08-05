#!/usr/bin/env bash
# GNOME custom keybinding helpers.

if [[ -n "${__SETUP_GNOME_KEYBINDINGS_LOADED:-}" ]]; then
  return 0
fi
__SETUP_GNOME_KEYBINDINGS_LOADED=1

register_gnome_keybinding() {
  local binding_name="${1:-}"
  local shortcut="${2:-}"
  local label="${3:-}"
  local command="${4:-}"
  local key_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/${binding_name}/"

  [[ -n "$binding_name" && -n "$shortcut" && -n "$label" && -n "$command" ]] || {
    warn "GNOME keybinding registration requires a name, shortcut, label, and command."
    return 1
  }

  if ! command -v gsettings >/dev/null 2>&1; then
    warn "gsettings is not available; skipping GNOME keybinding setup."
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 is required to manage GNOME keybindings; skipping."
    return 0
  fi

  local runtime="${XDG_RUNTIME_DIR:-/run/user/$TARGET_UID}"
  local bus="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$runtime/bus}"
  local -a session_env=(env "XDG_RUNTIME_DIR=$runtime" "DBUS_SESSION_BUS_ADDRESS=$bus" \
    "DISPLAY=${DISPLAY:-}" "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}")

  run_as_target "${session_env[@]}" python3 - "$key_path" <<'PY'
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

  run_as_target "${session_env[@]}" gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${key_path}" name "$label" >/dev/null 2>&1 || return 1
  run_as_target "${session_env[@]}" gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${key_path}" command "$command" >/dev/null 2>&1 || return 1
  run_as_target "${session_env[@]}" gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${key_path}" binding "$shortcut" >/dev/null 2>&1 || return 1

  return 0
}

register_common_gnome_keybindings() {
  local command_path=""

  if command -v gnome-terminal >/dev/null 2>&1; then
    command_path="gnome-terminal"
  elif command -v foot >/dev/null 2>&1; then
    command_path="foot"
  elif command -v xterm >/dev/null 2>&1; then
    command_path="xterm"
  fi

  if [[ -n "$command_path" ]]; then
    register_gnome_keybinding "startup-terminal" "<Primary><Alt>t" "Open terminal" "$command_path" >/dev/null 2>&1 || true
  fi

  if command -v brave-browser >/dev/null 2>&1; then
    register_gnome_keybinding "startup-brave" "<Primary><Alt>b" "Open Brave" "brave-browser" >/dev/null 2>&1 || true
  fi

  if command -v telegram-desktop >/dev/null 2>&1; then
    register_gnome_keybinding "startup-telegram" "<Primary><Alt>m" "Open Telegram" "telegram-desktop" >/dev/null 2>&1 || true
  fi

  if command -v code >/dev/null 2>&1; then
    register_gnome_keybinding "startup-code" "<Primary><Alt>c" "Open VS Code" "code" >/dev/null 2>&1 || true
  fi

  if command -v zen >/dev/null 2>&1; then
    register_gnome_keybinding "startup-zen" "<Primary><Alt>z" "Open Zen Browser" "zen" >/dev/null 2>&1 || true
  fi

  if command -v nautilus >/dev/null 2>&1; then
    register_gnome_keybinding "startup-files" "<Primary><Alt>f" "Open Files" "nautilus" >/dev/null 2>&1 || true
  fi
}

run_gnome_desktop_setup() {
  local desktop=" ${XDG_CURRENT_DESKTOP:-} ${DESKTOP_SESSION:-} ${GDMSESSION:-} "
  [[ "$desktop" == *GNOME* || "$desktop" == *gnome* ]] || return 0
  command -v gsettings >/dev/null 2>&1 || { warn "GNOME detected but gsettings is unavailable."; return 1; }
  local runtime="${XDG_RUNTIME_DIR:-/run/user/$TARGET_UID}"
  local bus="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$runtime/bus}"
  local -a env_args=(env "XDG_RUNTIME_DIR=$runtime" "DBUS_SESSION_BUS_ADDRESS=$bus" "DISPLAY=${DISPLAY:-}" "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}")
  run_as_target "${env_args[@]}" gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close' || return 1
  # Keep GNOME's close shortcut identical to Sway: Super+Shift+Q.
  run_as_target "${env_args[@]}" gsettings set org.gnome.desktop.wm.keybindings close "['<Super><Shift>q']" || return 1
  run_as_target "${env_args[@]}" gsettings set org.gnome.desktop.wm.keybindings panel-main-menu "['<Super>d']" || true
  run_as_target "${env_args[@]}" gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['<Super>f']" || true
  run_as_target "${env_args[@]}" gsettings set org.gnome.settings-daemon.plugins.media-keys screensaver "['<Primary><Alt>l']" || true
  register_gnome_keybinding startup-terminal '<Super>Return' 'Terminal' "$TARGET_HOME/.local/bin/launch-app.sh terminal" || true
  register_gnome_keybinding startup-terminal-secondary '<Super><Shift>Return' 'Secondary terminal' "$TARGET_HOME/.local/bin/launch-app.sh terminal-secondary" || true
  register_gnome_keybinding startup-files '<Super><Shift>e' 'File manager' "$TARGET_HOME/.local/bin/launch-app.sh filemanager" || true
  register_gnome_keybinding startup-browser '<Super><Shift>f' 'Browser' "$TARGET_HOME/.local/bin/launch-app.sh browser" || true
  register_gnome_keybinding startup-browser-secondary '<Super><Shift>b' 'Secondary browser' "$TARGET_HOME/.local/bin/launch-app.sh browser-secondary" || true
  register_gnome_keybinding startup-telegram '<Super><Shift>t' 'Telegram' "$TARGET_HOME/.local/bin/launch-app.sh telegram" || true
  register_gnome_keybinding startup-editor '<Super><Shift>n' 'Text editor' "$TARGET_HOME/.local/bin/launch-app.sh editor" || true
  register_gnome_keybinding startup-screenshot '<Super><Shift>s' 'Screenshot' "$TARGET_HOME/.local/bin/launch-app.sh screenshot" || true
  register_gnome_keybinding startup-code '<Super><Shift>c' 'VS Code' "$TARGET_HOME/.local/bin/launch-app.sh code" || true
  register_gnome_keybinding startup-obsidian '<Super><Shift>o' 'Obsidian' "$TARGET_HOME/.local/bin/launch-app.sh obsidian" || true
  register_gnome_keybinding startup-key-help '<Shift>F1' 'Sway key help' "$TARGET_HOME/.config/sway/scripts/key-help-wofi.sh" || true
  register_gnome_keybinding startup-wifi XF86RFKill 'Toggle Wi-Fi' 'nmcli radio wifi toggle' || true
  run_as_target "${env_args[@]}" gsettings set org.gnome.settings-daemon.plugins.media-keys volume-mute "['XF86AudioMute']" || true
  ok "GNOME desktop settings and keybindings configured"
}
