#!/usr/bin/env bash
# Open the first installed terminal system monitor, with top as the base fallback.
set -u

for monitor in btop htop top; do
    if command -v "$monitor" >/dev/null 2>&1; then
        exec foot -e "$monitor"
    fi
done

printf '%s\n' 'No terminal system monitor is available (btop, htop, or top).' >&2
exit 127
