#!/usr/bin/env bash

APP_DIR="/opt/nagara-tunnel-lite"
CONFIG_FILE="$APP_DIR/config/config.conf"
DB_FILE="$APP_DIR/users/users.db"

# =========================
# COLORS
# =========================
RESET='\033[0m'
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'

# =========================
# BASIC FUNCTIONS
# =========================

get_os() {
    . /etc/os-release
    echo "${PRETTY_NAME}"
}

get_cpu() {
    nproc
}

get_ram() {
    free -h | awk '/^Mem:/ {
        printf "%s / %s", $3, $2
    }'

}

get_uptime() {
    uptime -p | sed 's/^up //'
}

get_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

get_domain() {
    if [[ -f "$CONFIG_FILE" ]]; then
        awk -F'"' '/^DOMAIN=/ {print $2}' "$CONFIG_FILE"
    fi
}

service_state() {
    local service="$1"

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "${GREEN}ON${RESET}"
    else
        echo -e "${RED}OFF${RESET}"
    fi
}

count_users() {
    local protocol="$1"

    if [[ ! -f "$DB_FILE" ]]; then
        echo "0"
        return
    fi

    sqlite3 "$DB_FILE" \
        "SELECT COUNT(*) FROM users WHERE protocol='$protocol' AND status='active';" \
        2>/dev/null || echo "0"
}

count_online() {
    # Session monitor belum aktif.
    # Untuk sementara membaca runtime session jika tersedia.
    local session_db="$APP_DIR/runtime/sessions/sessions.db"

    if [[ -f "$session_db" ]]; then
        sqlite3 "$session_db" \
            "SELECT COUNT(*) FROM sessions WHERE status='online';" \
            2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# =========================
# DRAW DASHBOARD
# =========================

draw_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${WHITE}                 NAGARA TUNNEL LITE                   ${CYAN}║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
    echo
}

draw_server_info() {
    echo -e "  ${BOLD}SYS OS${RESET}   : $(get_os)"
    echo -e "  ${BOLD}RAM${RESET}      : $(get_ram)"
    echo -e "  ${BOLD}UPTIME${RESET}   : $(get_uptime)"
    echo -e "  ${BOLD}CPU${RESET}      : $(get_cpu) Core"
    echo -e "  ${BOLD}ISP${RESET}      : UpCloud"
    echo -e "  ${BOLD}CITY${RESET}     : Singapore"
    echo -e "  ${BOLD}IP${RESET}       : $(get_ip)"

    local domain
    domain="$(get_domain)"

    if [[ -n "$domain" ]]; then
        echo -e "  ${BOLD}DOMAIN${RESET}   : $domain"
    else
        echo -e "  ${BOLD}DOMAIN${RESET}   : -"
    fi
}

draw_services() {
    echo
    echo "────────────────────────────────────────────────────────"
    echo
    printf "  %-8s : %-4b │ %-8s : %-4b │ %-8s : %-4b\n" \
        "SSH" \
        "$(service_state ssh)" \
        "XRAY" \
        "$(service_state xray)" \
        "NGINX" \
        "$(service_state nginx)"

    printf "  %-8s : %-4b │ %-8s : %-4b │ %-8s : %-4b\n" \
        "SSL" \
        "$(if [[ -n "$(get_domain)" ]]; then echo -e "${GREEN}ON${RESET}"; else echo -e "${YELLOW}-${RESET}"; fi)" \
        "HAPROXY" \
        "$(service_state haproxy)" \
        "DROPBEAR" \
        "$(service_state dropbear)"
}

draw_accounts() {
    echo
    echo "────────────────────────────────────────────────────────"
    echo

    local vmess="0"
    local vless="0"
    local trojan="0"
    local online="0"

    if [[ -f "$DB_FILE" ]]; then
        while IFS='|' read -r protocol count; do
            case "$protocol" in
                vmess)  vmess="$count" ;;
                vless)  vless="$count" ;;
                trojan) trojan="$count" ;;
            esac
        done < <(
            sqlite3 -separator '|' "$DB_FILE"             "SELECT protocol, COUNT(*) FROM users WHERE status='active' GROUP BY protocol;"             2>/dev/null
        )
    fi

    online="$(count_online)"

    echo -e "                    │ VMESS  : ${WHITE}${vmess}${RESET} │"
    echo -e "                    │ VLESS  : ${WHITE}${vless}${RESET} │"
    echo -e "                    │ TROJAN : ${WHITE}${trojan}${RESET} │"
    echo -e "                    │ ONLINE : ${WHITE}${online}${RESET} │"
}

draw_menu() {
    echo
    echo "────────────────────────────────────────────────────────"
    echo
    echo "┌────────────────────────────────────────────────────────┐"
    echo "│                                                        │"
    printf "│     %-23s   %-23s │\n"         "1. VMESS MANAGER" "5. DOMAIN / SSL"
    printf "│     %-23s   %-23s │\n"         "2. VLESS MANAGER" "6. BACKUP / RESTORE"
    printf "│     %-23s   %-23s │\n"         "3. TROJAN MANAGER" "7. SYSTEM MONITOR"
    printf "│     %-23s   %-23s │\n"         "4. XRAY MANAGER" "8. SETTINGS"
    echo "│                                                        │"
    echo "└────────────────────────────────────────────────────────┘"
}

draw_footer() {
    echo
    echo "              Nagara Tunnel Lite v2.0"
    echo
    printf "  Select From Options [ 1 - 8 ] : "
}

run_manager() {
    local script="$1"

    if [[ -x "$APP_DIR/bin/$script" ]]; then
        "$APP_DIR/bin/$script"
    else
        echo
        echo -e "${YELLOW}Module belum tersedia:${RESET} $script"
        echo
        read -r -p "Tekan Enter untuk kembali..."
    fi
}

main_menu() {
    while true; do
        draw_header
        draw_server_info
        draw_services
        draw_accounts
        draw_menu
        draw_footer
        read -r choice

        case "$choice" in
            1)  run_manager vmess-manager.sh ;;
            2)  run_manager vless-manager.sh ;;
            3)  run_manager trojan-manager.sh ;;
            4)  run_manager xray-manager.sh ;;
            5)  run_manager domain-manager.sh ;;
            6)  run_manager backup-manager.sh ;;
            7)
                run_manager system-monitor.sh
                echo
                read -r -p "Tekan Enter untuk kembali ke menu..."
                ;;
            8)  echo
                echo "Settings belum diaktifkan."
                read -r -p "Tekan Enter untuk kembali..."
                ;;
            q|Q|0)
                clear
                exit 0
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
