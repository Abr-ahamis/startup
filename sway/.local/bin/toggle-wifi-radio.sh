#!/usr/bin/env bash
# Toggle NetworkManager's Wi-Fi radio using the portable on/off interface.
set -euo pipefail

state="$(nmcli -t radio wifi)"
case "$state" in
  enabled) exec nmcli radio wifi off ;;
  disabled) exec nmcli radio wifi on ;;
  *)
    printf 'Cannot determine Wi-Fi radio state: %s\n' "${state:-empty response}" >&2
    exit 1
    ;;
esac
