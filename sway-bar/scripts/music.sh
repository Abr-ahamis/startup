#!/usr/bin/env bash
set -u

TEXT="#c9d1d9"
MUTED="#6e7681"
OFF="#4a5568"

case "${BLOCK_BUTTON:-}" in
  1) playerctl previous >/dev/null 2>&1 || true ;;
  2) playerctl play-pause >/dev/null 2>&1 || true ;;
  3) playerctl next >/dev/null 2>&1 || true ;;
esac

status="$(playerctl status 2>/dev/null || printf Stopped)"
case "$status" in
  Playing) color="$TEXT"; middle=$'\uf04c' ;;
  Paused) color="$MUTED"; middle=$'\uf04b' ;;
  *) color="$OFF"; middle=$'\uf04b' ;;
esac

printf "<span color='%s'>%s</span>  <span color='%s'>%s</span>  <span color='%s'>%s</span>\n" "$MUTED" $'\uf048' "$color" "$middle" "$MUTED" $'\uf051'
