#!/usr/bin/env bash
set -euo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_HEADER="\033[38;5;39m"
C_LINE="\033[38;5;59m"
C_OK="\033[38;5;82m"
C_VALUE="\033[38;5;223m"
C_LABEL="\033[38;5;245m"

# =========================
# PUBLIC IP
# =========================
PUBLIC_IP="$(
  curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo "unavailable"
)"

# =========================
# DEFAULT INTERFACE
# =========================
DEFAULT_IFACE="$(
  ip route show default 2>/dev/null | awk '/default/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}'
)"

# =========================
# HEADER
# =========================
clear
echo -e "${C_LINE}====================================================${C_RESET}"
echo -e " ${C_BOLD}${C_HEADER}IP MENU${C_RESET}"
echo -e "${C_LINE}====================================================${C_RESET}"

echo -e "${C_LABEL}[Public IP]${C_RESET} ${C_OK}{${PUBLIC_IP}}${C_RESET}"
echo -e "${C_LABEL}[Interface]${C_RESET} ${C_OK}{${DEFAULT_IFACE:-none}}${C_RESET}"

echo -e "${C_LINE}----------------------------------------------------${C_RESET}"

# =========================
# INTERFACES + IPS
# =========================
while read -r line; do
  iface=$(echo "$line" | awk '{print $2}' | sed 's/://')
  state=$(ip -o link show "$iface" 2>/dev/null | awk -F'<' '{print $2}' | awk -F'>' '{print $1}')

  ips=$(ip -4 -o addr show "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | xargs)

  [[ -z "$ips" ]] && ips="no-ip"

  tag=""
  [[ "$iface" == "$DEFAULT_IFACE" ]] && tag="[default]"

  echo -e "${C_HEADER}${iface}${C_RESET} ${C_DIM}${tag}${C_RESET} ${C_LABEL}state:${C_RESET} ${C_VALUE}${state}${C_RESET}"
  echo -e "${C_OK}{ips : ${ips}}${C_RESET}"
  echo ""

done < <(ip -o link show)

echo -e "${C_LINE}----------------------------------------------------${C_RESET}"
echo -e "${C_DIM}SHIFT + SUPER + Q = close terminal${C_RESET}"

echo ""

# =========================
# LOOP (optional refresh / exit)
# =========================
while true; do
  read -rp "$(echo -e "${C_HEADER}command${C_RESET} ${C_DIM}(exit/refresh):${C_RESET} ")" cmd
  case "${cmd,,}" in
    exit|q)
      exit 0
      ;;
    refresh)
      exec "$0"
      ;;
  esac
done
