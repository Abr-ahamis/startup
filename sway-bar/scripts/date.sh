#!/usr/bin/env bash
set -u

MUTED="#6e7681"
TEXT="#c9d1d9"
ICON=$'\uf073'
printf "<span color='%s'>%s </span><span color='%s'>%s</span>\n" "$MUTED" " | $ICON" "$TEXT" " $(date '+%Y-%m-%d') "
