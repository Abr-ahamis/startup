#!/usr/bin/env bash
# main.sh - Menu to select tasks (i3/gnome/brave/vscode/telegram/virtualbox/protonvpn)
# ============================================================
# This script includes ALL of the requested behavior:
# ✔ All choices start at 0
# ✔ NO Up/Down navigation
# ✔ NO Enter toggle
# ✔ Only numbers 1–7 toggle
# ✔ 'c' = continue, 'q' = quit
# ✔ Interface exactly like your design
# ============================================================

set -euo pipefail

# ===========================
#        COLOR CODES
# ===========================
RED="\033[91m"
GREEN="\033[92m"
YELLOW="\033[93m"
CYAN="\033[96m"
RESET="\033[0m"
BOLD="\033[1m"

# ===========================
#        ROOT CHECK
# ===========================
ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}⚠ This script requires root privileges. Prompting for sudo...${RESET}"
        exec sudo bash "$0" "$@"
        exit 0
    fi
}

# ===========================
#   RECURSIVE CHMOD +X
# ===========================
run_chmod() {
    echo -e "${YELLOW}⚙ Setting execute permissions recursively...${RESET}"
    find . -type f \( -name "*.sh" -o -name "*.py" -o ! -name "*.*" \) -exec chmod +x {} \;
    echo -e "${GREEN}✅ Executable permissions applied.${RESET}"
}

# ===========================
#        TASK MENU
# ===========================
TASKS=("i3" "gnome" "brave" "vscode" "telegram" "virtualbox" "protonvpn")
# All choices start at 0 (unchecked)
CHECKED=(0 0 0 0 0 0 0)

draw_screen() {
    clear
    echo "====================="
    echo "  Select Tasks to Run"
    echo "====================="
    for i in "${!TASKS[@]}"; do
        [[ ${CHECKED[$i]} -eq 1 ]] && box="[x]" || box="[ ]"
        echo "  $box $((i+1)). ${TASKS[$i]}"
    done
    echo "====================="
    echo "Press number (1-7) to toggle"
    echo "Press 'c' to continue, 'q' to quit"
    echo "====================="
}

# ===========================
#          MENU LOOP
# ===========================
menu_loop() {
    draw_screen
    while true; do
        # read a single key silently
        IFS= read -rsn1 key || true

        case "$key" in
            [1-7])
                idx=$((key - 1))
                CHECKED[$idx]=$((1 - CHECKED[$idx]))
                ;;
            c|C)
                echo -e "${GREEN}\nContinuing...${RESET}"
                break
                ;;
            q|Q)
                echo -e "${YELLOW}\nQuit.${RESET}"
                exit 0
                ;;
            *)
                # any other key -> ignore (no Enter/arrow behavior)
                ;;
        esac

        draw_screen
    done
}

# ===========================
#     AFTER CONTINUE
# ===========================
after_continue() {
    echo
    echo "Selected tasks:"
    any=0
    for i in "${!TASKS[@]}"; do
        if [[ ${CHECKED[$i]} -eq 1 ]]; then
            echo " - ${TASKS[$i]}"
            any=1
        fi
    done
    [[ $any -eq 0 ]] && echo " (none)"

    # Placeholder: add task-specific actions here if you want them to run automatically.
    # Example:
    # for i in "${!TASKS[@]}"; do
    #   if [[ ${CHECKED[$i]} -eq 1 ]]; then
    #       case "${TASKS[$i]}" in
    #           "i3") /path/to/i3-setup.sh ;;
    #           "brave") /path/to/brave-install.sh ;;
    #           ...
    #       esac
    #   fi
    # done

    echo
    read -rp "Press Enter to exit..."
}

# ===========================
#            RUN
# ===========================
ensure_root "$@"
run_chmod
menu_loop
after_continue
exit 0
