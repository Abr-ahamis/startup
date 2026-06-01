#!/usr/bin/env bash
set -u

BLUE="#0088cc"
ICON=$'\uf011'
case "${BLOCK_BUTTON:-}" in
  1) nohup "$HOME/.config/sway/scripts/power_menu.sh" >/dev/null 2>&1 & ;;
esac
printf "<span color='%s'>%s</span>\n" "$BLUE" " | $ICON "
