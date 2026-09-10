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

  target_session_available || { info "GNOME session unavailable; keybinding '$binding_name' deferred."; return 0; }
  run_as_target_session python3 - "$key_path" <<'PY'
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

  run_as_target_session gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${key_path}" name "$label" >/dev/null 2>&1 || return 1
  run_as_target_session gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${key_path}" command "$command" >/dev/null 2>&1 || return 1
  run_as_target_session gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${key_path}" binding "$shortcut" >/dev/null 2>&1 || return 1

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

gnome_set_verified() {
  local schema="$1" key="$2" value="$3"
  run_as_target_session gsettings writable "$schema" "$key" 2>/dev/null | grep -qx true || {
    warn "GNOME setting is unavailable or locked: $schema::$key"; return 1; }
  run_as_target_session gsettings set "$schema" "$key" "$value" >>"$SETUP_LOG_FILE" 2>&1 || {
    warn "Could not set GNOME setting: $schema::$key"; return 1; }
  run_as_target_session gsettings get "$schema" "$key" >/dev/null 2>&1 || {
    warn "Could not verify GNOME setting: $schema::$key"; return 1; }
  record_verification "GNOME $schema::$key" OK "value=$value"
}

configure_gnome_dock() {
  local schema='org.gnome.shell.extensions.dash-to-dock'
  run_as_target_session gsettings list-schemas | grep -qx "$schema" || {
    defer 'Dash to Dock is not installed; dock placement and icon size were not changed.'; return 0; }
  gnome_set_verified "$schema" dock-position LEFT || return 1
  gnome_set_verified "$schema" dash-max-icon-size 23 || return 1
  ok_indented 'GNOME dock set to the left with 23px icons'
}

run_gnome_desktop_setup() {
  local desktop=" ${XDG_CURRENT_DESKTOP:-} ${DESKTOP_SESSION:-} ${GDMSESSION:-} "
  if target_session_available; then
    desktop=" $desktop $(run_as_target_session systemctl --user show-environment 2>/dev/null | awk -F= '$1 ~ /^(XDG_CURRENT_DESKTOP|DESKTOP_SESSION|GDMSESSION)$/ {print $2}' | tr '\n' ' ') "
  fi
  [[ "$desktop" == *GNOME* || "$desktop" == *gnome* ]] || return 0
  command -v gsettings >/dev/null 2>&1 || { warn "GNOME detected but gsettings is unavailable."; return 1; }
  if target_session_available; then
    run_as_target_session gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close' || return 1
  else
    info "GNOME user session unavailable; GNOME settings deferred until login."
    return 0
  fi
  # Keep common window/workspace behavior aligned with the shipped Sway map.
  gnome_set_verified org.gnome.desktop.wm.keybindings close "['<Super><Shift>q']" || return 1
  gnome_set_verified org.gnome.desktop.wm.keybindings panel-main-menu "['<Super>d']" || return 1
  gnome_set_verified org.gnome.desktop.wm.keybindings toggle-fullscreen "['<Super>f']" || return 1
  gnome_set_verified org.gnome.desktop.wm.keybindings switch-to-workspace-left "['<Super>Left']" || return 1
  gnome_set_verified org.gnome.desktop.wm.keybindings switch-to-workspace-right "['<Super>Right']" || return 1
  gnome_set_verified org.gnome.desktop.wm.keybindings move-to-workspace-left "['<Super><Shift>Left']" || return 1
  gnome_set_verified org.gnome.desktop.wm.keybindings move-to-workspace-right "['<Super><Shift>Right']" || return 1
  gnome_set_verified org.gnome.settings-daemon.plugins.media-keys screensaver "['<Primary><Alt>l']" || return 1
  local launcher="$TARGET_HOME/.config/sway/scripts/launch-app.sh"
  [[ -x "$launcher" ]] || { warn "GNOME launcher binding source is not executable: $launcher"; return 1; }
  register_gnome_keybinding startup-terminal '<Super>Return' 'Terminal' "$launcher terminal" || return 1
  register_gnome_keybinding startup-terminal-secondary '<Super><Shift>Return' 'Secondary terminal' "$launcher terminal-secondary" || return 1
  register_gnome_keybinding startup-files '<Super><Shift>e' 'File manager' "$launcher filemanager" || return 1
  register_gnome_keybinding startup-browser '<Super><Shift>f' 'Browser' "$launcher browser" || return 1
  local telegram_command="${STARTUP_TELEGRAM_COMMAND:-/opt/Telegram/Telegram}"
  [[ -x "$telegram_command" ]] || telegram_command="$launcher telegram"
  register_gnome_keybinding startup-telegram '<Super><Shift>t' 'Telegram' "$telegram_command" || return 1
  register_gnome_keybinding startup-editor '<Super><Shift>n' 'Text editor' "$launcher editor" || return 1
  register_gnome_keybinding startup-screenshot '<Super><Shift>s' 'Screenshot' "$launcher screenshot" || return 1
  register_gnome_keybinding startup-code '<Super><Shift>c' 'VS Code' "$launcher code" || return 1
  register_gnome_keybinding startup-key-help '<Shift>F1' 'Sway key help' "$TARGET_HOME/.config/sway/scripts/key-help-wofi.sh" || return 1
  register_gnome_keybinding startup-wifi XF86RFKill 'Toggle Wi-Fi' 'nmcli radio wifi toggle' || return 1
  configure_gnome_dock || return 1
}
