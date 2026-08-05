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
  if run_as_target env XDG_RUNTIME_DIR="$runtime" SWAYSOCK="$socket" swaymsg reload >>"$SETUP_LOG_FILE" 2>&1 && run_as_target env XDG_RUNTIME_DIR="$runtime" SWAYSOCK="$socket" swaymsg -t get_version >>"$SETUP_LOG_FILE" 2>&1; then
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

run_services() {
  section_setup "User services, xdg-desktop-portal helper, Sway"
  if $can_manage_user_session; then
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway >>"$SETUP_LOG_FILE" 2>&1 || warn "Could not export the portal environment."
    systemctl --user daemon-reexec >>"$SETUP_LOG_FILE" 2>&1 || warn "Could not re-exec the user systemd manager."
    systemctl --user daemon-reload >>"$SETUP_LOG_FILE" 2>&1 || warn "Could not reload user units."
    systemctl --user enable --now pipewire pipewire-pulse wireplumber battery-monitor.service >>"$SETUP_LOG_FILE" 2>&1 || warn "Some user services could not be started."
  fi
  force_refresh_sway_wallpaper || true
  if [[ -x "$TARGET_HOME/.config/sway/scripts/fix-sway-portals.sh" ]] && $can_manage_user_session; then
    bash "$TARGET_HOME/.config/sway/scripts/fix-sway-portals.sh" setup >>"$SETUP_LOG_FILE" 2>&1 || warn "Portal helper repair did not complete."
  fi
  _setup_log_write INFO "Portal helper setup completed; diagnose with ~/.config/sway/scripts/fix-sway-portals.sh status"
}
