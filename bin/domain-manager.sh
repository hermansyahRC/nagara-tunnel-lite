#!/usr/bin/env bash

APP_DIR="/opt/nagara-tunnel-lite"
CONFIG="$APP_DIR/config/config.conf"

mkdir -p "$APP_DIR/config"

pause_menu() {
    echo
    read -r -p "Press Enter to continue..." _
}

header() {
    clear
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║                  DOMAIN / SSL MANAGER                ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo
}

get_public_ip() {
    curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true
}

get_domain() {
    if [[ -f "$CONFIG" ]]; then
        grep '^DOMAIN=' "$CONFIG" 2>/dev/null | cut -d'=' -f2- | tr -d '"'
    fi
}

valid_domain() {
    local domain="$1"

    [[ -n "$domain" ]] || return 1

    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || return 1

    [[ "$domain" == *.* ]] || return 1

    return 0
}

set_domain() {
    header
    echo "SET DOMAIN"
    echo "────────────────────────────────────────────────────────"
    echo

    local domain
    read -r -p "Masukkan domain : " domain

    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%/}"

    if ! valid_domain "$domain"; then
        echo
        echo "✗ Format domain tidak valid."
        pause_menu
        return
    fi

    touch "$CONFIG"

    if grep -q '^DOMAIN=' "$CONFIG"; then
        sed -i "s|^DOMAIN=.*|DOMAIN=\"$domain\"|" "$CONFIG"
    else
        echo "DOMAIN=\"$domain\"" >> "$CONFIG"
    fi

    echo
    echo "✓ Domain berhasil disimpan."
    echo "  Domain : $domain"

    pause_menu
}

check_domain() {
    header
    echo "CHECK DOMAIN"
    echo "────────────────────────────────────────────────────────"
    echo

    local domain
    domain="$(get_domain)"

    if [[ -z "$domain" ]]; then
        echo "✗ Domain belum diset."
        pause_menu
        return
    fi

    echo "Domain : $domain"
    echo

    local server_ip
    server_ip="$(get_public_ip)"

    echo "IP VPS : ${server_ip:-Tidak diketahui}"

    echo
    echo "DNS A Record:"
    echo "────────────────────────────────────────────────────────"

    local dns_ip
    dns_ip="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | head -n 10)"

    if [[ -z "$dns_ip" ]]; then
        echo "✗ Tidak ditemukan A record."
        pause_menu
        return
    fi

    echo "$dns_ip"

    echo
    if [[ -n "$server_ip" ]] && echo "$dns_ip" | grep -qx "$server_ip"; then
        echo "✓ DNS domain mengarah ke IP VPS."
    else
        echo "⚠ DNS domain belum mengarah ke IP VPS."
    fi

    pause_menu
}

domain_status() {
    header
    echo "DOMAIN STATUS"
    echo "────────────────────────────────────────────────────────"
    echo

    local domain
    domain="$(get_domain)"

    local server_ip
    server_ip="$(get_public_ip)"

    echo "DOMAIN : ${domain:-NOT SET}"
    echo "VPS IP : ${server_ip:-UNKNOWN}"

    echo

    if [[ -n "$domain" ]]; then
        local dns_ip
        dns_ip="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | head -n 1)"

        if [[ -n "$dns_ip" ]]; then
            echo "DNS    : $dns_ip"

            if [[ -n "$server_ip" && "$dns_ip" == "$server_ip" ]]; then
                echo "STATUS : ✓ DOMAIN OK"
            else
                echo "STATUS : ⚠ DNS BELUM SESUAI"
            fi
        else
            echo "DNS    : NOT FOUND"
            echo "STATUS : ✗ DOMAIN BELUM AKTIF"
        fi
    else
        echo "DNS    : -"
        echo "STATUS : ✗ DOMAIN BELUM DISET"
    fi

    echo
    echo "NGINX  : $(systemctl is-active nginx 2>/dev/null || echo inactive)"

    if command -v certbot >/dev/null 2>&1; then
        echo "CERTBOT: installed"
    else
        echo "CERTBOT: not installed"
    fi

    pause_menu
}

show_menu() {
    header

    echo "  1. SET DOMAIN"
    echo "  2. CHECK DOMAIN"
    echo "  3. DOMAIN STATUS"
    echo "  4. NGINX MANAGER"
    echo "  0. BACK"
    echo
    echo "────────────────────────────────────────────────────────"
    echo
    read -r -p "  Select From Options [ 0 - 4 ] : " choice

    case "$choice" in
        1) set_domain ;;
        2) check_domain ;;
        3) domain_status ;;
        4) bash "$APP_DIR/bin/nginx-manager.sh" ;;
        0) exit 0 ;;
        *) echo; echo "✗ Pilihan tidak valid."; sleep 1 ;;
    esac
}

while true; do
    show_menu || exit 0
done
