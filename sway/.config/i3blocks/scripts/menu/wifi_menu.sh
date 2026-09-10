#!/usr/bin/env bash

set -euo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_HEADER="\033[38;5;39m"
C_LINE="\033[38;5;59m"
C_OK="\033[38;5;82m"
C_WARN="\033[38;5;214m"
C_ERROR="\033[38;5;203m"
C_VALUE="\033[38;5;223m"
C_LABEL="\033[38;5;245m"

PID_FILE="/tmp/wifi_menu.pid"

cleanup() {
  rm -f "$PID_FILE"
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM

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
  clear

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
  nmcli dev wifi rescan >/dev/null 2>&1 || true
  sleep 2

  mapfile -t NETS < <(
    nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list |
    awk -F: 'NF>=2 && $1!=""'
  )

  echo ""
  echo -e "${C_HEADER}Available WiFi networks:${C_RESET}"
  echo -e "${C_LINE}------------------------------------${C_RESET}"

  for i in "${!NETS[@]}"; do
    IFS=: read -r SSID SIGNAL SEC <<< "${NETS[$i]}"
    [[ -z "${SEC:-}" ]] && SEC="OPEN"

    printf "%b%2d)%b %s %b(%s%%)%b %b[%s]%b\n" \
      "$C_VALUE" "$((i+1))" "$C_RESET" "$SSID" \
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
  KNOWN="$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="wifi"{print $1}' | grep -Fx "$SSID" || true)"

  if [[ -n "$KNOWN" ]]; then
    echo -e "${C_OK}[+] Saved profile${C_RESET}"
    nmcli dev wifi connect "$SSID" ifname "$IFACE"
  else
    echo -e "${C_WARN}[!] Password required${C_RESET}"
    read -rsp "Password: " PASS
    echo ""
    nmcli dev wifi connect "$SSID" ifname "$IFACE" password "$PASS"
  fi

  if [[ $? -eq 0 ]]; then
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