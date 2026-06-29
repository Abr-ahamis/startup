#!/usr/bin/env bash

swaymsg -t subscribe '["window"]' | while read -r _; do
    count=$(swaymsg -t get_tree | jq '.. | objects | select(.type=="con") | select(.app_id!=null) | length')

    if [ "$count" -ge 2 ]; then
        # multiple apps open → dim unfocused
        swaymsg 'for_window [focused] opacity 0.94'
        swaymsg 'for_window [con_id!=focused] opacity 0.85'
    else
        # single app → normal
        swaymsg 'for_window [all] opacity 0.94'
    fi
done