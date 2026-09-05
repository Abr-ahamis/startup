#!/usr/bin/env bash
# User services, portal environment, and verified Sway reload.

if [[ -n "${__SETUP_SERVICES_LOADED:-}" ]]; then return 0; fi
__SETUP_SERVICES_LOADED=1

find_target_sway_socket() {
  local runtime="/run/user/$TARGET_UID"
  [[ -d "$runtime" ]] || return 1
  find "$runtime" -maxdepth 1 -type s -name 'sway-ipc.*.sock' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {print $2}'
}

reload_target_sway() {
  local runtime="/run/user/$TARGET_UID" socket
  socket="$(find_target_sway_socket || true)"
  if [[ -z "$socket" ]]; then
    if pgrep -u "$TARGET_UID" -x sway >/dev/null 2>&1; then
      _setup_log_write WARN "Sway is running but its IPC socket is unavailable; reload was deferred."
    fi
    return 1
  fi
  if run_as_target env XDG_RUNTIME_DIR="$runtime" SWAYSOCK="$socket" timeout --foreground 8s swaymsg reload >>"$SETUP_LOG_FILE" 2>&1 && run_as_target env XDG_RUNTIME_DIR="$runtime" SWAYSOCK="$socket" timeout --foreground 8s swaymsg -t get_version >>"$SETUP_LOG_FILE" 2>&1; then
    _setup_log_write INFO "Sway reload confirmed."
    return 0
  fi
  _setup_log_write WARN "Sway reload failed; check the setup log for details."
  return 1
}

force_refresh_sway_wallpaper() {
  local runtime="/run/user/$TARGET_UID"
  [[ -d "$runtime" ]] || return 0
  run_as_target env XDG_RUNTIME_DIR="$runtime" sh -c '
    pkill -u "$USER" -x swaybg 2>/dev/null || true
  ' >>"$SETUP_LOG_FILE" 2>&1 || true
}

enable_battery_monitor() {
  local unit="$TARGET_HOME/.config/systemd/user/battery-monitor.service"
  local wants="$TARGET_HOME/.config/systemd/user/default.target.wants/battery-monitor.service"
  [[ -f "$unit" && ! -L "$unit" ]] || return 1
  run_as_target mkdir -p "$(dirname "$wants")" || return 1
  [[ ! -e "$wants" || -L "$wants" ]] || return 1
  run_as_target ln -sfn "$unit" "$wants" || return 1
  [[ -L "$wants" && "$(readlink "$wants")" == "$unit" ]]
}

configure_portal_preference() {
  local helper="$TARGET_HOME/.config/sway/scripts/fix-sway-portals.sh"
  [[ -x "$helper" ]] || return 1
  run_as_target "$helper" setup no >>"$SETUP_LOG_FILE" 2>&1
}

configure_autotiling_startup() {
  local config="$TARGET_HOME/.config/sway/config" line='exec_always --no-startup-id autotiling'
  [[ -f "$config" ]] || return 1
  run_as_target grep -qxF "$line" "$config" || printf '%s\n' "$line" | run_as_target tee -a "$config" >/dev/null
}

run_services() {
  printf '\n%s──────────────────────────────────────────────────────────────────────%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  printf '  %s%s▶  Services and xdg-desktop-portal%s\n' "$SETUP_COLOR_BOLD" "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  printf '  %s──────────────────────────────────────────────────────────────────────%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  if run_pipx && configure_autotiling_startup; then
    ok_indented 'autotiling started'
  else
    warn 'autotiling startup could not be configured.'
  fi
  if enable_battery_monitor; then
    ok_indented 'battery-monitor.service enabled for the next target-user session'
  else
    warn 'battery-monitor.service could not be enabled for the target user.'
  fi
  if configure_portal_preference; then
    ok_indented 'Sway portal preference installed; live portal services were not restarted'
  else
    warn 'Sway portal preference could not be installed.'
  fi
  if target_session_available && run_as_target_session timeout --foreground 15s systemctl --user daemon-reload >>"$SETUP_LOG_FILE" 2>&1; then
    ok_indented 'Portal configuration verified for the active session'
  else
    warn 'Portal configuration could not be verified because the target user session is unavailable.'
  fi
  if run_gnome_desktop_setup; then
    ok_indented 'GNOME desktop settings and keybindings configured'
  else
    warn 'GNOME desktop settings and keybindings could not be configured.'
  fi
}
