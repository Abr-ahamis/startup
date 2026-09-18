#!/usr/bin/env bash
# Shared palette for i3blocks.  Source this file; it deliberately prints nothing.
PRIMARY_TEXT='#F5F5F7'; SECONDARY_TEXT='#F5F5F7'; DISABLED='#5E9DFF'
ACCENT='#0A84FF'; HEALTHY='#0A84FF'; ATTENTION='#FFD60A'; WARNING='#FF9F0A'
CRITICAL='#FF453A'; MEDIA='#BF5AF2'; NOTIFICATIONS='#FF375F'; NETWORK='#0A84FF'
STABLE_ICON="$ACCENT"
percentage_color() {
  local value="${1:-0}"
  [[ "$value" =~ ^-?[0-9]+$ ]] || value=0
  (( value < 0 )) && value=0; (( value > 100 )) && value=100
  if (( value >= 85 )); then
    printf '%s\n' "$CRITICAL"
  elif (( value >= 75 )); then
    printf '%s\n' "$WARNING"
  elif (( value >= 40 )); then
    printf '%s\n' "$ATTENTION"
  else
    printf '%s\n' "$ACCENT"
  fi
}
