#!/usr/bin/env bash
# User services, portal environment, and verified Sway reload.

if [[ -n "${__SETUP_SERVICES_LOADED:-}" ]]; then return 0; fi
__SETUP_SERVICES_LOADED=1

find_target_sway_socket() {
  # Ignore stale sockets left behind by terminated compositor sessions.
  # target_sway_socket tests each candidate with Sway IPC before returning it.
  target_sway_socket
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

remove_legacy_battery_monitor() {
  local service unit wants
  local -a legacy_services=(battery-monitor.service neo-battery-monitor.service)
  local old_script="$TARGET_HOME/.local/bin/battery-monitor.sh"
  local backup_dir="$SETUP_BACKUP_DIR/legacy-battery-monitor"

  for service in "${legacy_services[@]}"; do
    unit="$TARGET_HOME/.config/systemd/user/$service"
    wants="$TARGET_HOME/.config/systemd/user/default.target.wants/$service"
    if target_session_available; then
      run_as_target_session systemctl --user disable --now "$service" \
        >>"$SETUP_LOG_FILE" 2>&1 || true
    fi
    if [[ -L "$wants" && "$(readlink "$wants")" == "$unit" ]]; then
      run_as_target rm -f -- "$wants" || return 1
    fi
    if [[ -f "$unit" && ! -L "$unit" ]]; then
      run_as_root install -d -m 700 "$backup_dir" || return 1
      run_as_root cp -a -- "$unit" "$backup_dir/$service" || return 1
      run_as_target rm -f -- "$unit" || return 1
    fi
  done
  if [[ -f "$old_script" && ! -L "$old_script" ]]; then
    run_as_root install -d -m 700 "$backup_dir" || return 1
    run_as_root cp -a -- "$old_script" "$backup_dir/battery-monitor.sh" || return 1
    run_as_target rm -f -- "$old_script" || return 1
  fi
}

configure_portal_preference() {
  local helper="$TARGET_HOME/.config/sway/scripts/fix-sway-portals.sh"
  [[ -x "$helper" ]] || return 1
  run_as_target "$helper" setup no >>"$SETUP_LOG_FILE" 2>&1
}

configure_autotiling_startup() {
  local config="$TARGET_HOME/.config/sway/config" line='exec_always --no-startup-id autotiling'
  [[ -f "$config" ]] || return 1
  run_as_target grep -qxF "$line" "$config"
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
  if ! remove_legacy_battery_monitor; then
    warn 'The previous battery monitor could not be fully removed; its backup is in the installer backup directory.'
  fi
  info 'Battery notifications start from the Sway session hook only; other desktop sessions do not launch the monitor.'
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
