#!/usr/bin/env bash
# Close every application window in the current Sway session after confirmation.
set -u

for command in swaymsg jq wofi; do
  command -v "$command" >/dev/null 2>&1 || exit 127
done

choice="$(printf '%s\n' 'Cancel' 'Close all windows' | wofi --dmenu --insensitive --prompt 'Close all windows?' 2>/dev/null || true)"
[[ "$choice" == 'Close all windows' ]] || exit 0

swaymsg -t get_tree -r |
  jq -r '.. | objects | select(.type == "con" and (.app_id != null or .window != null)) | .id' |
  sort -un |
  while IFS= read -r container_id; do
    [[ "$container_id" =~ ^[0-9]+$ ]] || continue
    swaymsg "[con_id=$container_id] kill" >/dev/null 2>&1 || true
  done
