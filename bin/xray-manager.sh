#!/usr/bin/env bash

set -Eeuo pipefail

XRAY_SERVICE="xray"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

pause_screen() {
    echo
    read -r -p "Tekan Enter untuk kembali..."
}

xray_status() {
    if systemctl is-active --quiet "$XRAY_SERVICE"; then
        echo -e "${GREEN}ON${RESET}"
    else
        echo -e "${RED}OFF${RESET}"
    fi
}

start_xray() {
    echo
    echo "Starting Xray..."
    systemctl start "$XRAY_SERVICE"

    if systemctl is-active --quiet "$XRAY_SERVICE"; then
        echo -e "${GREEN}Xray berhasil START.${RESET}"
    else
        echo -e "${RED}Xray gagal START.${RESET}"
        systemctl status "$XRAY_SERVICE" --no-pager -l || true
    fi

    pause_screen
}

stop_xray() {
    echo
    echo "Stopping Xray..."
    systemctl stop "$XRAY_SERVICE"

    if systemctl is-active --quiet "$XRAY_SERVICE"; then
        echo -e "${RED}Xray masih berjalan.${RESET}"
    else
        echo -e "${GREEN}Xray berhasil STOP.${RESET}"
    fi

    pause_screen
}

restart_xray() {
    echo
    echo "Restarting Xray..."
    systemctl restart "$XRAY_SERVICE"

    if systemctl is-active --quiet "$XRAY_SERVICE"; then
        echo -e "${GREEN}Xray berhasil RESTART.${RESET}"
    else
        echo -e "${RED}Xray gagal RESTART.${RESET}"
        systemctl status "$XRAY_SERVICE" --no-pager -l || true
    fi

    pause_screen
}

show_status() {
    echo
    systemctl status "$XRAY_SERVICE" --no-pager -l || true
    pause_screen
}

test_config() {
    echo
    echo "Testing Xray configuration..."
    echo

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo -e "${RED}Config tidak ditemukan:${RESET}"
        echo "$XRAY_CONFIG"
        pause_screen
        return
    fi

    if "$XRAY_BIN" run -test -config "$XRAY_CONFIG"; then
        echo
        echo -e "${GREEN}Configuration OK.${RESET}"
    else
        echo
        echo -e "${RED}Configuration ERROR.${RESET}"
    fi

    pause_screen
}

show_version() {
    echo
    if [[ -x "$XRAY_BIN" ]]; then
        "$XRAY_BIN" version
    else
        echo -e "${RED}Xray binary tidak ditemukan.${RESET}"
    fi

    pause_screen
}

view_config() {
    echo

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo -e "${RED}Config tidak ditemukan:${RESET}"
        echo "$XRAY_CONFIG"
        pause_screen
        return
    fi

    echo "Config:"
    echo "----------------------------------------"
    cat "$XRAY_CONFIG"
    echo "----------------------------------------"

    pause_screen
}

draw_header() {
    clear

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${WHITE}                    XRAY MANAGER                      ${CYAN}║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
    echo
    printf "  XRAY STATUS : %b\n" "$(xray_status)"
    echo
}

main_menu() {
    while true; do
        draw_header

        echo "┌────────────────────────────────────────────────────────┐"
        echo "│                                                        │"
        echo "│     1. START XRAY                                      │"
        echo "│     2. STOP XRAY                                       │"
        echo "│     3. RESTART XRAY                                    │"
        echo "│     4. XRAY STATUS                                     │"
        echo "│     5. TEST CONFIG                                     │"
        echo "│     6. XRAY VERSION                                    │"
        echo "│     7. VIEW CONFIG                                     │"
        echo "│     0. BACK                                            │"
        echo "│                                                        │"
        echo "└────────────────────────────────────────────────────────┘"
        echo
        printf "  Select From Options [ 0 - 7 ] : "

        read -r choice

        case "$choice" in
            1) start_xray ;;
            2) stop_xray ;;
            3) restart_xray ;;
            4) show_status ;;
            5) test_config ;;
            6) show_version ;;
            7) view_config ;;
            0|q|Q)
                clear
                return
                ;;
            *)
                echo
                echo -e "${RED}Pilihan tidak valid.${RESET}"
                sleep 1
                ;;
        esac
    done
}

main_menu
