#!/usr/bin/env bash

set -euo pipefail

# Soft blue-black surface with cool gray text, lilac buttons, and warm orange
# highlights. Bold accent edges give the terminal buttons a subtle glow.
C_RESET=$'\033[0m\033[48;2;20;27;40m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_HEADER=$'\033[1;38;2;193;181;230m'
C_LINE=$'\033[38;2;79;96;122m'
C_OK=$'\033[38;2;172;190;205m'
C_WARN=$'\033[1;38;2;235;169;112m'
C_ERROR=$'\033[1;38;2;224;139;151m'
C_VALUE=$'\033[38;2;224;228;237m'
C_LABEL=$'\033[38;2;151;164;184m'
C_BUTTON=$'\033[1;38;2;25;31;45;48;2;174;161;218m'
C_GLOW=$'\033[1;38;2;246;190;132m'
C_BG=$'\033[48;2;20;27;40m'

PID_FILE="/tmp/wifi_menu.pid"

cleanup() {
  rm -f "$PID_FILE"
  printf '\033[0m'
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM

paint_background() {
  printf '%b\033[2J\033[H' "$C_BG"
}

draw_button() {
  printf '%b‹%b  %s  %b%b›%b' "$C_GLOW" "$C_BUTTON" "$1" "$C_RESET" "$C_GLOW" "$C_RESET"
}

parse_wifi_row() {
  local row="$1" field
  local -a fields=()
  IFS=: read -r -a fields <<< "$row"
  (( ${#fields[@]} >= 3 )) || return 1

  WIFI_SECURITY="${fields[${#fields[@]}-1]}"
  WIFI_SIGNAL="${fields[${#fields[@]}-2]}"
  WIFI_SSID="${fields[0]}"
  for field in "${fields[@]:1:${#fields[@]}-3}"; do
    WIFI_SSID+=":$field"
  done
  [[ -n "$WIFI_SSID" && "$WIFI_SIGNAL" =~ ^[0-9]+$ ]]
}

connection_profile_for_ssid() {
  local row name type field
  while IFS= read -r row; do
    local -a fields=()
    IFS=: read -r -a fields <<< "$row"
    (( ${#fields[@]} >= 2 )) || continue
    type="${fields[${#fields[@]}-1]}"
    [[ "$type" == wifi ]] || continue
    name="${fields[0]}"
    for field in "${fields[@]:1:${#fields[@]}-2}"; do
      name+=":$field"
    done
    [[ "$name" == "$1" ]] && { printf '%s\n' "$name"; return 0; }
  done < <(nmcli -t --escape no -f NAME,TYPE connection show 2>/dev/null || true)
  return 1
}

# ─────────────────────────────────────────────
# KILL OLD INSTANCE (IMPORTANT FIX)
# ─────────────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"

  if [[ -n "${OLD_PID:-}" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null || true
    sleep 0.2
    kill -9 "$OLD_PID" 2>/dev/null || true
  fi
fi

echo "$$" > "$PID_FILE"

# ─────────────────────────────────────────────
# CHECK WIFI DEVICE
# ─────────────────────────────────────────────
IFACE="$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi" {print $1; exit}')"

if [[ -z "$IFACE" ]]; then
  echo -e "${C_ERROR}No wireless interface found.${C_RESET}"
  exit 1
fi

# ─────────────────────────────────────────────
# MAIN LOOP
# ─────────────────────────────────────────────
while true; do
  paint_background

  WIFI_STATE="$(nmcli radio wifi || echo disabled)"

  echo -e "${C_LINE}====================================================${C_RESET}"
  echo -e " ${C_BOLD}${C_HEADER}WiFi Controller${C_RESET}"
  echo -e " ${C_LABEL}Interface :${C_RESET} ${C_VALUE}$IFACE${C_RESET}"
  echo -e " ${C_LABEL}Status    :${C_RESET} ${C_VALUE}$WIFI_STATE${C_RESET}"
  echo -e "${C_LINE}====================================================${C_RESET}"
  echo ""

  # ─────────────────────────────────────────────
  # WIFI OFF MODE
  # ─────────────────────────────────────────────
  if [[ "$WIFI_STATE" == "disabled" ]]; then
    echo -e "${C_WARN}[!] WiFi is OFF${C_RESET}"
    read -rp "Select (open/exit): " CMD || exit 0

    case "$CMD" in
      exit)
        exit 0
        ;;
      open)
        nmcli radio wifi on
        echo -e "${C_OK}[+] WiFi turned ON${C_RESET}"
        sleep 1
        continue
        ;;
      *)
        continue
        ;;
    esac
  fi

  # ─────────────────────────────────────────────
  # SCAN NETWORKS
  # ─────────────────────────────────────────────
  echo -e "${C_DIM}[*] Scanning WiFi networks...${C_RESET}"
  mapfile -t NETS < <(
    nmcli -t --escape no -f SSID,SIGNAL,SECURITY dev wifi list --rescan yes |
    awk -F: 'NF>=3 && $1!="" && $2 ~ /^[0-9]+$/ {print}' |
    awk '!seen[$0]++'
  )

  echo ""
  echo -e "${C_HEADER}Available WiFi networks:${C_RESET}"
  echo -e "${C_LINE}------------------------------------${C_RESET}"

  for i in "${!NETS[@]}"; do
    parse_wifi_row "${NETS[$i]}" || continue
    SSID="$WIFI_SSID"
    SIGNAL="$WIFI_SIGNAL"
    SEC="$WIFI_SECURITY"
    [[ -z "${SEC:-}" ]] && SEC="OPEN"

    draw_button "$((i+1))"
    printf " %b%s%b %b(%s%%)%b %b[%s]%b\n" \
      "$C_VALUE" "$SSID" "$C_RESET" \
      "$C_OK" "$SIGNAL" "$C_RESET" \
      "$C_DIM" "$SEC" "$C_RESET"
  done

  echo -e "${C_LINE}------------------------------------${C_RESET}"
  echo -e "${C_DIM}number | close | exit${C_RESET}"

  # ─────────────────────────────────────────────
  # USER INPUT
  # ─────────────────────────────────────────────
  INPUT=""

  while true; do
    read -rp "Select: " INPUT || exit 0

    [[ "$INPUT" == "exit" ]] && exit 0

    if [[ "$INPUT" == "close" ]]; then
      nmcli radio wifi off
      echo -e "${C_OK}[+] WiFi turned OFF${C_RESET}"
      sleep 1
      continue 2
    fi

    if [[ "$INPUT" =~ ^[0-9]+$ ]] && \
       [[ "$INPUT" -ge 1 ]] && \
       [[ "$INPUT" -le "${#NETS[@]}" ]]; then
      break
    fi

    echo -e "${C_ERROR}Invalid input${C_RESET}"
  done

  INDEX=$((INPUT - 1))
  SELECTED="${NETS[$INDEX]}"
  IFS=: read -r SSID SIGNAL SEC <<< "$SELECTED"

  echo ""
  echo -e "${C_DIM}[*] Connecting to:${C_RESET} ${C_VALUE}$SSID${C_RESET}"

  # ─────────────────────────────────────────────
  # CONNECT
  # ─────────────────────────────────────────────
  KNOWN="$(connection_profile_for_ssid "$SSID" || true)"

  if [[ -n "$KNOWN" ]]; then
    echo -e "${C_OK}[+] Saved profile${C_RESET}"
    if nmcli --wait 30 dev wifi connect "$SSID" ifname "$IFACE"; then
      CONNECTED=1
    else
      CONNECTED=0
    fi
  else
    echo -e "${C_WARN}[!] Password required${C_RESET}"
    read -rsp "Password: " PASS
    echo ""
    if nmcli --wait 30 dev wifi connect "$SSID" ifname "$IFACE" password "$PASS"; then
      CONNECTED=1
    else
      CONNECTED=0
    fi
  fi

  if (( CONNECTED == 1 )); then
    echo -e "${C_OK}[+] CONNECTION SUCCESS${C_RESET}"
  else
    echo -e "${C_ERROR}[-] CONNECTION FAILED${C_RESET}"
  fi

  echo ""
  nmcli -t -f ACTIVE,SSID dev wifi | grep '^yes:' || true

  echo ""
  read -rp "Press Enter to continue or type exit: " NEXT || exit 0
  [[ "$NEXT" == "exit" ]] && exit 0

done
