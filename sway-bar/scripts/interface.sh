#!/usr/bin/env bash
set -u

MUTED="#6e7681"
TEXT="#c9d1d9"
iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"

case "$iface" in
  wl*) icon=$'\uf1eb' ;;
  eth*|en*) icon=$'\uf6ff' ;;
  *) icon=$'\uf6ff'; [ -z "$iface" ] && iface="---" ;;
esac

printf "| <span color='%s'>%s </span><span color='%s'>%s</span>\n" "$MUTED" "$icon" "$TEXT" "$iface "
