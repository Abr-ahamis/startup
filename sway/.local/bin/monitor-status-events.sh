#!/usr/bin/env bash
# Refresh network, Bluetooth, and battery blocks on kernel/D-Bus events.
set -u

[[ -n "${SWAYSOCK:-}" && -S "$SWAYSOCK" ]] || exit 0
[[ "${STARTUP_SWAY_PREVIEW:-0}" != 1 ]] || exit 0
command -v swaymsg >/dev/null 2>&1 || exit 0
command -v pkill >/dev/null 2>&1 || exit 0
swaymsg -s "$SWAYSOCK" -t get_version >/dev/null 2>&1 || exit 0

uid="${UID:-$(id -u)}"
runtime="${XDG_RUNTIME_DIR:-/run/user/$uid}"
[[ -d "$runtime" ]] || exit 0
exec 9>"$runtime/startup-status-events-$uid.lock" || exit 0
flock -n 9 || exit 0

watch_stream() {
  local mode="$1" signal="$2" event='' event_pid='' event_fd='' last_signal=-1
  local -a command=()
  case "$mode" in
    network)
      command -v nmcli >/dev/null 2>&1 || return 0
      command=(nmcli monitor)
      ;;
    bluetooth)
      command -v dbus-monitor >/dev/null 2>&1 || return 0
      command=(dbus-monitor --system "type='signal',sender='org.bluez'")
      ;;
    battery)
      command -v udevadm >/dev/null 2>&1 || return 0
      command=(udevadm monitor --kernel --subsystem-match=power_supply)
      ;;
    *) return 2 ;;
  esac

  coproc EVENT_STREAM { "${command[@]}" 2>/dev/null; }
  event_pid="${EVENT_STREAM_PID:-}"
  event_fd="${EVENT_STREAM[0]:-}"
  [[ -n "$event_pid" && "$event_fd" =~ ^[0-9]+$ ]] || return 0

  while [[ -S "$SWAYSOCK" ]] && kill -0 "$event_pid" 2>/dev/null; do
    if IFS= read -r -t 1 event <&"$event_fd"; then
      case "$mode:$event" in
        network:*connected*|network:*Connectivity*)
          rm -f -- "$runtime/i3blocks_public_ip_$uid" 2>/dev/null || true
          ;;
        bluetooth:signal\ *|battery:KERNEL\[*|network:*) ;;
        *) continue ;;
      esac
      if (( SECONDS != last_signal )); then
        pkill "-RTMIN+$signal" -u "$uid" -x i3blocks 2>/dev/null || true
        last_signal=$SECONDS
      fi
    fi
  done

  if kill -0 "$event_pid" 2>/dev/null; then
    kill -TERM "$event_pid" 2>/dev/null || true
    wait "$event_pid" 2>/dev/null || true
  fi
  if [[ "$event_fd" =~ ^[0-9]+$ ]]; then
    exec {event_fd}<&- 2>/dev/null || true
  fi
}

watch_stream network 13 &
watch_stream bluetooth 14 &
watch_stream battery 15 &
wait
