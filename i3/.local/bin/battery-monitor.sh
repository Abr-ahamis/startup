#!/usr/bin/env bash
# battery-monitor.sh
# Monitors /sys/class/power_supply/BAT* and sends notifications:
# - "Plugged" / "Unplugged" when status changes
# - Alerts when capacity falls to or below 40, 30, 20, 10 (once each cycle)
#
# Requirements: notify-send (libnotify-bin on Debian/Ubuntu/Kali)

set -euo pipefail

# config
SLEEP_INTERVAL=8          # seconds between checks
THRESHOLDS=(40 30 20 10)  # notify when capacity <= threshold, in this order

# helpers
notify () {
    # $1 = summary, $2 = body, $3 = urgency (low, normal, critical) optional
    local summary="$1"
    local body="$2"
    local urgency="${3:-normal}"
    # send notification (no specific color/icon required)
    notify-send -u "$urgency" "$summary" "$body"
}

# find battery directory (prefer BAT0, fallback to first BAT*)
BAT_DIR=""
if [ -d /sys/class/power_supply/BAT0 ]; then
    BAT_DIR="/sys/class/power_supply/BAT0"
else
    # try to find any BAT* (e.g. BAT1)
    for d in /sys/class/power_supply/BAT*; do
        [ -d "$d" ] && BAT_DIR="$d" && break
    done
fi

if [ -z "$BAT_DIR" ] || [ ! -d "$BAT_DIR" ]; then
    echo "No battery found in /sys/class/power_supply (no BAT* directories). Exiting."
    exit 1
fi

# track notifications already sent this discharge cycle
declare -A notified
last_status=""

clear_notified() {
    for k in "${!notified[@]}"; do
        unset "notified[$k]"
    done
}

# initial read (so we can notify on immediate plug/unplug)
if [ -r "$BAT_DIR/status" ]; then
    last_status="$(cat "$BAT_DIR/status" 2>/dev/null || echo "")"
fi

# main loop
while true; do
    # guard in case the battery dir disappears/reappears
    if [ ! -d "$BAT_DIR" ]; then
        # attempt to rediscover
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

    # read values (use safe defaults)
    status="$(cat "$BAT_DIR/status" 2>/dev/null || echo "Unknown")"
    capacity="$(cat "$BAT_DIR/capacity" 2>/dev/null || echo "0")"

    # normalize capacity to integer
    capacity=$((capacity + 0))

    # plugged vs unplugged detection
    if [[ "$status" == "Discharging" ]]; then
        # if we just switched into Discharging, notify "Unplugged"
        if [[ "$last_status" != "Discharging" ]]; then
            notify "Battery unplugged" "Battery: ${capacity}% — watching thresholds: ${THRESHOLDS[*]}"
        fi

        # check thresholds and notify once each threshold per discharge cycle
        for t in "${THRESHOLDS[@]}"; do
            if (( capacity <= t )); then
                if [ -z "${notified[$t]:-}" ]; then
                    # make lower thresholds more urgent
                    if (( t <= 10 )); then
                        notify "Battery critical: ${capacity}%" "Battery ≤ ${t}% — plug in now!" "critical"
                    else
                        notify "Battery low: ${capacity}%" "Battery ≤ ${t}%"
                    fi
                    notified[$t]=1
                fi
            fi
        done

    else
        # treat Charging and Full and other non-Discharging as plugged
        if [[ "$last_status" == "Discharging" ]] || [[ "$last_status" == "" ]]; then
            # notify when it becomes plugged/charging or full (status changed away from Discharging)
            notify "Power connected" "Battery: ${capacity}% — charging or full"
            # reset the alerted thresholds so the next discharge cycle will alert again
            clear_notified
        fi
    fi

    last_status="$status"
    sleep "$SLEEP_INTERVAL"
done
