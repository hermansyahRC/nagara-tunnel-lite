#!/usr/bin/env bash

APP_DIR="/opt/nagara-tunnel-lite"
CONFIG_FILE="$APP_DIR/config/config.conf"
NGINX_SITE="/etc/nginx/sites-available/nagara-tunnel-lite"

source "$APP_DIR/core/colors.sh" 2>/dev/null || true

DOMAIN="$(grep '^DOMAIN=' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2)"

if [[ -z "$DOMAIN" ]]; then
    echo "Domain belum dikonfigurasi."
    exit 1
fi

CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
FULLCHAIN="$CERT_DIR/fullchain.pem"
PRIVKEY="$CERT_DIR/privkey.pem"

pause_menu() {
    echo
    read -r -p "Press Enter to continue..." _
}

ssl_status() {
    echo
    echo "=== SSL STATUS ==="
    echo

    if [[ -f "$FULLCHAIN" && -f "$PRIVKEY" ]]; then
        echo "Certificate : FOUND"
        echo "Domain      : $DOMAIN"

        if command -v openssl >/dev/null 2>&1; then
            echo "Expiry      : $(openssl x509 -enddate -noout -in "$FULLCHAIN" | cut -d= -f2)"
        fi
    else
        echo "Certificate : NOT FOUND"
    fi

    echo
    if ss -lnt 2>/dev/null | grep -qE '0\.0\.0\.0:443|:::443'; then
        echo "HTTPS : ACTIVE"
    else
        echo "HTTPS : OFF"
    fi

    pause_menu
}

enable_https() {
    echo
    echo "=== ENABLE HTTPS ==="
    echo

    if [[ ! -f "$FULLCHAIN" || ! -f "$PRIVKEY" ]]; then
        echo "SSL certificate tidak ditemukan."
        pause_menu
        return
    fi

    cp "$NGINX_SITE" "$NGINX_SITE.bak.$(date +%Y%m%d-%H%M%S)"

    cat > "$NGINX_SITE" <<NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $DOMAIN;

    ssl_certificate $FULLCHAIN;
    ssl_certificate_key $PRIVKEY;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    location /nagara-ws {
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:10001;
    }

    location /vmess-ws {
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:10002;
    }

    location / {
        return 200 "Nagara Tunnel Lite HTTPS OK\n";
        add_header Content-Type text/plain;
    }
}
NGINXEOF

    if nginx -t; then
        systemctl reload nginx
        echo
        echo "HTTPS berhasil diaktifkan."
    else
        echo
        echo "NGINX CONFIG ERROR."
        echo "Backup konfigurasi dibuat sebelum perubahan."
        exit 1
    fi

    pause_menu
}

install_ssl() {
    echo
    echo "=== SSL CERTBOT ==="
    echo

    if [[ -f "$FULLCHAIN" && -f "$PRIVKEY" ]]; then
        echo "Certificate sudah tersedia."
        pause_menu
        return
    fi

    certbot certonly --nginx -d "$DOMAIN"
}

while true; do
    clear
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║                 SSL MANAGER                          ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo
    echo "  Domain : $DOMAIN"
    echo
    echo "  1. INSTALL / REQUEST SSL"
    echo "  2. ENABLE HTTPS"
    echo "  3. SSL STATUS"
    echo "  0. BACK"
    echo
    read -r -p "  Select From Options [ 0 - 3 ] : " choice

    case "$choice" in
        1) install_ssl ;;
        2) enable_https ;;
        3) ssl_status ;;
        0) exit 0 ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done
