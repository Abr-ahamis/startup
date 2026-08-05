#!/usr/bin/env bash
set -uo pipefail

# =========================
# Config
# =========================
MUTED="#ffffff"
TEXT="#ffffff"
ICON_COLOR="#cba6f7"
GREEN="#ffffff"
YELLOW="#ffffff"
RED="#ffffff"
ICON=""

state_dir="${XDG_RUNTIME_DIR:-}"
if [[ -z "$state_dir" || ! -d "$state_dir" || ! -w "$state_dir" ]]; then
  state_dir="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/i3blocks"
  mkdir -p "$state_dir" 2>/dev/null || state_dir="/tmp"
fi
CACHE_FILE="$state_dir/i3updates_count_${UID:-$(id -u)}"

# =========================
# Click action
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot -e bash -c '
      set -e

      echo "=============================="
      echo " SYSTEM UPDATE"
      echo "=============================="
      echo ""

      sudo -v

      echo "[*] Updating package list..."
      if command -v pacman >/dev/null 2>&1; then sudo pacman -Sy --noconfirm; else sudo apt-get update; fi

      echo ""
      echo ""
      echo "[+] Package metadata refreshed; no packages were upgraded."
      echo "=============================="
      read -rp "Press Enter to close..."
    ' >/dev/null 2>&1 &
    ;;
esac

# =========================
# Get update count
# =========================
get_updates() {
  # Refresh cache every 5 minutes
  if [[ -f "$CACHE_FILE" ]]; then
    if [[ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE"))) -lt 300 ]]; then
      cat "$CACHE_FILE"
      return
    fi
  fi

  local count=0

  if command -v checkupdates >/dev/null 2>&1; then
    count="$(checkupdates 2>/dev/null | wc -l || true)"
  elif command -v apt >/dev/null 2>&1; then
    count="$(apt list --upgradeable 2>/dev/null | awk 'NR>1 {c++} END {print c+0}')"
  elif command -v pacman >/dev/null 2>&1; then
    count="$(pacman -Qu 2>/dev/null | wc -l || true)"
  fi

  printf '%s\n' "$count" > "$CACHE_FILE" 2>/dev/null || true
  echo "$count"
}

count="$(get_updates)"

# =========================
# Color logic
# =========================
color="$TEXT"

color="$TEXT"

# =========================
# Output
# =========================
printf "<span color='%s'>| </span><span color='%s'>%s</span> <span color='%s'>%s</span>\n" \
  "$TEXT" "$ICON_COLOR" "$ICON" "$TEXT" "$count"
