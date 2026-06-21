#!/bin/bash

# =========================
# INSTALL DEPENDENCY
# =========================
if ! command -v bluetoothctl &>/dev/null; then
  echo "[*] Installing Bluetooth..."
  sudo apt update -y
  sudo apt install -y bluez
fi

sudo systemctl start bluetooth >/dev/null 2>&1

# =========================
# EXIT
# =========================
quit() {
  echo "[*] Exiting..."
  exit 0
}

# =========================
# FIX BLUETOOTH POWER ON
# =========================
enable_bluetooth() {
  echo "[*] Enabling Bluetooth..."

  rfkill unblock bluetooth
  sudo systemctl restart bluetooth >/dev/null 2>&1
  sleep 1

  bluetoothctl power on >/dev/null 2>&1
  sleep 1

  bluetoothctl power on >/dev/null 2>&1

  if bluetoothctl show | grep -q "Powered: yes"; then
    echo "[+] Bluetooth READY"
  else
    echo "[-] Bluetooth FAILED"
  fi
}

# =========================
# SCAN FUNCTION
# =========================
scan_devices() {
  clear
  echo "[*] Scanning for devices (5–7 sec)..."

  bluetoothctl agent on >/dev/null 2>&1
  bluetoothctl default-agent >/dev/null 2>&1

  bluetoothctl scan on >/dev/null 2>&1 &
  sleep 6
  bluetoothctl scan off >/dev/null 2>&1

  echo ""
  echo "Available Devices:"
  echo "------------------------------------"
  bluetoothctl devices | nl -w2 -s") "
  echo "------------------------------------"
}

# =========================
# CONNECT FUNCTION (RETRY LOGIC)
# =========================
connect_device() {

  DEVICE=$(bluetoothctl devices | sed -n "${1}p")
  MAC=$(echo "$DEVICE" | awk '{print $2}')
  NAME=$(echo "$DEVICE" | cut -d' ' -f3-)

  if [[ -z "$MAC" ]]; then
    echo "Invalid device"
    return
  fi

  echo "[*] Device: $NAME ($MAC)"

  # check paired memory
  PAIRED=$(bluetoothctl paired-devices | grep "$MAC")

  if [[ -z "$PAIRED" ]]; then
    echo "[*] New device → pairing..."
    bluetoothctl pair "$MAC" >/dev/null 2>&1
    bluetoothctl trust "$MAC" >/dev/null 2>&1
  else
    echo "[*] Known device → using saved pairing"
  fi

  # =========================
  # CONNECT TRY FUNCTION
  # =========================
  try_connect() {
    bluetoothctl connect "$MAC" >/dev/null 2>&1
    sleep 2

    bluetoothctl info "$MAC" | grep -q "Connected: yes"
  }

  echo "[*] Connecting..."

  # FIRST TRY
  if try_connect; then
    echo "[+] CONNECTION SUCCESS"
    exit 0
  fi

  echo "[-] First attempt failed, retrying..."

  sleep 2

  # SECOND TRY
  if try_connect; then
    echo "[+] CONNECTION SUCCESS (retry)"
    exit 0
  fi

  # FAIL → BACK TO SCAN
  echo "[-] CONNECTION FAILED"
  echo "[*] Returning to scan..."
  sleep 2

  scan_devices
}

# =========================
# STARTUP CHECK
# =========================
STATE=$(bluetoothctl show | grep "Powered" | awk '{print $2}')

if [[ "$STATE" != "yes" ]]; then
  echo "Bluetooth is OFF"
  read -rp "Type open or exit: " CMD

  [[ "$CMD" == "exit" ]] && quit

  if [[ "$CMD" == "open" ]]; then
    enable_bluetooth
    scan_devices
  else
    quit
  fi
else
  enable_bluetooth
  scan_devices
fi

# =========================
# MAIN LOOP
# =========================
while true; do

  echo ""
  echo "Commands: <number> | rescan | open | close | exit"
  read -rp "Select : " INPUT

  [[ "$INPUT" == "exit" ]] && quit

  if [[ "$INPUT" == "open" ]]; then
    enable_bluetooth
    scan_devices
    continue
  fi

  if [[ "$INPUT" == "close" ]]; then
    bluetoothctl power off
    echo "[+] Bluetooth OFF"
    continue
  fi

  if [[ "$INPUT" == "rescan" ]]; then
    scan_devices
    continue
  fi

  if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
    connect_device "$INPUT"
    continue
  fi

  echo "Invalid input"
done