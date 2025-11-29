#!/bin/sh
# Simple date & time for i3blocks

while :
do
    # Format: | YYYY-MM-DD | HH : MM |
    TIME=$(date "+| %Y-%m-%d")
    echo "$TIME"
    sleep 60
done
