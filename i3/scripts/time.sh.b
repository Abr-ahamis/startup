#!/bin/sh
# vim:ts=4:sw=4:expandtab

# Tell i3bar that JSON will follow
echo '{"version":1}'
echo '['
echo '[],'

# Main loop
while :
do
    TIME="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[{\"full_text\":\"  $TIME\",\"color\":\"#FFFFFF\",\"name\":\"time\"}],"
    sleep 1
done
