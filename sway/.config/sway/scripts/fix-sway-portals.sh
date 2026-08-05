#!/usr/bin/env bash
set -uo pipefail

info()  { echo "[+] $*"; }
ok()    { echo "[OK] $*"; }
warn()  { echo "[WARN] $*" >&2; }

ACTION="${1:-setup}"
CFG_DIR="$HOME/.config/xdg-desktop-portal"
SWAY_PORTALS="$CFG_DIR/sway-portals.conf"
PORTALS_CONF="$CFG_DIR/portals.conf"
SWAY_CFG="$HOME/.config/sway/config"

timestamp() { date +"%Y%m%d-%H%M%S"; }

backup_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    cp -a "$path" "$path.bak.$(timestamp)"
  fi
}

write_configs() {
  info "Writing portal configs..."
  if ! mkdir -p "$CFG_DIR"; then warn "Cannot create portal config directory: $CFG_DIR"; return 1; fi

  backup_if_exists "$SWAY_PORTALS"
  cat > "$SWAY_PORTALS" <<'EOF' || { warn "Cannot write $SWAY_PORTALS"; return 1; }
[preferred]
default=gtk
org.freedesktop.impl.portal.FileChooser=gtk
org.freedesktop.impl.portal.Settings=gtk
org.freedesktop.impl.portal.Screenshot=wlr
org.freedesktop.impl.portal.ScreenCast=wlr
EOF

  backup_if_exists "$PORTALS_CONF"
  cat > "$PORTALS_CONF" <<'EOF' || { warn "Cannot write $PORTALS_CONF"; return 1; }
[preferred]
default=gtk
org.freedesktop.impl.portal.FileChooser=gtk
org.freedesktop.impl.portal.Settings=gtk
org.freedesktop.impl.portal.Screenshot=wlr
org.freedesktop.impl.portal.ScreenCast=wlr
EOF
}

remove_legacy_sway_config_block() {
  # Older versions appended raw shell commands to sway/config.  Sway reads
  # those as configuration directives and reports errors.  Environment export
  # belongs in startup-session.sh, not in the compositor configuration.
  local temporary
  [[ -f "$SWAY_CFG" ]] || return 0
  grep -q '^# fix-sway-portals start$' "$SWAY_CFG" || return 0
  temporary="$(mktemp "${SWAY_CFG}.XXXXXX")" || return 1
  awk '
    /^# fix-sway-portals start$/ { skipping=1; next }
    /^# fix-sway-portals end$/ { skipping=0; next }
    !skipping { print }
  ' "$SWAY_CFG" >"$temporary" || { rm -f -- "$temporary"; return 1; }
  mv -- "$temporary" "$SWAY_CFG"
  info "Removed the obsolete portal block from the Sway configuration."
}

clear_cache() {
  info "Clearing portal cache..."
  rm -rf "$HOME/.cache/xdg-desktop-portal" 2>/dev/null || true
}

restart_services() {
  info "Restarting portal services..."
  command -v dbus-update-activation-environment >/dev/null 2>&1 && \
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway >/dev/null 2>&1 || true
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user reset-failed xdg-desktop-portal >/dev/null 2>&1 || true
    systemctl --user reset-failed xdg-desktop-portal-wlr >/dev/null 2>&1 || true
    systemctl --user restart xdg-desktop-portal-wlr >/dev/null 2>&1 || true
    systemctl --user restart xdg-desktop-portal >/dev/null 2>&1 || true
  fi
}

status() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user status xdg-desktop-portal xdg-desktop-portal-wlr --no-pager || true
  else
    warn "systemctl is unavailable; portal service status cannot be displayed"
  fi
}

remove_all() {
  info "Removing portal configs..."
  rm -f "$SWAY_PORTALS" "$PORTALS_CONF"
  rm -rf "$HOME/.cache/xdg-desktop-portal" 2>/dev/null || true
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop xdg-desktop-portal xdg-desktop-portal-wlr >/dev/null 2>&1 || true
    systemctl --user reset-failed xdg-desktop-portal >/dev/null 2>&1 || true
    systemctl --user reset-failed xdg-desktop-portal-wlr >/dev/null 2>&1 || true
  fi
}

case "$ACTION" in
  setup)
    write_configs
    remove_legacy_sway_config_block
    clear_cache
    restart_services
    status
    ;;
  restart|start)
    clear_cache
    restart_services
    status
    ;;
  status)
    status
    ;;
  remove)
    remove_all
    status || true
    ;;
  *)
    echo "Usage: $0 {setup|restart|start|status|remove}"
    exit 1
    ;;
esac
