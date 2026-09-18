#!/usr/bin/env bash
set -euo pipefail

REFRESH=0

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_HEADER="\033[38;5;39m"
C_LINE="\033[38;5;59m"
C_OK="\033[38;5;82m"
C_WARN="\033[38;5;214m"
C_ERROR="\033[38;5;203m"
C_VALUE="\033[38;5;223m"

# =========================
# EXIT
# =========================
quit() {
  echo -e "${C_DIM}[*] Closing Power Menu...${C_RESET}"
  exit 0
}

# =========================
# SPEED INFO
# =========================
show_speed() {
  clear
  echo -e "${C_LINE}==============================${C_RESET}"
  echo -e " ${C_BOLD}${C_HEADER}SYSTEM INFO${C_RESET}"
  echo -e "${C_LINE}==============================${C_RESET}"

  echo ""
  echo -e "${C_HEADER}[CPU]${C_RESET}"
  grep "model name" /proc/cpuinfo | head -n 1 | cut -d':' -f2

  echo ""
  echo -e "${C_HEADER}[Load]${C_RESET}"
  uptime

  echo ""
  echo -e "${C_HEADER}[Memory]${C_RESET}"
  free -h

  echo ""
  echo -e "${C_HEADER}[Disk]${C_RESET}"
  df -h / | tail -n 1

  echo ""
  read -rp "$(echo -e "${C_DIM}Press Enter to return...${C_RESET}")"
}

# =========================
# POWER ACTIONS
# =========================
shutdown_system() {
  echo -e "${C_WARN}[*] Shutting down...${C_RESET}"
  sudo shutdown now
}

restart_system() {
  echo -e "${C_WARN}[*] Restarting...${C_RESET}"
  sudo reboot
}

sleep_system() {
  echo -e "${C_WARN}[*] Sleeping...${C_RESET}"
  systemctl suspend
}

logout_system() {
  echo -e "${C_WARN}[*] Logging out...${C_RESET}"

  if [[ "${XDG_CURRENT_DESKTOP:-}" == *"i3"* ]]; then
    i3-msg exit >/dev/null 2>&1 || true
  elif [[ "${XDG_CURRENT_DESKTOP:-}" == *"GNOME"* ]]; then
    gnome-session-quit --logout --no-prompt >/dev/null 2>&1 || true
  else
    pkill -KILL -u "$USER"
  fi
}

# =========================
# UI
# =========================
show_menu() {
  clear
  echo -e "${C_LINE}==============================${C_RESET}"
  echo -e " ${C_BOLD}${C_HEADER}POWER MENU${C_RESET}"
  echo -e "${C_LINE}==============================${C_RESET}"
  echo -e " ${C_VALUE}1)${C_RESET} Shutdown"
  echo -e " ${C_VALUE}2)${C_RESET} Restart"
  echo -e " ${C_VALUE}3)${C_RESET} Sleep"
  echo -e " ${C_VALUE}4)${C_RESET} Logout"
  echo -e " ${C_VALUE}5)${C_RESET} System Info"
  echo -e " ${C_VALUE}6)${C_RESET} Exit"
  echo -e "${C_LINE}==============================${C_RESET}"
  echo ""
  echo -e "${C_DIM}Commands:${C_RESET}"
  echo -e " ${C_OK}shutdown${C_RESET} | ${C_OK}restart${C_RESET} | ${C_OK}sleep${C_RESET} | ${C_OK}logout${C_RESET} | ${C_OK}info${C_RESET} | ${C_OK}exit${C_RESET}"
  echo ""
}

# =========================
# MAIN LOOP
# =========================
while true; do
  show_menu

  if read -rp "$(echo -e "${C_HEADER}Select${C_RESET} : ")" INPUT; then
    case "${INPUT,,}" in
      1|shutdown)
        shutdown_system
        ;;

      2|restart|reboot)
        restart_system
        ;;

      3|sleep|suspend)
        sleep_system
        ;;

      4|logout)
        logout_system
        ;;

      5|info|speed)
        show_speed
        ;;

      6|exit|quit|q)
        quit
        ;;

      *)
        echo -e "${C_ERROR}Invalid option${C_RESET}"
        sleep 1
        ;;
    esac
  fi
done