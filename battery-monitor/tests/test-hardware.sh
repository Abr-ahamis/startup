#!/usr/bin/env bash
# Exercise the compiled CLI against a fake sysfs tree; does not need hardware.
set -euo pipefail

binary="${1:-}"
[[ -x "$binary" ]] || { printf 'Usage: %s /path/to/neo-battery-monitor\n' "$0" >&2; exit 2; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p "$tmp/sys/BAT0" "$tmp/sys/AC"
printf '%s\n' Battery > "$tmp/sys/BAT0/type"
printf '%s\n' 82 > "$tmp/sys/BAT0/capacity"
printf '%s\n' Charging > "$tmp/sys/BAT0/status"
printf '%s\n' 12000000 > "$tmp/sys/BAT0/voltage_now"
printf '%s\n' Mains > "$tmp/sys/AC/type"
printf '%s\n' 1 > "$tmp/sys/AC/online"

check_output="$(NEO_BATTERY_SYSFS_PATH="$tmp/sys" "$binary" --check)"
[[ "$check_output" == *'Battery device: BAT0'* ]]
[[ "$check_output" == *'Capacity: 82%'* ]]
[[ "$check_output" == *'Battery status: Charging'* ]]
[[ "$check_output" == *'External power: AC connected'* ]]

status_output="$(NEO_BATTERY_SYSFS_PATH="$tmp/sys" "$binary" --status)"
[[ "$status_output" == *'BAT 82%'* && "$status_output" == *'Charging'* && "$status_output" == *'AC connected'* ]]

printf '%s\n' 'NEO Battery Monitor hardware checks passed.'
