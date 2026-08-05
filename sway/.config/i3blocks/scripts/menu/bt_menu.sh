#!/usr/bin/env bash
set -uo pipefail

SERVICE="bluetooth.service"
REFRESH_SECONDS=4
INITIAL_SCAN_SECONDS=5
CONNECT_RETRIES=2
CONNECT_WAIT_SECONDS=3
SCAN_ACTIVE=0
BLUETOOTH_CLOSED=0
BT_SCAN_PID=""
BT_SCAN_FD=""
DEVICE_LINES=()
CONNECTED_MAC=""

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_HEADER="\033[38;5;39m"
C_LINE="\033[38;5;59m"
C_OK="\033[38;5;82m"
C_WARN="\033[38;5;214m"
C_ERROR="\033[38;5;203m"
C_VALUE="\033[38;5;223m"

info() { echo -e "${C_DIM}[*] $*${C_RESET}"; }
ok()   { echo -e "${C_OK}[+] $*${C_RESET}"; }
warn() { echo -e "${C_WARN}[!] $*${C_RESET}"; }
fail() { echo -e "${C_ERROR}[-] $*${C_RESET}"; }
line() { echo -e "${C_LINE}------------------------------------${C_RESET}"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

add_missing_pkg() {
  local pkg="$1" item

  for item in "${missing[@]}"; do
    [[ "$item" == "$pkg" ]] && return 0
  done

  missing+=("$pkg")
}

run_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif [[ -t 0 ]]; then
    sudo "$@"
  else
    sudo -n "$@"
  fi
}

cleanup() {
  stop_scan >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

install_missing_tools() {
  local missing=()

  need_cmd bluetoothctl || add_missing_pkg "bluez"
  need_cmd btmgmt || add_missing_pkg "bluez"
  need_cmd rfkill || add_missing_pkg "rfkill"
  need_cmd systemctl || add_missing_pkg "systemd"

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  local package_manager=apt
  if need_cmd pacman; then
    package_manager=pacman
    for i in "${!missing[@]}"; do
      [[ "${missing[$i]}" == bluez ]] && missing[$i]=bluez-utils
    done
  fi
  if [[ "$package_manager" == apt ]] && ! need_cmd apt-get; then
    fail "No supported package manager found. Missing packages: ${missing[*]}"
    exit 1
  fi

  info "Installing missing packages: ${missing[*]}"
  if [[ "$package_manager" == pacman ]]; then
    run_sudo pacman -Sy --noconfirm
    run_sudo pacman -S --needed --noconfirm "${missing[@]}"
  else
    run_sudo apt-get update
    run_sudo apt-get install -y "${missing[@]}"
  fi
}

bt() {
  bluetoothctl "$@" 2>/dev/null
}

bt_batch() {
  bluetoothctl >/dev/null 2>&1
}

bt_with_timeout() {
  local seconds="$1"
  shift

  if need_cmd timeout; then
    timeout "$seconds" bluetoothctl "$@" 2>/dev/null
  else
    bluetoothctl "$@" 2>/dev/null
  fi
}

parse_devices() {
  awk '
    /^Device[[:space:]]+([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ {
      mac = $2
      name = ""
      for (i = 3; i <= NF; i++) {
        name = name (name == "" ? "" : " ") $i
      }
      if (name == "") name = mac
      print "Device " mac " " name
    }
  '
}

refresh_devices() {
  mapfile -t DEVICE_LINES < <(
    {
      bt devices
      bt devices Paired
      bt devices Connected
    } | parse_devices | awk 'NF >= 3 && !seen[$2]++'
  )
}

wait_for_discovery() {
  local waited=0

  while (( waited < INITIAL_SCAN_SECONDS )); do
    refresh_devices
    ((${#DEVICE_LINES[@]} > 0)) && return 0
    sleep 1
    ((waited++))
  done

  refresh_devices
}

connected_device() {
  bt devices Connected | parse_devices | awk 'NR == 1 {print $2; exit}'
}

is_connected() {
  [[ -n "$(connected_device)" ]]
}

scan_session_alive() {
  [[ -n "${BT_SCAN_PID:-}" ]] && kill -0 "$BT_SCAN_PID" 2>/dev/null
}

start_scan() {
  if [[ "$BLUETOOTH_CLOSED" -eq 1 ]]; then
    return 1
  fi

  if [[ "$SCAN_ACTIVE" -eq 1 ]] && scan_session_alive; then
    return 0
  fi

  if [[ -n "${BT_SCAN_FD:-}" ]]; then
    eval "exec ${BT_SCAN_FD}>&-" 2>/dev/null || true
    BT_SCAN_FD=""
  fi

  if [[ -n "${BT_SCAN_PID:-}" ]]; then
    kill "$BT_SCAN_PID" >/dev/null 2>&1 || true
    wait "$BT_SCAN_PID" 2>/dev/null || true
    BT_SCAN_PID=""
  fi

  coproc BT_SCAN_SESSION { bluetoothctl >/dev/null 2>&1; }
  BT_SCAN_PID="$BT_SCAN_SESSION_PID"
  exec {BT_SCAN_FD}>&"${BT_SCAN_SESSION[1]}"
  exec {BT_SCAN_SESSION[1]}>&-

  printf '%s\n' \
    "power on" \
    "agent on" \
    "default-agent" \
    "pairable on" \
    "scan on" >&"$BT_SCAN_FD" || {
    fail "Could not start scan"
    if [[ -n "${BT_SCAN_FD:-}" ]]; then
      eval "exec ${BT_SCAN_FD}>&-" 2>/dev/null || true
      BT_SCAN_FD=""
    fi
    if [[ -n "${BT_SCAN_PID:-}" ]]; then
      kill "$BT_SCAN_PID" >/dev/null 2>&1 || true
      wait "$BT_SCAN_PID" 2>/dev/null || true
      BT_SCAN_PID=""
    fi
    SCAN_ACTIVE=0
    return 1
  }

  SCAN_ACTIVE=1
}

stop_scan() {
  if [[ -n "${BT_SCAN_FD:-}" ]]; then
    {
      printf '%s\n' "scan off" "quit" >&"$BT_SCAN_FD"
      eval "exec ${BT_SCAN_FD}>&-"
    } 2>/dev/null || true
    BT_SCAN_FD=""
  fi

  if [[ -n "${BT_SCAN_PID:-}" ]]; then
    wait "$BT_SCAN_PID" 2>/dev/null || kill "$BT_SCAN_PID" >/dev/null 2>&1 || true
    BT_SCAN_PID=""
  fi

  bt scan off >/dev/null 2>&1 || true
  if need_cmd timeout && need_cmd btmgmt; then
    timeout 2 btmgmt find off >/dev/null 2>&1 || true
  fi
  SCAN_ACTIVE=0
}

open_bluetooth() {
  info "Opening Bluetooth..."
  BLUETOOTH_CLOSED=0

  run_sudo systemctl enable "$SERVICE" >/dev/null 2>&1 || true
  run_sudo systemctl start "$SERVICE" >/dev/null 2>&1 || true
  run_sudo rfkill unblock bluetooth >/dev/null 2>&1 || true

  if ! systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
    run_sudo systemctl start "$SERVICE" >/dev/null 2>&1 || true
  fi

  sleep 1
  printf '%s\n' \
    "power on" \
    "agent on" \
    "default-agent" \
    "pairable on" | bt_batch || true

  if bt show | grep -q "Powered: yes"; then
    ok "Bluetooth is on"
    start_scan
    wait_for_discovery
  else
    fail "Bluetooth did not power on"
  fi
}

close_bluetooth() {
  info "Closing Bluetooth..."
  BLUETOOTH_CLOSED=1
  stop_scan
  while IFS= read -r mac; do
    [[ -n "$mac" ]] && bt disconnect "$mac" >/dev/null 2>&1 || true
  done < <(bt devices Connected | parse_devices | awk '{print $2}')
  printf '%s\n' \
    "discoverable off" \
    "pairable off" \
    "agent off" \
    "power off" | bt_batch || true
  bt power off >/dev/null 2>&1 || true
  run_sudo systemctl stop "$SERVICE" >/dev/null 2>&1 || true
  run_sudo rfkill block bluetooth >/dev/null 2>&1 || true
  ok "Bluetooth closed"
}

show_header() {
  clear
  echo -e "${C_LINE}====================================${C_RESET}"
  echo -e " ${C_BOLD}${C_HEADER}Bluetooth Menu${C_RESET}"
  echo -e "${C_LINE}====================================${C_RESET}"
}

show_status() {
  local active enabled powered discovering connected show_output

  active=$(systemctl is-active "$SERVICE" 2>/dev/null || echo "inactive")
  enabled=$(systemctl is-enabled "$SERVICE" 2>/dev/null || echo "disabled")
  show_output=$(bt show)
  powered=$(awk -F': ' '/Powered/ {print $2; exit}' <<<"$show_output")
  discovering=$(awk -F': ' '/Discovering/ {print $2; exit}' <<<"$show_output")
  connected=$(connected_device)

  echo -e "${C_DIM}[*] Service:${C_RESET} ${C_VALUE}${active} | ${enabled}${C_RESET}"
  echo -e "${C_DIM}[*] Powered:${C_RESET} ${C_VALUE}${powered:-unknown}${C_RESET}"
  echo -e "${C_DIM}[*] Scanning:${C_RESET} ${C_VALUE}${discovering:-unknown}${C_RESET}"

  if [[ -n "$connected" ]]; then
    echo -e "${C_DIM}[*] Connected:${C_RESET} ${C_VALUE}${connected}${C_RESET}"
  else
    echo -e "${C_DIM}[*] Connected:${C_RESET} ${C_VALUE}none${C_RESET}"
  fi
}

show_devices() {
  refresh_devices

  echo
  echo -e "${C_BOLD}${C_HEADER}Available Devices:${C_RESET}"
  line

  if ((${#DEVICE_LINES[@]} == 0)); then
    warn "No devices found yet."
  else
    local i item mac name mark
    for i in "${!DEVICE_LINES[@]}"; do
      item="${DEVICE_LINES[$i]}"
      mac=$(awk '{print $2}' <<<"$item")
      name=$(cut -d' ' -f3- <<<"$item")
      mark=""
      bt info "$mac" | grep -q "Connected: yes" && mark=" ${C_OK}[connected]${C_RESET}"
      printf "%b%2d)%b %s %b[%s]%b%b\n" \
        "$C_VALUE" $((i + 1)) "$C_RESET" "$name" "$C_DIM" "$mac" "$C_RESET" "$mark"
    done
  fi

  line
}

show_help() {
  echo
  echo -e "${C_BOLD}${C_HEADER}Commands:${C_RESET}"
  line
  echo -e "  ${C_OK}<number>${C_RESET}          connect to a listed device"
  echo -e "  ${C_OK}list${C_RESET}, ${C_OK}scan${C_RESET}        refresh devices and keep scanning"
  echo -e "  ${C_OK}disconnect${C_RESET}       disconnect the current device"
  echo -e "  ${C_OK}disconnect <n>${C_RESET}   disconnect listed device number n"
  echo -e "  ${C_OK}open${C_RESET}             unblock, start, and power on Bluetooth"
  echo -e "  ${C_OK}close${C_RESET}            power off, stop service, and block Bluetooth"
  echo -e "  ${C_OK}status${C_RESET}           show current Bluetooth status"
  echo -e "  ${C_OK}help${C_RESET}             show this help"
  echo -e "  ${C_OK}exit${C_RESET}             stop scanning and quit"
  line
}

draw() {
  show_header
  show_status
  show_devices

  if [[ "$BLUETOOTH_CLOSED" -eq 1 ]]; then
    info "Bluetooth is closed. Use open to start it again."
  elif is_connected; then
    info "Connected. Discovery is still active."
  else
    info "Scanning until the script exits or Bluetooth is closed."
  fi
}

auto_connect_paired() {
  local item mac name attempt

  if is_connected; then
    CONNECTED_MAC="$(connected_device)"
    start_scan
    return 0
  fi

  start_scan

  while IFS= read -r item; do
    mac=$(awk '{print $2}' <<<"$item")
    name=$(cut -d' ' -f3- <<<"$item")
    [[ -n "$mac" ]] || continue

    info "Trying paired device: $name ($mac)"
    bt trust "$mac" >/dev/null 2>&1 || true
    for ((attempt = 1; attempt <= CONNECT_RETRIES; attempt++)); do
      bt_with_timeout "$CONNECT_WAIT_SECONDS" connect "$mac" >/dev/null 2>&1 || true
      sleep 1

      if bt info "$mac" | grep -q "Connected: yes"; then
        CONNECTED_MAC="$mac"
        start_scan
        ok "Connected to $name"
        return 0
      fi
    done

    warn "Could not connect to $name"
  done < <(bt devices Paired | parse_devices)

  return 1
}

connect_number() {
  local index="$1" item mac name paired attempt

  refresh_devices
  if (( index < 1 || index > ${#DEVICE_LINES[@]} )); then
    fail "Invalid device number"
    return 1
  fi

  item="${DEVICE_LINES[$((index - 1))]}"
  mac=$(awk '{print $2}' <<<"$item")
  name=$(cut -d' ' -f3- <<<"$item")

  info "Selected: $name ($mac)"

  if bt info "$mac" | grep -q "Connected: yes"; then
    CONNECTED_MAC="$mac"
    start_scan
    ok "Already connected"
    return 0
  fi

  paired=$(bt info "$mac" | grep -c "Paired: yes" || true)
  if [[ "$paired" -eq 0 ]]; then
    info "Pairing..."
    bt pair "$mac" >/dev/null 2>&1 || warn "Pair command failed or needs confirmation"
  fi

  bt trust "$mac" >/dev/null 2>&1 || true

  info "Connecting..."
  for ((attempt = 1; attempt <= CONNECT_RETRIES; attempt++)); do
    bt_with_timeout "$CONNECT_WAIT_SECONDS" connect "$mac" >/dev/null 2>&1 || true
    sleep 1

    if bt info "$mac" | grep -q "Connected: yes"; then
      CONNECTED_MAC="$mac"
      start_scan
      ok "Connected to $name"
      return 0
    fi

    warn "Connection attempt $attempt failed"
  done

  fail "Connection failed"
  start_scan
  return 1
}

disconnect_current() {
  local target="${1:-}" mac

  if [[ -n "$target" && "$target" =~ ^[0-9]+$ ]]; then
    refresh_devices
    if (( target >= 1 && target <= ${#DEVICE_LINES[@]} )); then
      mac=$(awk '{print $2}' <<<"${DEVICE_LINES[$((target - 1))]}")
    fi
  fi

  [[ -n "${mac:-}" ]] || mac="$(connected_device)"

  if [[ -z "$mac" ]]; then
    warn "No connected device"
    start_scan
    return 0
  fi

  info "Disconnecting $mac"
  bt disconnect "$mac" >/dev/null 2>&1 || true
  CONNECTED_MAC=""
  start_scan
}

handle_command() {
  local input="$1"

  case "$input" in
    open)
      open_bluetooth
      ;;
    close)
      close_bluetooth
      ;;
    scan|rescan|list)
      BLUETOOTH_CLOSED=0
      start_scan
      ;;
    status)
      show_status
      read -rp "Press Enter..."
      ;;
    help|h|\?)
      show_help
      read -rp "Press Enter..."
      ;;
    disconnect|disc)
      disconnect_current
      ;;
    disconnect\ *|disc\ *)
      disconnect_current "${input#* }"
      ;;
    exit|quit|q)
      cleanup
      exit 0
      ;;
    "")
      ;;
    *[!0-9]*)
      fail "Invalid input"
      sleep 1
      ;;
    *)
      connect_number "$input"
      sleep 1
      ;;
  esac
}

main() {
  local input

  install_missing_tools
  open_bluetooth
  refresh_devices

  while true; do
    if [[ "$BLUETOOTH_CLOSED" -eq 0 ]]; then
      auto_connect_paired >/dev/null 2>&1 || start_scan
    fi

    draw
    echo
    echo -e "${C_DIM}Commands:${C_RESET} ${C_OK}<number>${C_RESET} | ${C_OK}list${C_RESET} | ${C_OK}disconnect${C_RESET} | ${C_OK}open${C_RESET} | ${C_OK}close${C_RESET} | ${C_OK}status${C_RESET} | ${C_OK}help${C_RESET} | ${C_OK}exit${C_RESET}"

    if read -t "$REFRESH_SECONDS" -rp "$(echo -e "${C_HEADER}Select:${C_RESET} ")" input; then
      handle_command "$input"
    fi
  done
}

main "$@"
