#!/bin/bash

SAMPLE=0.8   # refresh rate in seconds

# function to read CPU values
read_cpu() {
    read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    echo "$user $nice $system $idle $iowait $irq $softirq $steal"
}

prev=($(read_cpu))

while true; do
    sleep $SAMPLE
    curr=($(read_cpu))

    # extract values
    prev_idle=$((prev[3] + prev[4]))
    prev_total=$((${prev[0]} + ${prev[1]} + ${prev[2]} + ${prev[3]} + ${prev[4]} + ${prev[5]} + ${prev[6]} + ${prev[7]}))

    idle_now=$((curr[3] + curr[4]))
    total_now=$((${curr[0]} + ${curr[1]} + ${curr[2]} + ${curr[3]} + ${curr[4]} + ${curr[5]} + ${curr[6]} + ${curr[7]}))

    diff_total=$((total_now - prev_total))
    diff_idle=$((idle_now - prev_idle))

    cpu_usage=$(awk -v idle="$diff_idle" -v total="$diff_total" \
        'BEGIN { printf "%3.0f", 100 * (1 - idle/total) }')

    echo " CPU ${cpu_usage}%"
    echo ""   # empty line for short_text (required)
    prev=("${curr[@]}")
done
