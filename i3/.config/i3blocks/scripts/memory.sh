#!/bin/bash

# Persistent loop for i3blocks
while true; do
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_free=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_used=$((mem_total - mem_free))

    swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
    swap_free=$(grep SwapFree /proc/meminfo | awk '{print $2}')
    swap_used=$((swap_total - swap_free))

    # Prevent division by zero if swap is disabled
    if [ "$swap_total" -gt 0 ]; then
        swap_percent=$((swap_used * 100 / swap_total))
    else
        swap_percent=0
    fi

    mem_percent=$((mem_used * 100 / mem_total))

    echo " ${swap_percent}% swap |  ${mem_percent}% memory"
    sleep 0.8
done
