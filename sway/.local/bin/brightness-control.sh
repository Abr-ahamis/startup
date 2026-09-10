#!/usr/bin/env bash
# Change backlight brightness without blocking the Sway/i3blocks session.
set -u

if ! command -v brightnessctl >/dev/null 2>&1; then
  exit 127
fi

if brightnessctl "$@" >/dev/null 2>&1; then
  pkill -RTMIN+11 i3blocks 2>/dev/null || true
  exit 0
fi

# uaccess/video permissions should normally make the first command succeed.
# Use cached, non-interactive sudo only as a fallback; never prompt from a bar.
if command -v sudo >/dev/null 2>&1 && sudo -n brightnessctl "$@" >/dev/null 2>&1; then
  pkill -RTMIN+11 i3blocks 2>/dev/null || true
  exit 0
fi
exit 1
