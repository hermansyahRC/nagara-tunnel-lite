#!/usr/bin/env bash

APP_DIR="/opt/nagara-tunnel-lite"
CONFIG="$APP_DIR/config/config.conf"

pause_menu() {
    echo
    read -r -p "Press Enter to continue..." _
}

header() {
    clear
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║                    NGINX MANAGER                     ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo
}

nginx_status() {
    systemctl is-active nginx 2>/dev/null || echo "inactive"
}

install_nginx() {
    header
    echo "INSTALL NGINX"
    echo "────────────────────────────────────────────────────────"
    echo

    if command -v nginx >/dev/null 2>&1; then
        echo "✓ Nginx sudah terpasang."
        echo "  Version : $(nginx -v 2>&1)"
        pause_menu
        return
    fi

    echo "Menginstall Nginx..."
    echo

    if apt-get update && apt-get install -y nginx; then
        echo
        echo "✓ Nginx berhasil diinstall."

        systemctl enable nginx >/dev/null 2>&1
        systemctl start nginx

        if systemctl is-active --quiet nginx; then
            echo "✓ Nginx berhasil dijalankan."
        else
            echo "⚠ Nginx terinstall tetapi service belum aktif."
        fi

        if [[ -f "$CONFIG" ]]; then
            if grep -q '^NGINX_ENABLED=' "$CONFIG"; then
                sed -i 's/^NGINX_ENABLED=.*/NGINX_ENABLED="true"/' "$CONFIG"
            else
                echo 'NGINX_ENABLED="true"' >> "$CONFIG"
            fi
        fi
    else
        echo
        echo "✗ Gagal menginstall Nginx."
    fi

    pause_menu
}

show_status() {
    header
    echo "NGINX STATUS"
    echo "────────────────────────────────────────────────────────"
    echo

    if command -v nginx >/dev/null 2>&1; then
        echo "Installed : YES"
        echo "Version   : $(nginx -v 2>&1)"
        echo "Service   : $(nginx_status)"
    else
        echo "Installed : NO"
        echo "Service   : inactive"
    fi

    echo

    if systemctl is-enabled --quiet nginx 2>/dev/null; then
        echo "Autostart : ENABLED"
    else
        echo "Autostart : DISABLED"
    fi

    pause_menu
}

test_config() {
    header
    echo "TEST NGINX CONFIG"
    echo "────────────────────────────────────────────────────────"
    echo

    if ! command -v nginx >/dev/null 2>&1; then
        echo "✗ Nginx belum terinstall."
        pause_menu
        return
    fi

    nginx -t

    pause_menu
}

restart_nginx() {
    header
    echo "RESTART NGINX"
    echo "────────────────────────────────────────────────────────"
    echo

    if ! command -v nginx >/dev/null 2>&1; then
        echo "✗ Nginx belum terinstall."
        pause_menu
        return
    fi

    if ! nginx -t; then
        echo
        echo "✗ Config Nginx tidak valid."
        echo "Nginx tidak direstart."
        pause_menu
        return
    fi

    systemctl restart nginx

    if systemctl is-active --quiet nginx; then
        echo
        echo "✓ Nginx berhasil direstart."
    else
        echo
        echo "✗ Nginx gagal aktif setelah restart."
    fi

    pause_menu
}

stop_nginx() {
    header
    echo "STOP NGINX"
    echo "────────────────────────────────────────────────────────"
    echo

    if ! command -v nginx >/dev/null 2>&1; then
        echo "✗ Nginx belum terinstall."
        pause_menu
        return
    fi

    systemctl stop nginx

    if ! systemctl is-active --quiet nginx; then
        echo "✓ Nginx berhasil dihentikan."
    else
        echo "✗ Nginx masih aktif."
    fi

    pause_menu
}

show_menu() {
    header

    echo "  1. INSTALL NGINX"
    echo "  2. NGINX STATUS"
    echo "  3. TEST CONFIG"
    echo "  4. RESTART NGINX"
    echo "  5. STOP NGINX"
    echo "  0. BACK"
    echo
    echo "────────────────────────────────────────────────────────"
    echo
    read -r -p "  Select From Options [ 0 - 5 ] : " choice

    case "$choice" in
        1) install_nginx ;;
        2) show_status ;;
        3) test_config ;;
        4) restart_nginx ;;
        5) stop_nginx ;;
        0) exit 0 ;;
        *) echo; echo "✗ Pilihan tidak valid."; sleep 1 ;;
    esac
}

while true; do
    show_menu || exit 0
done
