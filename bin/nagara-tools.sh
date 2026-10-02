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
# AUTO MAINTENANCE
# =========================
AUTO_MAINT_CONFIG="$APP_DIR/runtime/auto-maintenance.conf"
AUTO_MAINT_SERVICE="/etc/systemd/system/nagara-auto-maintenance.service"
AUTO_MAINT_TIMER="/etc/systemd/system/nagara-auto-maintenance.timer"

load_auto_maintenance() {
    AUTO_MAINT_INTERVAL="OFF"

    if [[ -f "$AUTO_MAINT_CONFIG" ]]; then
        # shellcheck disable=SC1090
        source "$AUTO_MAINT_CONFIG"
    fi

    [[ -n "${AUTO_MAINT_INTERVAL:-}" ]] || AUTO_MAINT_INTERVAL="OFF"
}

auto_maintenance_interval_seconds() {
    case "$1" in
        30m) echo 1800 ;;
        1h)  echo 3600 ;;
        3h)  echo 10800 ;;
        6h)  echo 21600 ;;
        12h) echo 43200 ;;
        24h) echo 86400 ;;
        *)   echo 0 ;;
    esac
}

auto_maintenance_label() {
    case "$1" in
        30m) echo "30 MENIT" ;;
        1h)  echo "1 JAM" ;;
        3h)  echo "3 JAM" ;;
        6h)  echo "6 JAM" ;;
        12h) echo "12 JAM" ;;
        24h) echo "24 JAM" ;;
        *)   echo "OFF" ;;
    esac
}

write_auto_maintenance_files() {
    local interval="$1"
    local seconds

    seconds="$(auto_maintenance_interval_seconds "$interval")"

    mkdir -p "$APP_DIR/runtime"

    if [[ "$interval" == "OFF" || "$seconds" -eq 0 ]]; then
        rm -f "$AUTO_MAINT_CONFIG"
        systemctl disable --now nagara-auto-maintenance.timer >/dev/null 2>&1 || true
        rm -f "$AUTO_MAINT_TIMER" "$AUTO_MAINT_SERVICE"
        systemctl daemon-reload
        return 0
    fi

    cat > "$AUTO_MAINT_CONFIG" <<EOF
AUTO_MAINT_INTERVAL="$interval"
EOF

    cat > "$AUTO_MAINT_SERVICE" <<'EOF'
[Unit]
Description=Nagara Tunnel Lite Auto Maintenance
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/nagara-tunnel-lite/bin/nagara-tools.sh --auto-maintenance
EOF

    cat > "$AUTO_MAINT_TIMER" <<EOF
[Unit]
Description=Nagara Tunnel Lite Auto Maintenance Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=${seconds}s
Persistent=true

[Install]
WantedBy=timers.target
EOF

    chmod 600 "$AUTO_MAINT_CONFIG"
    chmod 644 "$AUTO_MAINT_SERVICE" "$AUTO_MAINT_TIMER"

    systemctl daemon-reload
    systemctl enable --now nagara-auto-maintenance.timer
}

run_auto_maintenance() {
    local log_file="/var/log/nagara-tunnel-lite/auto-maintenance.log"

    # TELEGRAM_AUTO_MAINTENANCE_NOTIFICATION
    telegram_send "NAGARA TUNNEL LITE

AUTO MAINTENANCE
Maintenance otomatis sedang dijalankan.

Server : $(hostname)
Time   : $(date '+%Y-%m-%d %H:%M:%S')"
    local timestamp

    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    mkdir -p "$(dirname "$log_file")"

    {
        echo
        echo "[$timestamp] AUTO MAINTENANCE START"

        echo "[CHECK] Disk usage:"
        df -h / | tail -1

        echo "[CHECK] Inode usage:"
        df -ih / | tail -1

        echo "[CHECK] Failed systemd units:"
        systemctl --failed --no-legend 2>/dev/null || true

        echo "[CLEAN] Temporary files:"
        find /tmp -xdev -type f -mtime +7 -delete 2>/dev/null || true

        echo "[CLEAN] Journal:"
        journalctl --vacuum-time=7d >/dev/null 2>&1 || true

        echo "[CHECK] Services:"
        for service in ssh xray nginx haproxy dropbear fail2ban cron; do
            if service_exists "$service"; then
                if systemctl is-active --quiet "$service" 2>/dev/null; then
                    echo "  $service : ON"
                else
                    echo "  $service : OFF"
                    echo "  $service : restart attempt"

                    systemctl restart "$service" >/dev/null 2>&1 || true

                    if systemctl is-active --quiet "$service" 2>/dev/null; then
                        echo "  $service : recovered"
                    else
                        echo "  $service : still OFF"
                    fi
                fi
            fi
        done

        echo "[CHECK] Memory:"
        free -h

        echo "[$timestamp] AUTO MAINTENANCE END"
    } >> "$log_file" 2>&1

    tail -200 "$log_file" > "${log_file}.tmp" 2>/dev/null || true
    mv "${log_file}.tmp" "$log_file" 2>/dev/null || true
}

auto_maintenance_menu() {
    show_header
    load_auto_maintenance

    echo -e "${WHITE}${BOLD}AUTO MAINTENANCE${RESET}"
    echo "────────────────────────────────────────────────────────"
    echo

    echo -n "  Status      : "
    if [[ "$AUTO_MAINT_INTERVAL" == "OFF" ]]; then
        echo -e "${RED}OFF${RESET}"
    else
        echo -e "${GREEN}ON${RESET}"
    fi

    echo "  Interval    : $(auto_maintenance_label "$AUTO_MAINT_INTERVAL")"

    echo
    echo "Pilih interval:"
    echo
    echo "  1. OFF"
    echo "  2. 30 MENIT"
    echo "  3. 1 JAM"
    echo "  4. 3 JAM"
    echo "  5. 6 JAM"
    echo "  6. 12 JAM"
    echo "  7. 24 JAM"
    echo "  0. Kembali"
    echo

    read -rp "  Pilih: " choice

    local new_interval=""

    case "$choice" in
        1) new_interval="OFF" ;;
        2) new_interval="30m" ;;
        3) new_interval="1h" ;;
        4) new_interval="3h" ;;
        5) new_interval="6h" ;;
        6) new_interval="12h" ;;
        7) new_interval="24h" ;;
        0) return ;;
        *)
            echo
            echo -e "${RED}Pilihan tidak valid.${RESET}"
            sleep 1
            return
            ;;
    esac

    echo
    echo "Menerapkan pengaturan..."

    if write_auto_maintenance_files "$new_interval"; then
        echo
        if [[ "$new_interval" == "OFF" ]]; then
            echo -e "${YELLOW}AUTO MAINTENANCE dimatikan.${RESET}"
        else
            echo -e "${GREEN}AUTO MAINTENANCE aktif.${RESET}"
            echo "Interval : $(auto_maintenance_label "$new_interval")"
        fi
    else
        echo
        echo -e "${RED}Gagal menerapkan AUTO MAINTENANCE.${RESET}"
    fi

    pause_screen
}

# =========================
# AUTO REBOOT
# =========================
AUTO_REBOOT_CONFIG="$APP_DIR/runtime/auto-reboot.conf"
AUTO_REBOOT_SERVICE="/etc/systemd/system/nagara-auto-reboot.service"
AUTO_REBOOT_TIMER="/etc/systemd/system/nagara-auto-reboot.timer"

load_auto_reboot() {
    AUTO_REBOOT_INTERVAL="OFF"

    if [[ -f "$AUTO_REBOOT_CONFIG" ]]; then
        # shellcheck disable=SC1090
        source "$AUTO_REBOOT_CONFIG"
    fi

    [[ -n "${AUTO_REBOOT_INTERVAL:-}" ]] || AUTO_REBOOT_INTERVAL="OFF"
}

auto_reboot_interval_seconds() {
    case "$1" in
        1h)  echo 3600 ;;
        3h)  echo 10800 ;;
        6h)  echo 21600 ;;
        12h) echo 43200 ;;
        24h) echo 86400 ;;
        *)   echo 0 ;;
    esac
}

auto_reboot_label() {
    case "$1" in
        1h)  echo "1 JAM" ;;
        3h)  echo "3 JAM" ;;
        6h)  echo "6 JAM" ;;
        12h) echo "12 JAM" ;;
        24h) echo "24 JAM" ;;
        *)   echo "OFF" ;;
    esac
}

write_auto_reboot_files() {
    local interval="$1"

    # TELEGRAM_AUTO_REBOOT_NOTIFICATION
    if [[ "$interval" != "off" ]]; then
        telegram_send "NAGARA TUNNEL LITE

AUTO REBOOT AKTIF

Server   : $(hostname)
Interval : $(auto_reboot_label "$interval")
Status   : VPS akan reboot otomatis sesuai jadwal.

Time     : $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    local seconds

    seconds="$(auto_reboot_interval_seconds "$interval")"

    mkdir -p "$APP_DIR/runtime"

    if [[ "$interval" == "OFF" || "$seconds" -eq 0 ]]; then
        rm -f "$AUTO_REBOOT_CONFIG"

        systemctl disable --now nagara-auto-reboot.timer >/dev/null 2>&1 || true

        rm -f "$AUTO_REBOOT_TIMER" "$AUTO_REBOOT_SERVICE"

        systemctl daemon-reload
        return 0
    fi

    cat > "$AUTO_REBOOT_CONFIG" <<EOF
AUTO_REBOOT_INTERVAL="$interval"
EOF

    cat > "$AUTO_REBOOT_SERVICE" <<'EOF'
[Unit]
Description=Nagara Tunnel Lite Auto Reboot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl reboot
EOF

    cat > "$AUTO_REBOOT_TIMER" <<EOF
[Unit]
Description=Nagara Tunnel Lite Auto Reboot Timer

[Timer]
OnBootSec=${seconds}s
OnUnitActiveSec=${seconds}s
Persistent=false

[Install]
WantedBy=timers.target
EOF

    chmod 600 "$AUTO_REBOOT_CONFIG"
    chmod 644 "$AUTO_REBOOT_SERVICE" "$AUTO_REBOOT_TIMER"

    systemctl daemon-reload
    systemctl enable --now nagara-auto-reboot.timer
}

auto_reboot_menu() {
    show_header
    load_auto_reboot

    echo -e "${WHITE}${BOLD}AUTO REBOOT${RESET}"
    echo "────────────────────────────────────────────────────────"
    echo

    echo -n "  Status      : "
    if [[ "$AUTO_REBOOT_INTERVAL" == "OFF" ]]; then
        echo -e "${RED}OFF${RESET}"
    else
        echo -e "${GREEN}ON${RESET}"
    fi

    echo "  Interval    : $(auto_reboot_label "$AUTO_REBOOT_INTERVAL")"

    echo
    echo "Pilih interval:"
    echo
    echo "  1. OFF"
    echo "  2. 1 JAM"
    echo "  3. 3 JAM"
    echo "  4. 6 JAM"
    echo "  5. 12 JAM"
    echo "  6. 24 JAM"
    echo "  0. Kembali"
    echo

    read -rp "  Pilih: " choice

    local new_interval=""

    case "$choice" in
        1) new_interval="OFF" ;;
        2) new_interval="1h" ;;
        3) new_interval="3h" ;;
        4) new_interval="6h" ;;
        5) new_interval="12h" ;;
        6) new_interval="24h" ;;
        0) return ;;
        *)
            echo
            echo -e "${RED}Pilihan tidak valid.${RESET}"
            sleep 1
            return
            ;;
    esac

    echo

    if [[ "$new_interval" != "OFF" ]]; then
        echo -e "${YELLOW}PERHATIAN:${RESET}"
        echo "VPS akan reboot otomatis setiap"
        echo "$(auto_reboot_label "$new_interval")."
        echo
        echo "Reboot pertama tidak dilakukan sekarang."
        echo "Timer akan menunggu sesuai interval yang dipilih."
        echo
        read -rp "Aktifkan AUTO REBOOT? [y/N]: " confirm

        case "$confirm" in
            y|Y|yes|YES)
                ;;
            *)
                echo
                echo "Dibatalkan."
                pause_screen
                return
                ;;
        esac
    fi

    echo
    echo "Menerapkan pengaturan..."

    if write_auto_reboot_files "$new_interval"; then
        echo
        if [[ "$new_interval" == "OFF" ]]; then
            echo -e "${YELLOW}AUTO REBOOT dimatikan.${RESET}"
        else
            echo -e "${GREEN}AUTO REBOOT aktif.${RESET}"
            echo "Interval : $(auto_reboot_label "$new_interval")"
        fi
    else
        echo
        echo -e "${RED}Gagal menerapkan AUTO REBOOT.${RESET}"
    fi

    pause_screen
}

# =========================
# CLEAN LOG
# =========================
clean_log() {
    show_header
    echo -e "${WHITE}${BOLD}CLEAN LOG${RESET}"
    echo "────────────────────────────────────────────────────────"
    echo

    local journal_size xray_size nginx_size auth_size syslog_size

    journal_size="$(journalctl --disk-usage 2>/dev/null | sed 's/.*take up //; s/ in the file system.*//')"
    [[ -n "$journal_size" ]] || journal_size="0"

    xray_size="$(du -sh /var/log/xray 2>/dev/null | awk '{print $1}')"
    [[ -n "$xray_size" ]] || xray_size="0"

    nginx_size="$(du -sh /var/log/nginx 2>/dev/null | awk '{print $1}')"
    [[ -n "$nginx_size" ]] || nginx_size="0"

    auth_size="$(du -h /var/log/auth.log 2>/dev/null | awk '{print $1}')"
    [[ -n "$auth_size" ]] || auth_size="0"

    syslog_size="$(du -h /var/log/syslog 2>/dev/null | awk '{print $1}')"
    [[ -n "$syslog_size" ]] || syslog_size="0"

    echo "  Journal        : $journal_size"
    echo "  Xray log       : $xray_size"
    echo "  Nginx log      : $nginx_size"
    echo "  Auth log       : $auth_size"
    echo "  Syslog         : $syslog_size"
    echo
    echo "  1. Journal > 7 hari"
    echo "  2. Journal > 3 hari"
    echo "  3. Log Xray & Nginx"
    echo "  4. Semua log aman"
    echo "  0. Kembali"
    echo

    read -rp "  Pilih: " choice

    case "$choice" in
        1)
            echo
            echo "Membersihkan journal lebih dari 7 hari..."
            journalctl --vacuum-time=7d
            ;;
        2)
            echo
            echo "Membersihkan journal lebih dari 3 hari..."
            journalctl --vacuum-time=3d
            ;;
        3)
            echo
            echo "Merotasi log Xray & Nginx..."
            if command -v logrotate >/dev/null 2>&1; then
                logrotate -f /etc/logrotate.conf >/dev/null 2>&1 || true
            fi

            if [[ -f /var/log/xray/access.log ]]; then
                : > /var/log/xray/access.log
            fi

            if [[ -f /var/log/nginx/access.log ]]; then
                : > /var/log/nginx/access.log
            fi

            if [[ -f /var/log/nginx/error.log ]]; then
                : > /var/log/nginx/error.log
            fi

            echo "Log Xray & Nginx dibersihkan."
            ;;
        4)
            echo
            echo "Membersihkan journal lebih dari 7 hari..."
            journalctl --vacuum-time=7d

            echo
            echo "Merotasi log Xray & Nginx..."
            if command -v logrotate >/dev/null 2>&1; then
                logrotate -f /etc/logrotate.conf >/dev/null 2>&1 || true
            fi

            if [[ -f /var/log/xray/access.log ]]; then
                : > /var/log/xray/access.log
            fi

            if [[ -f /var/log/nginx/access.log ]]; then
                : > /var/log/nginx/access.log
            fi

            if [[ -f /var/log/nginx/error.log ]]; then
                : > /var/log/nginx/error.log
            fi

            echo
            echo "Cleanup selesai."
            ;;
        0)
            return
            ;;
        *)
            echo
            echo -e "${RED}Pilihan tidak valid.${RESET}"
            ;;
    esac

    pause_screen
}

# =========================
# CLEAR CACHE
# =========================
clear_cache() {
    show_header
    echo -e "${WHITE}${BOLD}CLEAR CACHE${RESET}"
    echo "────────────────────────────────────────────────────────"
    echo

    local apt_size tmp_size vartmp_size

    apt_size="$(du -sh /var/cache/apt 2>/dev/null | awk '{print $1}')"
    [[ -n "$apt_size" ]] || apt_size="0"

    tmp_size="$(du -sh /tmp 2>/dev/null | awk '{print $1}')"
    [[ -n "$tmp_size" ]] || tmp_size="0"

    vartmp_size="$(du -sh /var/tmp 2>/dev/null | awk '{print $1}')"
    [[ -n "$vartmp_size" ]] || vartmp_size="0"

    echo "  APT cache      : $apt_size"
    echo "  /tmp           : $tmp_size"
    echo "  /var/tmp       : $vartmp_size"
    echo
    echo "  1. APT cache"
    echo "  2. Temporary files"
    echo "  3. Semua cache aman"
    echo "  0. Kembali"
    echo

    read -rp "  Pilih: " choice

    case "$choice" in
        1)
            echo
            echo "Membersihkan APT cache..."
            apt-get clean >/dev/null 2>&1 || true
            echo "APT cache selesai dibersihkan."
            ;;
        2)
            echo
            echo "Membersihkan temporary files lama..."

            find /tmp -xdev -type f -mtime +7 -delete 2>/dev/null || true
            find /var/tmp -xdev -type f -mtime +7 -delete 2>/dev/null || true

            echo "Temporary files lama selesai dibersihkan."
            ;;
        3)
            echo
            echo "Membersihkan APT cache..."
            apt-get clean >/dev/null 2>&1 || true

            echo
            echo "Membersihkan temporary files lama..."
            find /tmp -xdev -type f -mtime +7 -delete 2>/dev/null || true
            find /var/tmp -xdev -type f -mtime +7 -delete 2>/dev/null || true

            echo
            echo "Cleanup cache selesai."
            ;;
        0)
            return
            ;;
        *)
            echo
            echo -e "${RED}Pilihan tidak valid.${RESET}"
            ;;
    esac

    pause_screen
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

    # TELEGRAM_CHECK_REPAIR_NOTIFICATION
    telegram_send "NAGARA TUNNEL LITE

CHECK / REPAIR

Server : $(hostname)
Time   : $(date '+%Y-%m-%d %H:%M:%S')

Ditemukan masalah pada service atau konfigurasi.
Silakan periksa menu CHECK / REPAIR."

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

                # TELEGRAM_RESTART_SERVICE_NOTIFICATION
                telegram_send "NAGARA TUNNEL LITE

SERVICE RESTART GAGAL

Server  : $(hostname)
Service : $service
Time    : $(date '+%Y-%m-%d %H:%M:%S')

Restart service gagal. Silakan lakukan pemeriksaan."
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

    local mem_total mem_used mem_available mem_percent
    local swap_total swap_used swap_percent

    mem_total="$(free -m | awk '/^Mem:/{print $2}')"
    mem_used="$(free -m | awk '/^Mem:/{print $3}')"
    mem_available="$(free -m | awk '/^Mem:/{print $7}')"

    if [[ "${mem_total:-0}" -gt 0 ]]; then
        mem_percent=$((mem_used * 100 / mem_total))
    else
        mem_percent=0
    fi

    swap_total="$(free -m | awk '/^Swap:/{print $2}')"
    swap_used="$(free -m | awk '/^Swap:/{print $3}')"

    if [[ "${swap_total:-0}" -gt 0 ]]; then
        swap_percent=$((swap_used * 100 / swap_total))
    else
        swap_percent=0
    fi

    echo -e "${BOLD}RAM${RESET}"
    echo "  Total       : ${mem_total} MB"
    echo "  Used        : ${mem_used} MB (${mem_percent}%)"
    echo "  Available   : ${mem_available} MB"

    echo
    echo -e "${BOLD}SWAP${RESET}"

    if [[ "${swap_total:-0}" -gt 0 ]]; then
        echo "  Total       : ${swap_total} MB"
        echo "  Used        : ${swap_used} MB (${swap_percent}%)"

        echo
        echo "  Active swap:"
        swapon --show 2>/dev/null || true
    else
        echo -e "  Status      : ${YELLOW}NOT CONFIGURED${RESET}"
    fi

    echo
    echo -e "${BOLD}MEMORY PRESSURE${RESET}"

    if [[ -f /proc/pressure/memory ]]; then
        awk '
            /^some/ {print "  " $0}
            /^full/ {print "  " $0}
        ' /proc/pressure/memory
    else
        echo "  Memory PSI tidak tersedia."
    fi

    echo
    echo -e "${BOLD}TOP MEMORY PROCESSES${RESET}"
    echo "────────────────────────────────────────────────────────"

    ps -eo pid,user,%mem,rss,comm --sort=-%mem 2>/dev/null |
        head -n 6 |
        awk '
        NR==1 {
            printf "  %-8s %-12s %-7s %-10s %s\n",
                   "PID","USER","%MEM","RSS","COMMAND"
            next
        }
        {
            printf "  %-8s %-12s %-7s %-10s %s\n",
                   $1,$2,$3,$4" KB",$5
        }'

    echo
    echo "────────────────────────────────────────────────────────"

    if [[ "${swap_total:-0}" -eq 0 ]]; then
        echo
        echo -e "${YELLOW}SWAP BELUM TERPASANG.${RESET}"
        echo
        echo "Swap dapat membantu sebagai cadangan ketika RAM"
        echo "tertekan, tetapi swap bukan pengganti RAM."
        echo
        echo "1. Buat SWAP 2 GB"
        echo "0. Kembali"
        echo

        read -rp "Pilih: " choice

        case "$choice" in
            1)
                echo
                echo "Memeriksa kebutuhan dan ruang disk..."

                local disk_free_mb
                disk_free_mb="$(df -Pm / | awk 'NR==2{print $4}')"

                if [[ "${disk_free_mb:-0}" -lt 3072 ]]; then
                    echo -e "${RED}Ruang disk bebas tidak cukup untuk membuat swap 2 GB.${RESET}"
                    pause_screen
                    return
                fi

                if [[ -e /swapfile ]]; then
                    echo -e "${YELLOW}/swapfile sudah ada tetapi belum aktif.${RESET}"
                    echo "Tidak akan menimpa file tersebut."
                    pause_screen
                    return
                fi

                echo
                echo "Membuat swap 2 GB..."

                if fallocate -l 2G /swapfile 2>/dev/null &&
                   chmod 600 /swapfile &&
                   mkswap /swapfile >/dev/null 2>&1 &&
                   swapon /swapfile >/dev/null 2>&1; then

                    if ! grep -qE '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab; then
                        echo '/swapfile none swap sw 0 0' >> /etc/fstab
                    fi

                    echo
                    echo -e "${GREEN}SWAP 2 GB berhasil diaktifkan.${RESET}"
                    echo
                    free -h
                else
                    echo
                    echo -e "${RED}Gagal membuat atau mengaktifkan swap.${RESET}"
                fi

                pause_screen
                ;;

            0)
                return
                ;;

            *)
                echo -e "${RED}Pilihan tidak valid.${RESET}"
                sleep 1
                ;;
        esac
    else
        echo
        echo -e "${GREEN}SWAP sudah aktif. Tidak ada perubahan yang diperlukan.${RESET}"
        echo
        pause_screen
    fi
}


# =========================
# PORT INFO
# =========================

info_port() {
    show_header

    echo -e "${WHITE}${BOLD}INFO PORT${RESET}"
    echo "────────────────────────────────────────────────────────"
    echo

    port_state() {
        local port="$1"

        if ss -lnt 2>/dev/null |
            awk -v p=":$port" '$4 ~ p"$" {found=1} END {exit !found}'; then
            echo -e "${GREEN}LISTEN${RESET}"
        else
            echo -e "${RED}CLOSED${RESET}"
        fi
    }

    echo -e "${WHITE}${BOLD}PUBLIC PORT${RESET}"
    echo "  22    SSH        : $(port_state 22)"
    echo "  80    NGINX      : $(port_state 80)"
    echo "  443   NGINX      : $(port_state 443)"
    echo "  2222  DROPBEAR   : $(port_state 2222)"

    echo
    echo -e "${WHITE}${BOLD}XRAY INTERNAL${RESET}"

    for port in 10001 10002 10003 10004 10005 10085; do
        printf "  %-5s : " "$port"
        port_state "$port"
    done

    echo
    echo -e "${GRAY}Port Xray di atas digunakan secara internal/local.${RESET}"
    echo
    echo "────────────────────────────────────────────────────────"

    pause_screen
}

# =========================
# TELEGRAM
# =========================

TELEGRAM_CONFIG="$APP_DIR/runtime/telegram.conf"
TELEGRAM_SCRIPT="$APP_DIR/bin/telegram-notify.sh"

load_telegram_config() {
    TELEGRAM_ENABLED="false"
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID=""

    if [[ -f "$TELEGRAM_CONFIG" ]]; then
        source "$TELEGRAM_CONFIG"
    fi
}

save_telegram_config() {
    mkdir -p "$APP_DIR/runtime"

    cat > "$TELEGRAM_CONFIG" <<EOF
TELEGRAM_ENABLED="$TELEGRAM_ENABLED"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
EOF

    chmod 600 "$TELEGRAM_CONFIG"
}

telegram_menu() {
    while true; do
        show_header
        load_telegram_config

        echo -e "${WHITE}${BOLD}TELEGRAM NOTIFICATION${RESET}"
        echo "────────────────────────────────────────────────────────"
        echo

        if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
            echo -e "  Status       : ${GREEN}ON${RESET}"
        else
            echo -e "  Status       : ${RED}OFF${RESET}"
        fi

        if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
            echo "  Bot Token    : SET"
        else
            echo "  Bot Token    : NOT SET"
        fi

        if [[ -n "$TELEGRAM_CHAT_ID" ]]; then
            echo "  Chat ID      : SET"
        else
            echo "  Chat ID      : NOT SET"
        fi

        echo
        echo "  1. SET BOT TOKEN"
        echo "  2. SET CHAT ID"
        echo "  3. TEST NOTIFICATION"
        echo "  4. ENABLE"
        echo "  5. DISABLE"
        echo "  0. KEMBALI"
        echo

        read -rp "  Pilih: " choice

        case "$choice" in
            1)
                echo
                read -rp "  Masukkan Bot Token: " TELEGRAM_BOT_TOKEN
                echo
                save_telegram_config
                echo -e "${GREEN}Bot Token tersimpan.${RESET}"
                pause_screen
                ;;
            2)
                echo
                read -rp "  Masukkan Chat ID: " TELEGRAM_CHAT_ID
                save_telegram_config
                echo -e "${GREEN}Chat ID tersimpan.${RESET}"
                pause_screen
                ;;
            3)
                load_telegram_config
                echo
                if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
                    echo -e "${RED}Bot Token dan Chat ID belum lengkap.${RESET}"
                else
                    echo "Mengirim test notification..."
                    if "$TELEGRAM_SCRIPT" --test; then
                        echo -e "${GREEN}✓ Test notification berhasil dikirim.${RESET}"
                    else
                        echo -e "${RED}✗ Test notification gagal.${RESET}"
                    fi
                fi
                pause_screen
                ;;
            4)
                load_telegram_config
                if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
                    echo
                    echo -e "${RED}Bot Token dan Chat ID harus diisi terlebih dahulu.${RESET}"
                else
                    TELEGRAM_ENABLED="true"
                    save_telegram_config
                    echo
                    echo -e "${GREEN}Telegram notification diaktifkan.${RESET}"
                fi
                pause_screen
                ;;
            5)
                TELEGRAM_ENABLED="false"
                save_telegram_config
                echo
                echo "Telegram notification dinonaktifkan."
                pause_screen
                ;;
            0|00|q|Q)
                return
                ;;
            *)
                echo
                echo -e "${RED}Pilihan tidak valid.${RESET}"
                pause_screen
                ;;
        esac
    done
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
                auto_maintenance_menu
                ;;
            6|06)
                auto_reboot_menu
                ;;
            7|07)
                memory_swap
                ;;
            8|08)
                clean_log
                ;;
            9|09)
                clear_cache
                ;;
            10)
                info_port
                ;;
            11)
                telegram_menu
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

if [[ "${1:-}" == "--auto-maintenance" ]]; then
    run_auto_maintenance
    exit 0
fi

main_menu
