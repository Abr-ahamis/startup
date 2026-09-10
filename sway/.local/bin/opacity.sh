#!/usr/bin/env bash

set -uo pipefail

command -v swaymsg >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

apply_opacity() {
    mapfile -t nodes < <(
        swaymsg -t get_tree | jq -r '
            .. | objects
            | select(.type? == "con")
            | select(.pid != null)
            | "\(.id) \(.focused)"
        ' 2>/dev/null
    )

    count=${#nodes[@]}

    if (( count <= 1 )); then
        for node in "${nodes[@]}"; do
            id=$(awk '{print $1}' <<< "$node")
            swaymsg "[con_id=$id] opacity set 0.80" >/dev/null
        done
        return
    fi

    for node in "${nodes[@]}"; do
        id=$(awk '{print $1}' <<< "$node")
        focused=$(awk '{print $2}' <<< "$node")

        if [[ "$focused" == "true" ]]; then
            swaymsg "[con_id=$id] opacity set 0.85" >/dev/null
        else
            swaymsg "[con_id=$id] opacity set 0.75" >/dev/null
        fi
    done
}

apply_opacity

swaymsg -t subscribe '["window"]' |
while read -r _; do
    apply_opacity
done
