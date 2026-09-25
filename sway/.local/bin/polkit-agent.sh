#!/usr/bin/env bash
set -u

for agent in \
  /usr/libexec/polkit-mate-authentication-agent-1 \
  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
  /usr/lib/polkit-gnome-authentication-agent-1; do
  [[ -x "$agent" ]] || continue
  pgrep -f -- "$agent" >/dev/null 2>&1 && exit 0
  exec "$agent"
done
exit 0
