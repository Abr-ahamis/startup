#!/bin/sh
# Persistent date & time for i3blocks

while :; do
    # Format: | YYYY-MM-DD | HH:MM |
    TIME=$(date "+ %Y-%m-%d |   %H:%M ")
    echo "$TIME"
    sleep 60
done
