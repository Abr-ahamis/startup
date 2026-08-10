#!/usr/bin/env bash
# Fast, session-aware Sway portal repair.  It never writes shell commands into
# sway/config and never waits for the wlr backend outside an active Sway session.
set -uo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

ACTION="${1:-setup}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CFG_DIR="$XDG_CONFIG_HOME/xdg-desktop-portal"
SWAY_PORTALS="$CFG_DIR/sway-portals.conf"
PORTALS_CONF="$CFG_DIR/portals.conf"
SWAY_CFG="$XDG_CONFIG_HOME/sway/config"
CACHE_DIR="$XDG_CACHE_HOME/xdg-desktop-portal"

timestamp() { date +'%Y%m%d-%H%M%S'; }
backup_if_exists() { [[ -e "$1" ]] && cp -a -- "$1" "$1.bak.$(timestamp)"; }

portal_content() {
  cat <<'EOF'
[preferred]
default=gtk
org.freedesktop.impl.portal.FileChooser=gtk
org.freedesktop.impl.portal.Settings=gtk
org.freedesktop.impl.portal.Screenshot=wlr
org.freedesktop.impl.portal.ScreenCast=wlr
EOF
}

sway_session_active() {
  local socket desktop
  # A nested test compositor can have a valid Sway IPC socket while GNOME is
  # still the real desktop.  Only select the wlr portal when Sway is the
  # active desktop session, not merely when a nested Sway process exists.
  desktop="${XDG_CURRENT_DESKTOP:-}"
  [[ "${desktop,,}" == *sway* ]] || return 1
  for socket in "${XDG_RUNTIME_DIR:-/nonexistent}"/sway-ipc."$(id -u)".*.sock; do
    [[ -S "$socket" ]] || continue
    SWAYSOCK="$socket" swaymsg -t get_version >/dev/null 2>&1 && { export SWAYSOCK="$socket"; return 0; }
  done
  return 1
}

write_if_changed() {
  local path="$1" temp
  temp="$(mktemp "$CFG_DIR/.portal.XXXXXX")" || return 1
  portal_content >"$temp"
  if [[ -f "$path" ]] && cmp -s "$temp" "$path"; then rm -f -- "$temp"; return 0; fi
  backup_if_exists "$path" || { rm -f -- "$temp"; return 1; }
  mv -f -- "$temp" "$path"
}

write_configs() {
  mkdir -p -m 700 "$CFG_DIR" || { warn "Cannot create $CFG_DIR"; return 1; }
  write_if_changed "$SWAY_PORTALS" || { warn "Cannot write $SWAY_PORTALS"; return 1; }
  # Only use the generic fallback while Sway is active.  In GNOME it would
  # override the desktop's portal selection and make wlr startup time out.
  if sway_session_active; then
    write_if_changed "$PORTALS_CONF" || { warn "Cannot write $PORTALS_CONF"; return 1; }
  elif [[ -f "$PORTALS_CONF" ]] && [[ "$(cat -- "$PORTALS_CONF")" == "$(portal_content)" ]]; then
    backup_if_exists "$PORTALS_CONF" && rm -f -- "$PORTALS_CONF" || return 1
    info "Removed old generic Sway portal fallback for this non-Sway session"
  fi
  ok "Portal configuration is current"
}

remove_legacy_sway_block() {
  local temp
  [[ -f "$SWAY_CFG" ]] && grep -q '^# fix-sway-portals start$' "$SWAY_CFG" || return 0
  temp="$(mktemp "${SWAY_CFG}.XXXXXX")" || return 1
  awk '/^# fix-sway-portals start$/ { skip=1; next } /^# fix-sway-portals end$/ { skip=0; next } !skip' "$SWAY_CFG" >"$temp" || { rm -f -- "$temp"; return 1; }
  backup_if_exists "$SWAY_CFG" && mv -f -- "$temp" "$SWAY_CFG" || { rm -f -- "$temp"; return 1; }
  info "Removed obsolete shell commands from Sway config"
}

clear_cache() { [[ -e "$CACHE_DIR" ]] && rm -rf -- "$CACHE_DIR" || true; }
have_user_bus() { command -v systemctl >/dev/null 2>&1 && [[ -S "${XDG_RUNTIME_DIR:-}/bus" ]]; }

restart_unit() {
  local unit="$1"
  systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
  # Bound startup so a broken D-Bus service cannot hold the installer for a
  # minute.  Failure remains visible and has a real nonzero return status.
  timeout 10s systemctl --user restart "$unit"
}

restart_services() {
  have_user_bus || { warn "No active user D-Bus session; portal services were not restarted"; return 2; }
  command -v dbus-update-activation-environment >/dev/null 2>&1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP || true
  systemctl --user daemon-reload || return 1
  restart_unit xdg-desktop-portal.service || { warn "xdg-desktop-portal.service could not restart"; return 1; }
  if sway_session_active; then
    restart_unit xdg-desktop-portal-wlr.service || { warn "xdg-desktop-portal-wlr.service could not restart in the active Sway session"; return 1; }
  else
    info "Sway is not active; wlr portal backend was intentionally not restarted"
  fi
  ok "Portal services restarted"
}

status() {
  have_user_bus || { warn "No active user D-Bus session"; return 2; }
  local unit state
  for unit in xdg-desktop-portal.service; do
    state="$(systemctl --user is-active "$unit" 2>/dev/null || true)"
    printf '%-32s %s\n' "$unit" "${state:-unknown}"
    [[ "$state" == active ]] || return 1
  done
  if sway_session_active; then
    state="$(systemctl --user is-active xdg-desktop-portal-wlr.service 2>/dev/null || true)"
    printf '%-32s %s\n' xdg-desktop-portal-wlr.service "${state:-unknown}"
    [[ "$state" == active ]] || return 1
  fi
}

remove_all() {
  rm -f -- "$SWAY_PORTALS" "$PORTALS_CONF"
  clear_cache
  have_user_bus || return 0
  systemctl --user stop xdg-desktop-portal.service xdg-desktop-portal-wlr.service >/dev/null 2>&1 || true
}

case "$ACTION" in
  setup) write_configs && remove_legacy_sway_block && clear_cache && restart_services && status ;;
  restart|start) clear_cache && restart_services && status ;;
  status) status ;;
  remove) remove_all ;;
  *) printf 'Usage: %s {setup|restart|start|status|remove}\n' "$0" >&2; exit 1 ;;
esac
