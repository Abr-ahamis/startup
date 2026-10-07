#!/usr/bin/env bash
# Close every application window in the current Sway session.
set -euo pipefail

for command in swaymsg jq; do
  command -v "$command" >/dev/null 2>&1 || exit 127
done

tree="$(swaymsg -t get_tree -r 2>/dev/null)" || exit 1
container_ids="$(jq -r '.. | objects | select(.type == "con" and (.app_id != null or .window != null)) | .id' <<<"$tree" | sort -un)" || exit 1

while IFS= read -r container_id; do
  [[ "$container_id" =~ ^[0-9]+$ ]] || continue
  swaymsg "[con_id=$container_id] kill" >/dev/null 2>&1 || true
done <<<"$container_ids"
