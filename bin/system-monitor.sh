#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/nagara-tunnel-lite"
CONFIG_FILE="${APP_DIR}/config/config.conf"
STATS="${APP_DIR}/core/xray-stats.sh"

human_bytes() {
    awk -v bytes="${1:-0}" '
    BEGIN {
        if (bytes < 1024)
            printf "%.0f B", bytes
        else if (bytes < 1024^2)
            printf "%.2f KB", bytes/1024
        else if (bytes < 1024^3)
            printf "%.2f MB", bytes/1024^2
        else if (bytes < 1024^4)
            printf "%.2f GB", bytes/1024^3
        else
            printf "%.2f TB", bytes/1024^4
    }'
}

get_domain() {
    local domain=""

    if [[ -f "$CONFIG_FILE" ]]; then
        domain="$(awk -F= '/^DOMAIN=/{print $2}' "$CONFIG_FILE" | tail -1 | tr -d '"')"
    fi

    [[ -n "$domain" ]] && echo "$domain" || echo "-"
}

get_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

get_isp() {
    local isp
    isp="$(curl -fsS --max-time 3 https://ipinfo.io/org 2>/dev/null || true)"
    [[ -n "$isp" ]] && echo "$isp" || echo "-"
}

get_city() {
    local city
    city="$(curl -fsS --max-time 3 https://ipinfo.io/city 2>/dev/null || true)"
    [[ -n "$city" ]] && echo "$city" || echo "-"
}

service_status() {
    local service="$1"

    if ! command -v systemctl >/dev/null 2>&1; then
        echo "UNKNOWN"
        return
    fi

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "ON"
    elif systemctl list-unit-files --type=service 2>/dev/null \
        | awk '{print $1}' \
        | grep -qx "${service}.service"; then
        echo "OFF"
    else
        echo "NOT INSTALLED"
    fi
}

show_header() {
    clear 2>/dev/null || true

    echo
    echo "=============================================================="
    echo "                    NAGARA SYSTEM MONITOR"
    echo "=============================================================="
    echo
}

show_server_info() {
    local os
    local ram
    local cpu
    local disk
    local uptime
    local ip
    local domain
    local isp
    local city

    os="$(. /etc/os-release && echo "$PRETTY_NAME")"
    ram="$(free -h | awk '/^Mem:/{print $2}')"
    cpu="$(nproc)"
    disk="$(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')"
    uptime="$(uptime -p 2>/dev/null || true)"
    ip="$(get_ip)"
    domain="$(get_domain)"
    isp="$(get_isp)"
    city="$(get_city)"

    echo "SERVER INFORMATION"
    echo "--------------------------------------------------------------"
    printf "%-14s : %s\n" "OS" "$os"
    printf "%-14s : %s\n" "RAM" "$ram"
    printf "%-14s : %s Core\n" "CPU" "$cpu"
    printf "%-14s : %s\n" "DISK" "$disk"
    printf "%-14s : %s\n" "UPTIME" "$uptime"
    printf "%-14s : %s\n" "IP" "$ip"
    printf "%-14s : %s\n" "ISP" "$isp"
    printf "%-14s : %s\n" "CITY" "$city"
    printf "%-14s : %s\n" "DOMAIN" "$domain"
    echo
}

show_services() {
    echo "SERVICES"
    echo "--------------------------------------------------------------"

    printf "%-14s : %s\n" "SSH" "$(service_status ssh)"
    printf "%-14s : %s\n" "XRAY" "$(service_status xray)"
    printf "%-14s : %s\n" "NGINX" "$(service_status nginx)"
    printf "%-14s : %s\n" "DROPBEAR" "$(service_status dropbear)"
    printf "%-14s : %s\n" "HAPROXY" "$(service_status haproxy)"
    printf "%-14s : %s\n" "FAIL2BAN" "$(service_status fail2ban)"
    printf "%-14s : %s\n" "CRON" "$(service_status cron)"

    echo
}

show_traffic() {
    echo "XRAY TRAFFIC"
    echo "--------------------------------------------------------------"

    if [[ -x "$STATS" ]]; then
        "$STATS" traffic
    else
        echo "Traffic monitor tidak ditemukan."
        echo
    fi
}

main() {
    show_header
    show_server_info
    show_services
    show_traffic
}

main "$@"
