#!/usr/bin/env bash

set -u

APP_DIR="/opt/nagara-tunnel-lite"
CONFIG_FILE="$APP_DIR/config/config.conf"

# =========================
# COLORS
# =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
RESET='\033[0m'
BOLD='\033[1m'

# =========================
# BASIC FUNCTIONS
# =========================

pause_screen() {
    echo
    read -rp "Tekan ENTER untuk kembali..." _
}

get_domain() {
    if [[ -f "$CONFIG_FILE" ]]; then
        awk -F'"' '/^DOMAIN=/ {print $2}' "$CONFIG_FILE" | tail -1
    fi
}

service_exists() {
    local service="$1"

    systemctl list-unit-files \
        --type=service \
        2>/dev/null |
        awk '{print $1}' |
        grep -qx "${service}.service"
}

service_status() {
    local service="$1"

    if ! service_exists "$service"; then
        echo "NOT INSTALLED"
    elif systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "ON"
    else
        echo "OFF"
    fi
}

status_text() {
    case "$1" in
        ON)
            echo -e "${GREEN}ON${RESET}"
            ;;
        OFF)
            echo -e "${RED}OFF${RESET}"
            ;;
        NOT*)
            echo -e "${GRAY}$1${RESET}"
            ;;
        *)
            echo -e "${YELLOW}$1${RESET}"
            ;;
    esac
}

show_header() {
    clear

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${WHITE}                  NAGARA TOOLS                         ${CYAN}║${RESET}"
    echo -e "${CYAN}║${GRAY}          Maintenance & VPS Administration             ${CYAN}║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
    echo
}

# =========================
# HEALTH CHECK
# =========================

health_check() {
    show_header

    echo -e "${WHITE}${BOLD}HEALTH CHECK${RESET}"
    echo "────────────────────────────────────────────────────────"
    echo

    # CPU
    local cpu_load
    cpu_load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0")"

    echo -e "${BOLD}RESOURCE${RESET}"

    printf "  CPU Load   : %s\n" "$cpu_load"

    # RAM
    local ram_total ram_used ram_available
    ram_total="$(free -m | awk '/^Mem:/{print $2}')"
    ram_used="$(free -m | awk '/^Mem:/{print $3}')"
    ram_available="$(free -m | awk '/^Mem:/{print $7}')"

    if [[ -n "$ram_total" && "$ram_total" -gt 0 ]]; then
        local ram_percent
        ram_percent=$((ram_used * 100 / ram_total))

        if (( ram_percent >= 90 )); then
            echo -e "  RAM        : ${RED}${ram_used}MB / ${ram_total}MB (${ram_percent}%)${RESET}"
        elif (( ram_percent >= 75 )); then
            echo -e "  RAM        : ${YELLOW}${ram_used}MB / ${ram_total}MB (${ram_percent}%)${RESET}"
        else
            echo -e "  RAM        : ${GREEN}${ram_used}MB / ${ram_total}MB (${ram_percent}%)${RESET}"
        fi
    fi

    echo "  Available  : ${ram_available}MB"

    # SWAP
    local swap_total swap_used
    swap_total="$(free -m | awk '/^Swap:/{print $2}')"
    swap_used="$(free -m | awk '/^Swap:/{print $3}')"

    if [[ "$swap_total" == "0" || -z "$swap_total" ]]; then
        echo -e "  SWAP       : ${YELLOW}NOT CONFIGURED${RESET}"
    else
        echo -e "  SWAP       : ${GREEN}${swap_used}MB / ${swap_total}MB${RESET}"
    fi

    # Disk
    local disk_used disk_available
    disk_used="$(df -h / | awk 'NR==2{print $5}')"
    disk_available="$(df -h / | awk 'NR==2{print $4}')"

    echo "  Disk       : ${disk_used} used / ${disk_available} free"

    echo
    echo -e "${BOLD}SERVICES${RESET}"

    local services=(
        "ssh"
        "xray"
        "nginx"
        "haproxy"
        "dropbear"
        "fail2ban"
        "cron"
    )

    local service
    for service in "${services[@]}"; do
        printf "  %-10s : " "${service^^}"
        status_text "$(service_status "$service")"
    done

    echo
    echo -e "${BOLD}NETWORK${RESET}"

    local domain
    domain="$(get_domain)"

    printf "  IP         : %s\n" "$(hostname -I 2>/dev/null | awk '{print $1}')"
    printf "  Domain     : %s\n" "${domain:-"-"}"

    if [[ -n "$domain" ]]; then
        if getent hosts "$domain" >/dev/null 2>&1; then
            echo -e "  DNS        : ${GREEN}OK${RESET}"
        else
            echo -e "  DNS        : ${RED}FAILED${RESET}"
        fi
    else
        echo -e "  DNS        : ${GRAY}SKIP${RESET}"
    fi

    echo
    echo "────────────────────────────────────────────────────────"

    pause_screen
}

# =========================
# TOP PROCESSES
# =========================

top_processes() {
    echo
    echo -e "${BOLD}TOP CPU PROCESSES${RESET}"
    echo "────────────────────────────────────────────────────────"

    ps -eo pid,ppid,user,%cpu,%mem,etime,comm \
        --sort=-%cpu 2>/dev/null |
        head -n 11

    echo
    echo -e "${BOLD}TOP MEMORY PROCESSES${RESET}"
    echo "────────────────────────────────────────────────────────"

    ps -eo pid,ppid,user,%cpu,%mem,etime,comm \
        --sort=-%mem 2>/dev/null |
        head -n 11
}

# =========================
# SYSTEM DIAGNOSTIC
# =========================

system_diagnostic() {
    show_header

    echo -e "${WHITE}${BOLD}SYSTEM DIAGNOSTIC${RESET}"
    echo "────────────────────────────────────────────────────────"
    echo

    echo -e "${BOLD}SYSTEM${RESET}"
    echo "  Hostname   : $(hostname)"
    echo "  OS         : $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo "  Kernel     : $(uname -r)"
    echo "  CPU Core   : $(nproc)"
    echo "  Uptime     : $(uptime -p 2>/dev/null || true)"

    echo
    echo -e "${BOLD}LOAD${RESET}"
    echo "  Load Avg   : $(cat /proc/loadavg)"

    echo
    echo -e "${BOLD}MEMORY${RESET}"
    free -h

    echo
    echo -e "${BOLD}DISK${RESET}"
    df -h /

    echo
    echo -e "${BOLD}INODE${RESET}"
    df -ih /

    echo
    echo -e "${BOLD}CONNECTIONS${RESET}"

    if command -v ss >/dev/null 2>&1; then
        echo "  TCP ESTABLISHED : $(ss -Htan state established 2>/dev/null | wc -l)"
        echo "  TCP LISTEN      : $(ss -Hlnt 2>/dev/null | wc -l)"
        echo "  UDP             : $(ss -Hlun 2>/dev/null | wc -l)"
    else
        echo "  ss tidak tersedia."
    fi

    top_processes

    echo
    echo "────────────────────────────────────────────────────────"

    pause_screen
}

# =========================
# SERVICE CHECK / REPAIR
# =========================

check_repair() {
    show_header

    echo -e "${WHITE}${BOLD}CHECK / REPAIR${RESET}"
    echo "────────────────────────────────────────────────────────"
    echo

    local services=(
        "ssh"
        "xray"
        "nginx"
        "haproxy"
        "dropbear"
        "fail2ban"
        "cron"
    )

    local service
    local state
    local problem=0
    local -a failed_services=()

    echo -e "${WHITE}${BOLD}1. SERVICE CHECK${RESET}"
    echo

    for service in "${services[@]}"; do
        state="$(service_status "$service")"

        printf "  %-10s : " "${service^^}"
        status_text "$state"

        case "$state" in
            OFF|FAILED)
                problem=1
                failed_services+=("$service")
                echo -e "             ${YELLOW}Perlu pemeriksaan.${RESET}"
                ;;
            "NOT INSTALLED")
                echo -e "             ${YELLOW}Tidak terpasang.${RESET}"
                ;;
        esac
    done

    echo
    echo "────────────────────────────────────────────────────────"
    echo -e "${WHITE}${BOLD}2. CONFIGURATION CHECK${RESET}"
    echo

    local check_ok=1

    if command -v xray >/dev/null 2>&1; then
        if xray -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1; then
            echo -e "  XRAY CONFIG   : ${GREEN}OK${RESET}"
        else
            echo -e "  XRAY CONFIG   : ${RED}ERROR${RESET}"
            echo -e "                  ${YELLOW}Konfigurasi Xray perlu diperiksa.${RESET}"
            problem=1
            check_ok=0
        fi
    else
        echo -e "  XRAY CONFIG   : ${YELLOW}XRAY TIDAK DITEMUKAN${RESET}"
        problem=1
        check_ok=0
    fi

    if command -v nginx >/dev/null 2>&1; then
        if nginx -t >/dev/null 2>&1; then
            echo -e "  NGINX CONFIG  : ${GREEN}OK${RESET}"
        else
            echo -e "  NGINX CONFIG  : ${RED}ERROR${RESET}"
            echo -e "                  ${YELLOW}Konfigurasi Nginx perlu diperiksa.${RESET}"
            problem=1
            check_ok=0
        fi
    else
        echo -e "  NGINX CONFIG  : ${YELLOW}NGINX TIDAK DITEMUKAN${RESET}"
        problem=1
        check_ok=0
    fi

    if command -v fail2ban-client >/dev/null 2>&1; then
        if fail2ban-client -t >/dev/null 2>&1; then
            echo -e "  FAIL2BAN CFG  : ${GREEN}OK${RESET}"
        else
            echo -e "  FAIL2BAN CFG  : ${RED}ERROR${RESET}"
            echo -e "                  ${YELLOW}Konfigurasi Fail2ban perlu diperiksa.${RESET}"
            problem=1
            check_ok=0
        fi
    else
        echo -e "  FAIL2BAN CFG  : ${YELLOW}FAIL2BAN TIDAK DITEMUKAN${RESET}"
    fi

    echo
    echo "────────────────────────────────────────────────────────"

    if [[ "$problem" -eq 0 ]]; then
        echo
        echo -e "  ${GREEN}${BOLD}SISTEM TIDAK MENEMUKAN MASALAH.${RESET}"
        echo
        pause_screen
        return
    fi

    echo
    echo -e "  ${YELLOW}${BOLD}DITEMUKAN MASALAH YANG PERLU DIPERIKSA.${RESET}"
    echo

    if [[ "${#failed_services[@]}" -gt 0 ]]; then
        echo "Service yang bermasalah:"
        for service in "${failed_services[@]}"; do
            echo "  - $service"
        done
        echo
    fi

    echo "Pilih tindakan:"
    echo "1. Repair service yang bermasalah"
    echo "2. Tampilkan detail error"
    echo "0. Kembali"
    echo

    read -rp "Pilih: " choice

    case "$choice" in
        1)
            if [[ "${#failed_services[@]}" -eq 0 ]]; then
                echo
                echo -e "${YELLOW}Tidak ada service yang bisa direstart otomatis.${RESET}"
                echo "Masalah kemungkinan berada pada konfigurasi."
                pause_screen
                return
            fi

            echo
            echo "Menjalankan repair service..."
            echo

            for service in "${failed_services[@]}"; do
                echo "→ Restart $service"

                if systemctl restart "$service" 2>/dev/null; then
                    sleep 1

                    if systemctl is-active --quiet "$service" 2>/dev/null; then
                        echo -e "  ${GREEN}Berhasil.${RESET}"
                    else
                        echo -e "  ${RED}Masih bermasalah.${RESET}"
                    fi
                else
                    echo -e "  ${RED}Gagal restart.${RESET}"
                fi
            done

            echo
            echo "Repair selesai. Melakukan pengecekan ulang..."
            sleep 2

            echo
            for service in "${failed_services[@]}"; do
                state="$(service_status "$service")"
                printf "  %-10s : " "${service^^}"
                status_text "$state"
            done

            pause_screen
            ;;

        2)
            echo
            echo "=== DETAIL SERVICE BERMASALAH ==="

            if [[ "${#failed_services[@]}" -gt 0 ]]; then
                for service in "${failed_services[@]}"; do
                    echo
                    echo "--- $service ---"
                    systemctl status "$service" --no-pager -l 2>&1 | head -30
                done
            fi

            echo
            echo "=== DETAIL KONFIGURASI ==="

            if [[ "$check_ok" -eq 0 ]]; then
                echo
                echo "Jika Xray/Nginx/Fail2ban config bermasalah,"
                echo "gunakan menu detail atau periksa log sebelum melakukan perubahan."
            fi

            pause_screen
            ;;

        0)
            return
            ;;

        *)
            echo
            echo -e "${RED}Pilihan tidak valid.${RESET}"
            sleep 1
            ;;
    esac
}


# =========================
# RESTART SERVICES
# =========================

restart_services() {
    show_header

    echo -e "${WHITE}${BOLD}RESTART SERVICES${RESET}"
    echo "────────────────────────────────────────────────────────"
    echo

    echo "1. Xray"
    echo "2. Nginx"
    echo "3. HAProxy"
    echo "4. Dropbear"
    echo "5. Fail2ban"
    echo "6. SSH"
    echo "7. Restart semua service Nagara"
    echo "0. Kembali"
    echo

    read -rp "Pilih: " choice

    local services=()

    case "$choice" in
        1) services=("xray") ;;
        2) services=("nginx") ;;
        3) services=("haproxy") ;;
        4) services=("dropbear") ;;
        5) services=("fail2ban") ;;
        6) services=("ssh") ;;
        7)
            services=("xray" "nginx" "haproxy" "dropbear" "fail2ban")
            ;;
        0) return ;;
        *)
            echo -e "${RED}Pilihan tidak valid.${RESET}"
            sleep 1
            return
            ;;
    esac

    echo

    local service

    for service in "${services[@]}"; do
        if service_exists "$service"; then
            echo "Restarting $service..."

            if systemctl restart "$service" 2>/dev/null; then
                echo -e "  ${GREEN}OK${RESET}"
            else
                echo -e "  ${RED}FAILED${RESET}"
            fi
        else
            echo -e "  ${GRAY}$service tidak terpasang.${RESET}"
        fi
    done

    echo
    echo "Selesai."
    pause_screen
}

# =========================
# MEMORY / SWAP
# =========================

memory_swap() {
    show_header

    echo -e "${WHITE}${BOLD}MEMORY / SWAP${RESET}"
    echo "────────────────────────────────────────────────────────"
    echo

    free -h

    echo
    echo -e "${BOLD}SWAP DETAIL${RESET}"

    if command -v swapon >/dev/null 2>&1; then
        if swapon --show 2>/dev/null | grep -q .; then
            swapon --show
        else
            echo -e "${YELLOW}Belum ada SWAP aktif.${RESET}"
        fi
    fi

    echo
    echo -e "${BOLD}MEMORY PRESSURE${RESET}"

    if [[ -f /proc/pressure/memory ]]; then
        cat /proc/pressure/memory
    else
        echo "Memory PSI tidak tersedia."
    fi

    echo
    echo "Belum ada perubahan memory/swap otomatis."
    echo "Tahap berikutnya bisa menambahkan pembuatan SWAP"
    echo "dengan pengecekan ukuran VPS terlebih dahulu."

    echo
    pause_screen
}

# =========================
# PORT INFO
# =========================

info_port() {
    show_header

    echo -e "${WHITE}${BOLD}INFO PORT${RESET}"
    echo "────────────────────────────────────────────────────────"
    echo

    if command -v ss >/dev/null 2>&1; then
        echo -e "${BOLD}PORT LISTENING${RESET}"
        echo

        ss -lntup 2>/dev/null |
            awk 'NR==1 || /LISTEN|UNCONN/'
    else
        echo "Perintah ss tidak tersedia."
    fi

    echo
    echo "────────────────────────────────────────────────────────"

    pause_screen
}

# =========================
# MAIN MENU
# =========================

main_menu() {
    while true; do
        show_header

        echo -e "${WHITE}${BOLD}MAINTENANCE & ADMINISTRATION${RESET}"
        echo
        echo "  [01] HEALTH CHECK"
        echo "  [02] SYSTEM DIAGNOSTIC"
        echo "  [03] CHECK / REPAIR"
        echo "  [04] RESTART SERVICES"
        echo "  [05] AUTO MAINTENANCE"
        echo "  [06] AUTO REBOOT"
        echo "  [07] MEMORY / SWAP"
        echo "  [08] CLEAN LOG"
        echo "  [09] CLEAR CACHE"
        echo "  [10] INFO PORT"
        echo "  [11] TELEGRAM"
        echo "  [00] KEMBALI"
        echo

        read -rp "  Pilih menu: " choice

        case "$choice" in
            1|01)
                health_check
                ;;
            2|02)
                system_diagnostic
                ;;
            3|03)
                check_repair
                ;;
            4|04)
                restart_services
                ;;
            5|05)
                echo
                echo "AUTO MAINTENANCE belum diaktifkan."
                echo "Akan dibuat setelah mesin diagnosis selesai."
                pause_screen
                ;;
            6|06)
                echo
                echo "AUTO REBOOT belum diaktifkan."
                echo "Kita akan buat pilihan 1H / 3H / 6H / 12H / 24H."
                pause_screen
                ;;
            7|07)
                memory_swap
                ;;
            8|08)
                echo
                echo "CLEAN LOG akan dibuat pada tahap berikutnya."
                pause_screen
                ;;
            9|09)
                echo
                echo "CLEAR CACHE akan dibuat dengan mekanisme aman."
                pause_screen
                ;;
            10)
                info_port
                ;;
            11)
                echo
                echo "TELEGRAM akan dibuat pada tahap berikutnya."
                pause_screen
                ;;
            0|00|q|Q)
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
