#!/bin/bash
# i3blocks CPU/Mem/Swap using top as the data source (non-interactive)
set -u

top_out=$(top -bn1)

cpu_usage=$(awk -F'[:, ]+' '/^%Cpu\(s\):/ { for (i=1;i<=NF;i++) if ($i=="id") { id=$(i-1); } }
  END { if (id=="") { print "0"; } else { printf "%3.0f", 100 - id; } }' <<<"$top_out")

mem_line=$(awk -F'[:, ]+' '/^MiB Mem/ {print $0}' <<<"$top_out")
swap_line=$(awk -F'[:, ]+' '/^MiB Swap/ {print $0}' <<<"$top_out")

mem_used=$(awk -F'[, ]+' '{ for (i=1;i<=NF;i++) if ($i=="used") { print $(i-1); exit } }' <<<"$mem_line")
mem_total=$(awk -F'[, ]+' '{ for (i=1;i<=NF;i++) if ($i=="total") { print $(i-1); exit } }' <<<"$mem_line")

swap_used=$(awk -F'[, ]+' '{ for (i=1;i<=NF;i++) if ($i=="used") { print $(i-1); exit } }' <<<"$swap_line")
swap_total=$(awk -F'[, ]+' '{ for (i=1;i<=NF;i++) if ($i=="total") { print $(i-1); exit } }' <<<"$swap_line")

# Fallbacks if parsing fails
mem_used=${mem_used:-0}
mem_total=${mem_total:-0}
swap_used=${swap_used:-0}
swap_total=${swap_total:-0}

echo " CPU ${cpu_usage}%  |   ${mem_used}% / ${mem_total}% MiB  |    ${swap_used}% / ${swap_total} MiB"
