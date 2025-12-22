#!/usr/bin/env bash
# fast-battery-monitor.sh
# Monitors battery and sends notifications immediately on status change or low battery.

set -euo pipefail

# Configuration
SLEEP_INTERVAL=0.2           # check every 0.2 seconds for fast response
THRESHOLDS=(40 30 20 10)     # battery alert thresholds

# Notification function
notify() {
    local summary="$1"
    local body="$2"
    local urgency="${3:-normal}"
    notify-send -u "$urgency" "$summary" "$body"
}

# Find battery directory
BAT_DIR=""
if [ -d /sys/class/power_supply/BAT0 ]; then
    BAT_DIR="/sys/class/power_supply/BAT0"
else
    for d in /sys/class/power_supply/BAT*; do
        [ -d "$d" ] && BAT_DIR="$d" && break
    done
fi

if [ -z "$BAT_DIR" ] || [ ! -d "$BAT_DIR" ]; then
    echo "No battery found. Exiting."
    exit 1
fi

# Track notified thresholds
declare -A notified
last_status=""

clear_notified() {
    for k in "${!notified[@]}"; do
        unset "notified[$k]"
    done
}

# Initial status read
if [ -r "$BAT_DIR/status" ]; then
    last_status="$(cat "$BAT_DIR/status" 2>/dev/null || echo "")"
fi

# Main monitoring loop
while true; do
    # Re-discover battery if missing
    if [ ! -d "$BAT_DIR" ]; then
        if [ -d /sys/class/power_supply/BAT0 ]; then
            BAT_DIR="/sys/class/power_supply/BAT0"
        else
            for d in /sys/class/power_supply/BAT*; do
                [ -d "$d" ] && BAT_DIR="$d" && break
            done
        fi
        sleep "$SLEEP_INTERVAL"
        continue
    fi

    status="$(cat "$BAT_DIR/status" 2>/dev/null || echo "Unknown")"
    capacity=$(( $(cat "$BAT_DIR/capacity" 2>/dev/null || echo 0) ))

    # Unplug detection
    if [[ "$status" == "Discharging" ]]; then
        if [[ "$last_status" != "Discharging" ]]; then
            notify "Battery unplugged" "Battery: ${capacity}%"
        fi

        # Check thresholds
        for t in "${THRESHOLDS[@]}"; do
            if (( capacity <= t )) && [ -z "${notified[$t]:-}" ]; then
                if (( t <= 10 )); then
                    notify "Battery critical: ${capacity}%" "Battery ≤ ${t}% — plug in now!" "critical"
                else
                    notify "Battery low: ${capacity}%" "Battery ≤ ${t}%"
                fi
                notified[$t]=1
            fi
        done

    else
        # Plugged in detection
        if [[ "$last_status" == "Discharging" ]] || [[ "$last_status" == "" ]]; then
            notify "Power connected" "Battery: ${capacity}%"
            clear_notified
        fi
    fi

    last_status="$status"
    sleep "$SLEEP_INTERVAL"
done
