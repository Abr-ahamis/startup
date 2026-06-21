#!/bin/bash

IFACE=$(nmcli -t -f DEVICE device status | grep -E '^wl' | head -n 1)

if [[ -z "$IFACE" ]]; then
  echo "No wireless interface found."
  exit 1
fi

while true; do
  clear

  WIFI_STATE=$(nmcli radio wifi)

  echo "===================================================="
  echo " WiFi Controller"
  echo " Interface : $IFACE"
  echo " Status    : $WIFI_STATE"
  echo "===================================================="
  echo ""

  # EXIT shortcut
  #echo "Type 'exit' anytime to close everything"

  # WIFI OFF
  if [[ "$WIFI_STATE" == "disabled" ]]; then
    echo "[!] WiFi is OFF"
    read -rp "Select : " CMD

    if [[ "$CMD" == "exit" ]]; then
      exit 0
    elif [[ "$CMD" == "open" ]]; then
      nmcli radio wifi on
      echo "[+] WiFi turned ON"
      sleep 1
      continue
    else
      continue
    fi
  fi

  # SCAN
  echo "[*] Scanning for WiFi networks..."
  nmcli dev wifi rescan >/dev/null 2>&1
  sleep 2

  mapfile -t NETS < <(
    nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list | awk -F: 'NF>=2 && $1!=""'
  )

  echo ""
  echo "Available WiFi networks:"
  echo "------------------------------------"

  for i in "${!NETS[@]}"; do
    SSID=$(echo "${NETS[$i]}" | cut -d':' -f1)
    SIGNAL=$(echo "${NETS[$i]}" | cut -d':' -f2)
    SEC=$(echo "${NETS[$i]}" | cut -d':' -f3)

    [[ -z "$SEC" ]] && SEC="OPEN"

    printf "%d) %s (%s%%) [%s]\n" "$((i+1))" "$SSID" "$SIGNAL" "$SEC"
  done

  echo "------------------------------------"
  echo "Type number / 'close' / 'exit'"

  while true; do
    read -rp "Select : " INPUT

    # EXIT FULL SYSTEM
    if [[ "$INPUT" == "exit" ]]; then
      echo "[*] Exiting..."
      exit 0
    fi

    # TURN WIFI OFF
    if [[ "$INPUT" == "close" ]]; then
      nmcli radio wifi off
      echo "[+] WiFi turned OFF"
      sleep 1
      break
    fi

    # VALID NUMBER
    if [[ "$INPUT" =~ ^[0-9]+$ ]] && \
       [ "$INPUT" -ge 1 ] && \
       [ "$INPUT" -le "${#NETS[@]}" ]; then
      break
    fi

    echo "Invalid input."
  done

  [[ "$INPUT" == "close" ]] && continue

  INDEX=$((INPUT - 1))
  SELECTED="${NETS[$INDEX]}"

  SSID=$(echo "$SELECTED" | cut -d':' -f1)
  SEC=$(echo "$SELECTED" | cut -d':' -f3)

  echo ""
  echo "[*] Connecting to: $SSID"

  # CHECK SAVED CONNECTION
  KNOWN=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="wifi"{print $1}' | grep -Fx "$SSID")

  if [[ -n "$KNOWN" ]]; then
    echo "[✓] Saved network detected (auto password exists)"
    echo "[*] Connecting using saved profile..."
    nmcli dev wifi connect "$SSID"
  else
    echo "[!] New network (password required)"
    if [[ "$SEC" != "--" && -n "$SEC" ]]; then
      read -rsp "Enter password: " PASS
      echo ""
      nmcli dev wifi connect "$SSID" password "$PASS"
    else
      nmcli dev wifi connect "$SSID"
    fi
  fi

  echo ""

  if [ $? -eq 0 ]; then
    echo "[+] CONNECTION SUCCESS"
  else
    echo "[-] CONNECTION FAILED"
  fi

  echo ""
  nmcli -t -f ACTIVE,SSID dev wifi | grep yes

  echo ""

  # 🔥 AUTO CLOSE TERMINAL OPTION
  echo "Closing terminal..."
  sleep 1

  # This works if script is run directly in terminal
  exit 0
done