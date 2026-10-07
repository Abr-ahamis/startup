#!/usr/bin/env bash
set -euo pipefail

iface="${1:-}"
[[ -n "$iface" ]] || { printf 'No network interface was selected.\n'; exit 2; }
command -v nmcli >/dev/null 2>&1 || { printf 'NetworkManager (nmcli) is unavailable.\n'; exit 1; }

while true; do
  state="$(nmcli -g GENERAL.STATE device show "$iface" 2>/dev/null || printf unknown)"
  profile="$(nmcli -g GENERAL.CONNECTION device show "$iface" 2>/dev/null || printf -- '--')"
  [[ -n "$profile" ]] || profile='--'
  printf '\033[2J\033[H\033[1;38;2;193;181;230mWired network interface\033[0m\n\n'
  printf 'Interface : %s\nConnection: %s\nState     : %s\n\n' "$iface" "$profile" "$state"
  printf 'c connect  d disconnect  r refresh  q exit\n'
  IFS= read -rsn1 action || exit 0
  case "$action" in
    c|C) nmcli device connect "$iface" || true; printf '\nPress Enter to continue...'; IFS= read -r _ || exit 0;;
    d|D) nmcli device disconnect "$iface" || true; printf '\nPress Enter to continue...'; IFS= read -r _ || exit 0;;
    r|R) :;;
    q|Q) exit 0;;
  esac
done
