#!/usr/bin/env bash
set -euo pipefail

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

PREFERRED_IFACE=""
WIFI_SLOT=0
IFACE=""
WIFI_IFACES=() NETS=() NMCLI_FIELDS=()
PID_FILE=""

while (( $# )); do
  case "$1" in
    -1|-2) WIFI_SLOT="${1#-}"; shift;;
    --preferred-interface)
      [[ $# -ge 2 ]] || { echo 'Missing interface after --preferred-interface' >&2; exit 2; }
      PREFERRED_IFACE="$2"; shift 2;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done

paint_background() { printf '%b\033[2J\033[H' "$C_BG"; }
draw_button() { printf '%b‹%b  %s  %b%b›%b' "$C_GLOW" "$C_BUTTON" "$1" "$C_RESET" "$C_GLOW" "$C_RESET"; }

parse_nmcli_fields() {
  local row="$1" char escaped=0 field="" i
  NMCLI_FIELDS=()
  for ((i=0; i<${#row}; i++)); do
    char="${row:i:1}"
    if (( escaped )); then
      field+="$char"; escaped=0
    elif [[ "$char" == $'\\' ]]; then
      escaped=1
    elif [[ "$char" == ':' ]]; then
      NMCLI_FIELDS+=("$field"); field=""
    else
      field+="$char"
    fi
  done
  if (( escaped )); then field+=$'\\'; fi
  NMCLI_FIELDS+=("$field")
}

parse_wifi_row() {
  parse_nmcli_fields "$1"
  (( ${#NMCLI_FIELDS[@]} >= 3 )) || return 1
  WIFI_SSID="${NMCLI_FIELDS[0]}"
  WIFI_SIGNAL="${NMCLI_FIELDS[1]}"
  WIFI_SECURITY="${NMCLI_FIELDS[2]}"
  [[ -n "$WIFI_SSID" && "$WIFI_SIGNAL" =~ ^[0-9]+$ ]]
}

discover_wifi_interfaces() {
  local row
  WIFI_IFACES=()
  while IFS= read -r row; do
    parse_nmcli_fields "$row"
    (( ${#NMCLI_FIELDS[@]} >= 2 )) || continue
    if [[ "${NMCLI_FIELDS[1]}" == wifi ]]; then WIFI_IFACES+=("${NMCLI_FIELDS[0]}"); fi
  done < <(nmcli -t --escape yes -f DEVICE,TYPE device status 2>/dev/null || true)
}

connection_profile_for_ssid() {
  local row name type ssid
  while IFS= read -r row; do
    parse_nmcli_fields "$row"
    (( ${#NMCLI_FIELDS[@]} >= 2 )) || continue
    name="${NMCLI_FIELDS[0]}"; type="${NMCLI_FIELDS[1]}"
    [[ "$type" == 802-11-wireless ]] || continue
    ssid="$(nmcli -g 802-11-wireless.ssid connection show "$name" 2>/dev/null || true)"
    if [[ "$ssid" == "$1" ]]; then printf '%s\n' "$name"; return 0; fi
  done < <(nmcli -t --escape yes -f NAME,TYPE connection show 2>/dev/null || true)
  return 1
}

cleanup() {
  [[ -z "$PID_FILE" ]] || rm -f -- "$PID_FILE"
  printf '\033[0m'
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM

command -v nmcli >/dev/null 2>&1 || { printf '%bNetworkManager (nmcli) is unavailable.%b\n' "$C_ERROR" "$C_RESET"; exit 1; }
discover_wifi_interfaces
if (( ${#WIFI_IFACES[@]} == 0 )); then printf '%bNo wireless interface found.%b\n' "$C_ERROR" "$C_RESET"; exit 1; fi

if [[ -n "$PREFERRED_IFACE" ]]; then
  IFACE="$PREFERRED_IFACE"
elif (( WIFI_SLOT > 0 )); then
  if (( WIFI_SLOT <= ${#WIFI_IFACES[@]} )); then IFACE="${WIFI_IFACES[$((WIFI_SLOT - 1))]}"; fi
else
  IFACE="${WIFI_IFACES[0]}"
fi
if [[ -z "$IFACE" ]] || ! printf '%s\n' "${WIFI_IFACES[@]}" | grep -qxF -- "$IFACE"; then
  printf '%bRequested Wi-Fi interface was not found: %s%b\n' "$C_ERROR" "${PREFERRED_IFACE:-slot $WIFI_SLOT}" "$C_RESET"
  exit 1
fi

PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/wifi_menu-${UID:-$(id -u)}-${IFACE}.pid"
if [[ -r "$PID_FILE" ]]; then
  OLD_PID="$(<"$PID_FILE")"
  if [[ "$OLD_PID" =~ ^[0-9]+$ ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null || true
    sleep 0.2
    kill -9 "$OLD_PID" 2>/dev/null || true
  fi
fi
printf '%s\n' "$$" > "$PID_FILE"

while true; do
  paint_background
  WIFI_STATE="$(nmcli radio wifi 2>/dev/null || printf disabled)"
  printf '%b====================================================%b\n' "$C_LINE" "$C_RESET"
  printf ' %b%sWiFi Controller%b\n' "$C_BOLD" "$C_HEADER" "$C_RESET"
  printf ' %bInterface :%b %b%s%b\n' "$C_LABEL" "$C_RESET" "$C_VALUE" "$IFACE" "$C_RESET"
  printf ' %bStatus    :%b %b%s%b\n' "$C_LABEL" "$C_RESET" "$C_VALUE" "$WIFI_STATE" "$C_RESET"
  printf '%b====================================================%b\n\n' "$C_LINE" "$C_RESET"

  if [[ "$WIFI_STATE" != enabled ]]; then
    printf '%b[!] WiFi is OFF%b\n' "$C_WARN" "$C_RESET"
    read -rp 'Select (open/exit): ' CMD || exit 0
    case "$CMD" in
      open) nmcli radio wifi on; printf '%b[+] WiFi turned ON%b\n' "$C_OK" "$C_RESET"; sleep 1; continue;;
      exit|q) exit 0;;
      *) continue;;
    esac
  fi

  printf '%b[*] Scanning WiFi networks...%b\n' "$C_DIM" "$C_RESET"
  mapfile -t NETS < <(nmcli -t --escape yes -f SSID,SIGNAL,SECURITY device wifi list ifname "$IFACE" --rescan yes 2>/dev/null | awk '!seen[$0]++')

  printf '\n%bAvailable WiFi networks:%b\n' "$C_HEADER" "$C_RESET"
  printf '%b------------------------------------%b\n' "$C_LINE" "$C_RESET"
  for i in "${!NETS[@]}"; do
    parse_wifi_row "${NETS[$i]}" || continue
    SEC="${WIFI_SECURITY:-}"
    [[ -n "$SEC" && "$SEC" != -- ]] || SEC=OPEN
    draw_button "$((i + 1))"
    printf ' %b%s%b %b(%s%%)%b %b[%s]%b\n' \
      "$C_VALUE" "$WIFI_SSID" "$C_RESET" "$C_OK" "$WIFI_SIGNAL" "$C_RESET" "$C_DIM" "$SEC" "$C_RESET"
  done
  printf '%b------------------------------------%b\n' "$C_LINE" "$C_RESET"
  printf '%bnumber | close | exit%b\n' "$C_DIM" "$C_RESET"

  while true; do
    read -rp 'Select: ' INPUT || exit 0
    case "$INPUT" in
      exit|q) exit 0;;
      close)
        nmcli radio wifi off
        printf '%b[+] WiFi turned OFF%b\n' "$C_OK" "$C_RESET"
        sleep 1
        continue 2;;
    esac
    if [[ "$INPUT" =~ ^[0-9]+$ ]] && (( INPUT >= 1 && INPUT <= ${#NETS[@]} )); then break; fi
    printf '%bInvalid input%b\n' "$C_ERROR" "$C_RESET"
  done

  parse_wifi_row "${NETS[$((INPUT - 1))]}" || { printf '%bInvalid network row%b\n' "$C_ERROR" "$C_RESET"; continue; }
  SSID="$WIFI_SSID"; SEC="$WIFI_SECURITY"
  printf '\n%b[*] Connecting to:%b %b%s%b\n' "$C_DIM" "$C_RESET" "$C_VALUE" "$SSID" "$C_RESET"
  KNOWN="$(connection_profile_for_ssid "$SSID" || true)"
  if [[ -n "$KNOWN" ]]; then
    printf '%b[+] Saved profile: %s%b\n' "$C_OK" "$KNOWN" "$C_RESET"
    if nmcli --wait 30 connection up "$KNOWN" ifname "$IFACE"; then CONNECTED=1; else CONNECTED=0; fi
  elif [[ -z "$SEC" || "$SEC" == -- ]]; then
    if nmcli --wait 30 device wifi connect "$SSID" ifname "$IFACE"; then CONNECTED=1; else CONNECTED=0; fi
  else
    printf '%b[!] Password required%b\n' "$C_WARN" "$C_RESET"
    read -rsp 'Password: ' PASS || exit 0
    printf '\n'
    if nmcli --wait 30 device wifi connect "$SSID" ifname "$IFACE" password "$PASS"; then CONNECTED=1; else CONNECTED=0; fi
    PASS=''
  fi

  if (( CONNECTED == 1 )); then printf '%b[+] CONNECTION SUCCESS%b\n' "$C_OK" "$C_RESET"; else printf '%b[-] CONNECTION FAILED%b\n' "$C_ERROR" "$C_RESET"; fi
  printf '\n'
  nmcli -t --escape yes -f ACTIVE,SSID device wifi list ifname "$IFACE" 2>/dev/null | awk -F: '$1=="yes" {print "yes:" $2}' || true
  printf '\n'
  read -rp 'Press Enter to continue or type exit: ' NEXT || exit 0
  [[ "$NEXT" == exit ]] && exit 0
done
