#!/bin/bash

# =========================
# EXIT FUNCTION
# =========================
quit() {
  echo "[*] Closing Power Menu..."
  exit 0
}

# =========================
# SPEED INFO
# =========================
show_speed() {
  clear
  echo "=============================="
  echo " SYSTEM SPEED INFO"
  echo "=============================="

  echo ""
  echo "[CPU]"
  echo "$(grep 'model name' /proc/cpuinfo | head -n 1 | cut -d':' -f2)"

  echo ""
  echo "[Load]"
  uptime

  echo ""
  echo "[Memory]"
  free -h

  echo ""
  echo "[Disk]"
  df -h / | tail -n 1

  echo ""
  read -rp "Press Enter to return..."
}

# =========================
# POWER ACTIONS
# =========================
shutdown_system() {
  echo "[*] Shutting down..."
  sudo shutdown now
}

restart_system() {
  echo "[*] Restarting..."
  sudo reboot
}

logout_system() {
  echo "[*] Logging out..."

  # detect session type
  if [[ "$XDG_CURRENT_DESKTOP" == *"i3"* ]]; then
    i3-msg exit
  elif [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
    gnome-session-quit --logout --no-prompt
  else
    pkill -KILL -u "$USER"
  fi
}

# =========================
# MAIN LOOP
# =========================
while true; do
  clear

  echo "=============================="
  echo " POWER MENU"
  echo "=============================="
  echo "1) Shutdown"
  echo "2) Restart"
  echo "3) Logout"
  echo "4) Speed Info"
  echo "5) Exit"
  echo "=============================="
  echo ""

  read -rp "Select : " INPUT

  case "$INPUT" in
    1)
      shutdown_system
      ;;
    2)
      restart_system
      ;;
    3)
      logout_system
      ;;
    4)
      show_speed
      ;;
    5|exit)
      quit
      ;;
    *)
      echo "Invalid option"
      sleep 1
      ;;
  esac
done