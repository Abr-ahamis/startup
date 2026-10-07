#!/usr/bin/env bash
# Keep Wofi menus single-instance and dismiss them when Sway focus moves away.
set -u

command -v wofi >/dev/null 2>&1 || exit 127
command -v swaymsg >/dev/null 2>&1 || exit 127
command -v jq >/dev/null 2>&1 || exit 127
command -v flock >/dev/null 2>&1 || exit 127

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
uid="${UID:-$(id -u)}"
pid_file="$runtime_dir/startup-wofi-$uid.pid"
lock_file="$runtime_dir/startup-wofi-$uid.lock"
mkdir -p -- "$runtime_dir" 2>/dev/null || exit 1
exec 9>"$lock_file" || exit 1
flock -x 9 || exit 1

old_pid="$(cat "$pid_file" 2>/dev/null || true)"
if [[ "$old_pid" =~ ^[0-9]+$ ]] && (( old_pid != $$ )) && kill -0 "$old_pid" 2>/dev/null; then
  old_command="$(tr '\0' ' ' <"/proc/$old_pid/cmdline" 2>/dev/null || true)"
  if [[ "$old_command" == *wofi-popup.sh* ]]; then
    kill -TERM "$old_pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$old_pid" 2>/dev/null || break
      sleep 0.05
    done
    kill -KILL "$old_pid" 2>/dev/null || true
  fi
fi
printf '%s\n' "$$" >"$pid_file"
flock -u 9

wofi_pid=""
cleanup() {
  trap - EXIT INT TERM HUP
  if [[ -n "$wofi_pid" ]] && kill -0 "$wofi_pid" 2>/dev/null; then
    kill -TERM "$wofi_pid" 2>/dev/null || true
    wait "$wofi_pid" 2>/dev/null || true
  fi
  [[ "$(cat "$pid_file" 2>/dev/null || true)" != "$$" ]] || rm -f -- "$pid_file"
}
trap cleanup EXIT
trap 'exit 0' INT TERM HUP

# A normal Sway window is required here: older Wofi releases do not implement
# close_on_focus_loss, so monitor Sway's focused window as a compatibility path.
# Background jobs in non-interactive Bash may get /dev/null as stdin unless
# the descriptor is explicit. Preserve dmenu pipelines (key help, power,
# clipboard) while keeping the focus watcher active.
wofi --normal-window --define close_on_focus_loss=true "$@" <&0 &
wofi_pid=$!
seen_focused=0

while kill -0 "$wofi_pid" 2>/dev/null; do
  tree="$(swaymsg -t get_tree -r 2>/dev/null || true)"
  if [[ -n "$tree" ]]; then
    focused="$(jq -r '[.. | objects | select(.app_id == "wofi" and .focused == true)] | length' <<<"$tree" 2>/dev/null || printf 0)"
    any_wofi="$(jq -r '[.. | objects | select(.app_id == "wofi")] | length' <<<"$tree" 2>/dev/null || printf 0)"
    if (( any_wofi > 0 && focused > 0 )); then
      seen_focused=1
    elif (( seen_focused )); then
      kill -TERM "$wofi_pid" 2>/dev/null || true
      break
    fi
  fi
  sleep 0.1
done

wait "$wofi_pid"
