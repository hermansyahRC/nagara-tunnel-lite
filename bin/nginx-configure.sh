#!/usr/bin/env bash

DOMAIN="$(grep '^DOMAIN=' /opt/nagara-tunnel-lite/config/config.conf 2>/dev/null | cut -d'=' -f2- | tr -d '"')"

if [[ -z "$DOMAIN" ]]; then
    echo "✗ DOMAIN belum diset."
    exit 1
fi

cat > "/etc/nginx/sites-available/nagara-tunnel-lite" <<NGINX
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN;

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

    location /trojan-ws {
        proxy_redirect off;
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_pass http://127.0.0.1:10003;
    }

    location / {
        return 200 "Nagara Tunnel Lite OK\n";
        add_header Content-Type text/plain;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/nagara-tunnel-lite \
       /etc/nginx/sites-enabled/nagara-tunnel-lite

rm -f /etc/nginx/sites-enabled/default

echo
echo "=== TEST NGINX CONFIG ==="

if nginx -t; then
    systemctl reload nginx

    if systemctl is-active --quiet nginx; then
        echo
        echo "✓ Nginx configuration berhasil."
        echo "✓ Nginx berhasil di-reload."
    else
        echo
        echo "✗ Nginx tidak aktif."
        exit 1
    fi
else
    echo
    echo "✗ Konfigurasi Nginx gagal."
    exit 1
fi
