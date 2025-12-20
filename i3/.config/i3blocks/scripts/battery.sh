#!/usr/bin/env bash
# i3blocks battery module that reads GNOME exported JSON
JSON=/tmp/gnome_status.json
SAMPLE=0.6  # seconds between updates

while true; do
  if [[ -r "$JSON" ]]; then
    # get values from JSON
    pct=$(jq -r '.battery.percent // -1' "$JSON" 2>/dev/null)
    state=$(jq -r '.battery.state // "N/A"' "$JSON" 2>/dev/null)

    if [[ "$pct" -ge 0 ]]; then
      icon="" # adjust icon by pct if you want
      echo "$icon $pct%"
    else
      echo " N/A"
    fi
  else
    echo " N/A"
  fi

  # i3blocks expects a single status line, but many configs use persist scripts that keep running
  # Print an empty line for full_text / additional fields if your i3blocks expects them
  echo ""
  sleep "$SAMPLE"
done
