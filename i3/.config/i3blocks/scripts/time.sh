#!/bin/sh
# Simple date & time for i3blocks

while :
do
    # Format: | YYYY-MM-DD | HH : MM |
    TIME=$(date " %H : %M")
    echo "$TIME"
    sleep 60
done

