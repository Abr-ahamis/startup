#!/usr/bin/env bash
set -u

MUTED="#6e7681"
TEXT="#c9d1d9"
ICON=$'\uf0ac'
ipaddr="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"

if [ -z "$ipaddr" ]; then
  printf "<span color='%s'>%s </span><span color='%s'>no ip</span>\n" "$MUTED" "$ICON" "$MUTED"
else
  printf "| <span color='%s'>%s </span><span color='%s'>%s</span>\n" "$MUTED" "$ICON" "$TEXT" "$ipaddr"
fi
