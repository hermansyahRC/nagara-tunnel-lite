#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="Nagara Tunnel Lite"
APP_VERSION="2.1.0"

APP_DIR="/opt/nagara-tunnel-lite"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/nagara-tunnel-lite"

BIN_LINK="/usr/local/bin/menu"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${CYAN}[NAGARA]${NC} $1"
}

success() {
    echo -e "${GREEN}[ OK ]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error "Installer harus dijalankan sebagai root."
        exit 1
    fi
}

check_os() {
    log "Memeriksa sistem..."

    if [[ ! -f /etc/os-release ]]; then
        error "Tidak dapat mendeteksi sistem operasi."
        exit 1
    fi

    . /etc/os-release

    if [[ "${ID}" != "ubuntu" ]]; then
        error "Nagara Tunnel Lite membutuhkan Ubuntu."
        error "OS terdeteksi: ${PRETTY_NAME}"
        exit 1
    fi

    success "OS: ${PRETTY_NAME}"
}

update_system() {
    log "Memperbarui sistem..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y

    success "APT update selesai."
}

install_dependencies() {
    log "Menginstal dependency dasar..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get install -y \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg \
        unzip \
        tar \
        gzip \
        jq \
        sqlite3 \
        openssl \
        socat \
        net-tools \
        iproute2 \
        procps \
        lsof \
        nano \
        cron \
        nginx \
        certbot \
        python3-certbot-nginx \
        dropbear \
        haproxy \
        fail2ban

    success "Dependency dan service utama selesai."
}

install_xray() {
    log "Memasang Xray..."

    local xray_installer="/tmp/nagara-xray-install.sh"

    if ! curl -fsSL \
        "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" \
        -o "${xray_installer}"; then
        warning "Gagal mengunduh installer Xray."
        return 1
    fi

    if ! bash -n "${xray_installer}"; then
        warning "Installer Xray tidak lolos pengecekan sintaks."
        rm -f "${xray_installer}"
        return 1
    fi

    if ! bash "${xray_installer}"; then
        warning "Instalasi Xray gagal."
        rm -f "${xray_installer}"
        return 1
    fi

    rm -f "${xray_installer}"

    if command -v xray >/dev/null 2>&1; then
        success "Xray berhasil dipasang: $(xray -version | head -n 1)"
    else
        warning "Binary Xray belum ditemukan."
        return 1
    fi
}


create_xray_config() {
    log "Menyiapkan konfigurasi Xray..."

    local xray_dir="/usr/local/etc/xray"
    local xray_config="${xray_dir}/config.json"

    mkdir -p "${xray_dir}"
    mkdir -p /var/log/xray

    if [[ -f "${xray_config}" ]]; then
        cp -a "${xray_config}" "${xray_config}.nagara.bak"
    fi

    cat > "${xray_config}" <<'XRAY_CONFIG'
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "stats": {},
  "api": {
    "services": [
      "StatsService"
    ],
    "tag": "api"
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/nagara-ws"
        }
      },
      "tag": "vless-ws"
    },
    {
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess-ws"
        }
      },
      "tag": "vmess-ws"
    },
    {
      "listen": "127.0.0.1",
      "port": 10003,
      "protocol": "trojan",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojan-ws"
        }
      },
      "tag": "trojan-ws"
    },
    {
      "listen": "127.0.0.1",
      "port": 10004,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vmess-grpc"
        }
      },
      "tag": "vmess-grpc"
    },
    {
      "listen": "127.0.0.1",
      "port": 10005,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vless-grpc"
        }
      },
      "tag": "vless-grpc"
    },
    {
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "freedom",
      "tag": "api"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api"
      }
    ]
  }
}
XRAY_CONFIG

    if xray -test -config "${xray_config}" >/dev/null 2>&1; then
        success "Konfigurasi Xray + API valid."
    else
        warning "Konfigurasi Xray tidak valid."
        return 1
    fi
}

configure_nginx() {
    log "Menyiapkan konfigurasi Nginx..."

    local domain
    domain="$(get_domain)"

    if [[ -z "${domain}" ]]; then
        warning "Domain belum diatur. Nginx akan memakai konfigurasi dasar."
        return 0
    fi

    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    mkdir -p /var/www/nagara-acme

    cat > "/etc/nginx/sites-available/nagara-tunnel" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/nagara-acme;
        default_type "text/plain";
    }

    location /nagara-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /vmess-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /trojan-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /vmess-grpc {
        grpc_pass grpc://127.0.0.1:10004;
    }

    location /vless-grpc {
        grpc_pass grpc://127.0.0.1:10005;
    }

    location / {
        return 404;
    }
}
NGINX

    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/nagara-tunnel \
        /etc/nginx/sites-enabled/nagara-tunnel

    if nginx -t >/dev/null 2>&1; then
        systemctl enable nginx >/dev/null 2>&1 || true
        systemctl restart nginx >/dev/null 2>&1 || true
        success "Konfigurasi Nginx HTTP berhasil."
    else
        warning "Konfigurasi Nginx tidak valid."
        return 1
    fi
}

configure_ssl() {
    log "Menyiapkan SSL Let's Encrypt..."

    local domain
    domain="$(get_domain)"

    if [[ -z "${domain}" ]]; then
        warning "Domain belum diatur. SSL dilewati."
        return 0
    fi

    if ! command -v certbot >/dev/null 2>&1; then
        warning "Certbot belum tersedia. SSL dilewati."
        return 0
    fi

    if ! getent hosts "${domain}" >/dev/null 2>&1; then
        warning "Domain ${domain} belum bisa di-resolve. SSL dilewati."
        return 0
    fi

    mkdir -p /var/www/nagara-acme

    log "Menerbitkan sertifikat untuk ${domain}..."

    if certbot certonly \
        --webroot \
        -w /var/www/nagara-acme \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        -d "${domain}"; then

        success "SSL berhasil diterbitkan untuk ${domain}."

        local cert_dir="/etc/letsencrypt/live/${domain}"

        if [[ ! -f "${cert_dir}/fullchain.pem" || ! -f "${cert_dir}/privkey.pem" ]]; then
            warning "File sertifikat tidak ditemukan."
            return 1
        fi

        cat >> "/etc/nginx/sites-available/nagara-tunnel" <<NGINX

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};

    ssl_certificate ${cert_dir}/fullchain.pem;
    ssl_certificate_key ${cert_dir}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;

    location /nagara-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /vmess-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /trojan-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /vmess-grpc {
        grpc_pass grpc://127.0.0.1:10004;
    }

    location /vless-grpc {
        grpc_pass grpc://127.0.0.1:10005;
    }

    location / {
        return 404;
    }
}
NGINX

        if nginx -t >/dev/null 2>&1; then
            systemctl reload nginx >/dev/null 2>&1 || true
            success "HTTPS 443 berhasil dikonfigurasi."
            success "HTTP 80 tetap dipertahankan."
        else
            warning "Konfigurasi Nginx HTTPS tidak valid."
            return 1
        fi
    else
        warning "SSL belum berhasil diterbitkan."
        warning "Instalasi tetap dilanjutkan tanpa SSL."
    fi
}

configure_dropbear() {
    log "Menyiapkan Dropbear..."

    local config="/etc/default/dropbear"

    if [[ -f "${config}" ]]; then
        cp -a "${config}" "${config}.nagara.bak"
    fi

    cat > "${config}" <<'DROPBEAR'
# Nagara Tunnel Lite - Dropbear

NO_START=0
DROPBEAR_PORT=2222
DROPBEAR_EXTRA_ARGS=""
DROPBEAR
    if systemctl enable dropbear >/dev/null 2>&1; then
        systemctl restart dropbear >/dev/null 2>&1 || true
    fi

    if systemctl is-active --quiet dropbear 2>/dev/null; then
        success "Dropbear aktif pada port 2222."
    else
        warning "Dropbear belum aktif."
    fi
}

configure_haproxy() {
    log "Menyiapkan HAProxy..."

    local config="/etc/haproxy/haproxy.cfg"

    if [[ -f "${config}" ]]; then
        cp -a "${config}" "${config}.nagara.bak"
    fi

    cat > "${config}" <<'HAPROXY'
#---------------------------------------------------------------------
# Nagara Tunnel Lite - HAProxy
#---------------------------------------------------------------------

global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

    stats socket /run/haproxy/admin.sock mode 660 level admin

defaults
    log global
    mode tcp

    option dontlognull

    timeout connect 5s
    timeout client 30s
    timeout server 30s

# HAProxy belum mengambil port publik.
# Nginx tetap menangani port 80 dan 443.
#
# Frontend/backend dapat ditambahkan pada tahap berikutnya.
HAPROXY

    if haproxy -c -f "${config}" >/dev/null 2>&1; then
        systemctl enable haproxy >/dev/null 2>&1 || true
        systemctl restart haproxy >/dev/null 2>&1 || true

        if systemctl is-active --quiet haproxy 2>/dev/null; then
            success "HAProxy aktif."
        else
            warning "HAProxy terpasang tetapi belum aktif."
        fi
    else
        warning "Konfigurasi HAProxy tidak valid."
        return 1
    fi
}

configure_fail2ban() {
    log "Menyiapkan Fail2ban..."

    mkdir -p /etc/fail2ban/jail.d
    mkdir -p /etc/fail2ban/filter.d

    cat > /etc/fail2ban/filter.d/nagara-dropbear.conf <<'DROPBEAR_FILTER'
[Definition]
failregex = ^.*dropbear.*(Exit before auth|Bad password|Auth error|authentication failed).*$
ignoreregex =
DROPBEAR_FILTER

    cat > /etc/fail2ban/jail.d/nagara-ssh.conf <<'FAIL2BAN'
[sshd]
enabled = true
port = 22
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h

[nagara-dropbear]
enabled = true
port = 2222
filter = nagara-dropbear
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
FAIL2BAN

    if fail2ban-client -t >/dev/null 2>&1; then
        systemctl enable fail2ban >/dev/null 2>&1 || true
        systemctl restart fail2ban >/dev/null 2>&1 || true

        if systemctl is-active --quiet fail2ban 2>/dev/null; then
            success "Fail2ban aktif."
        else
            warning "Fail2ban terpasang tetapi belum aktif."
        fi
    else
        warning "Konfigurasi Fail2ban belum valid."
        return 1
    fi
}

create_directories() {
    log "Membuat direktori aplikasi..."

    mkdir -p \
        "${APP_DIR}" \
        "${APP_DIR}/core" \
        "${APP_DIR}/bin" \
        "${APP_DIR}/config" \
        "${APP_DIR}/users" \
        "${APP_DIR}/runtime" \
        "${APP_DIR}/logs" \
        "${APP_DIR}/backups" \
        "${LOG_DIR}"

    success "Direktori aplikasi siap."
}

copy_project() {
    log "Menyiapkan file Nagara Tunnel Lite..."

    if [[ "${REPO_DIR}" != "${APP_DIR}" ]]; then
        cp -a "${REPO_DIR}/." "${APP_DIR}/"
    fi

    chmod +x "${APP_DIR}/install.sh" 2>/dev/null || true
    chmod +x "${APP_DIR}/menu.sh" 2>/dev/null || true
    chmod +x "${APP_DIR}/bin/"*.sh 2>/dev/null || true
    chmod +x "${APP_DIR}/core/"*.sh 2>/dev/null || true

    success "File aplikasi siap."
}

ask_domain() {
    local domain

    echo
    echo "=========================================="
    echo "        NAGARA TUNNEL LITE - DOMAIN"
    echo "=========================================="
    echo
    echo "Masukkan domain yang sudah diarahkan ke VPS."
    echo "Contoh: vpn.example.com"
    echo
    read -r -p "Domain: " domain

    if [[ -z "${domain}" ]]; then
        warning "Domain kosong. Instalasi tetap dilanjutkan."
        return 0
    fi

    if [[ ! "${domain}" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        warning "Format domain terlihat tidak valid."
        return 0
    fi

    mkdir -p "${APP_DIR}/config"

    if [[ -f "${APP_DIR}/config/config.conf" ]]; then
        sed -i "s/^DOMAIN=.*/DOMAIN=\"${domain}\"/" \
            "${APP_DIR}/config/config.conf"
    fi

    success "Domain disimpan: ${domain}"
}

get_domain() {
    local config="${APP_DIR}/config/config.conf"

    if [[ -f "${config}" ]]; then
        grep '^DOMAIN=' "${config}" 2>/dev/null | head -n 1 | cut -d '"' -f 2
    fi
}

create_config() {
    log "Membuat konfigurasi Nagara..."

    cat > "${APP_DIR}/config/config.conf" <<EOF_CONFIG
# Nagara Tunnel Lite
APP_NAME="${APP_NAME}"
APP_VERSION="${APP_VERSION}"

APP_DIR="${APP_DIR}"
LOG_DIR="${LOG_DIR}"

DOMAIN=""
NGINX_ENABLED="true"
SSL_ENABLED="false"
XRAY_ENABLED="true"
HAPROXY_ENABLED="true"
DROPBEAR_ENABLED="true"
FAIL2BAN_ENABLED="true"

VMESS_ENABLED="true"
VLESS_ENABLED="true"
TROJAN_ENABLED="true"
EOF_CONFIG

    success "Konfigurasi utama dibuat."
}

create_database() {
    log "Membuat database user..."

    local db="${APP_DIR}/users/users.db"

    sqlite3 "${db}" <<'SQL'
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    protocol TEXT NOT NULL,
    uuid TEXT,
    password TEXT,
    limit_ip INTEGER DEFAULT 1,
    expiry_date TEXT,
    status TEXT DEFAULT 'active',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
SQL

    chmod 600 "${db}"

    success "Database siap."
}

create_nagara_command() {
    log "Membuat command Nagara..."

    cat > "${BIN_LINK}" <<EOF_MENU
#!/usr/bin/env bash
exec "${APP_DIR}/menu.sh" "\$@"
EOF_MENU

    chmod +x "${BIN_LINK}"

    cat > /usr/local/bin/nagara <<EOF_NAGARA
#!/usr/bin/env bash
exec "${APP_DIR}/menu.sh" "\$@"
EOF_NAGARA

    chmod +x /usr/local/bin/nagara

    success "Command 'menu' tersedia."
    success "Command 'nagara' tetap tersedia."
}

enable_services() {
    log "Mengaktifkan service..."

    local services=(
        "cron"
        "nginx"
        "xray"
        "dropbear"
        "haproxy"
        "fail2ban"
    )

    local service

    for service in "${services[@]}"; do
        if systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
            systemctl enable "${service}" >/dev/null 2>&1 || true
            systemctl restart "${service}" >/dev/null 2>&1 || true

            if systemctl is-active --quiet "${service}" 2>/dev/null; then
                success "${service}: aktif"
            else
                warning "${service}: belum aktif"
            fi
        else
            warning "${service}: service tidak ditemukan"
        fi
    done
}


final_check() {
    log "Menjalankan pengecekan akhir..."

    local failed=0
    local domain
    domain="$(get_domain)"

    echo
    echo "=============================================================="
    echo "                    FINAL CHECK"
    echo "=============================================================="

    if [[ -d "${APP_DIR}" ]]; then
        echo "APP          : OK"
    else
        echo "APP          : FAILED"
        failed=1
    fi

    if [[ -f "${APP_DIR}/config/config.conf" ]]; then
        echo "CONFIG       : OK"
    else
        echo "CONFIG       : FAILED"
        failed=1
    fi

    if [[ -f "${APP_DIR}/users/users.db" ]]; then
        echo "DATABASE     : OK"
    else
        echo "DATABASE     : FAILED"
        failed=1
    fi

    if [[ -x "${BIN_LINK}" ]]; then
        echo "COMMAND      : OK"
    else
        echo "COMMAND      : FAILED"
        failed=1
    fi

    echo "--------------------------------------------------------------"

    if command -v xray >/dev/null 2>&1 &&
       [[ -f "/usr/local/etc/xray/config.json" ]] &&
       xray -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1; then
        echo "XRAY         : ON"
    else
        echo "XRAY         : FAILED"
        failed=1
    fi

    for service in nginx dropbear haproxy fail2ban cron; do
        if systemctl is-active --quiet "${service}" 2>/dev/null; then
            echo "$(printf '%-12s' "${service^^}") : ON"
        else
            echo "$(printf '%-12s' "${service^^}") : OFF"
            failed=1
        fi
    done

    echo "--------------------------------------------------------------"

    if [[ -n "${domain}" ]]; then
        local cert_dir="/etc/letsencrypt/live/${domain}"

        if [[ -f "${cert_dir}/fullchain.pem" &&
              -f "${cert_dir}/privkey.pem" ]]; then
            echo "SSL          : OK"
        else
            echo "SSL          : SKIPPED / NOT AVAILABLE"
        fi
    else
        echo "SSL          : SKIPPED / NO DOMAIN"
    fi

    echo "=============================================================="

    if [[ "${failed}" -eq 0 ]]; then
        success "Pengecekan akhir berhasil."
    else
        error "Pengecekan akhir menemukan service atau komponen yang bermasalah."
        return 1
    fi
}

show_complete() {
    local domain
    domain="$(get_domain)"

    echo
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║              NAGARA TUNNEL LITE                     ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo
    echo "  Installer selesai."
    echo
    echo "  Version : ${APP_VERSION}"
    echo "  Path    : ${APP_DIR}"
    echo "  Domain  : ${domain:-belum diatur}"
    echo
    echo "  Service:"
    echo "    Nginx      : $(systemctl is-active nginx 2>/dev/null || true)"
    echo "    Xray       : $(systemctl is-active xray 2>/dev/null || true)"
    echo "    Dropbear   : $(systemctl is-active dropbear 2>/dev/null || true)"
    echo "    HAProxy    : $(systemctl is-active haproxy 2>/dev/null || true)"
    echo "    Fail2ban   : $(systemctl is-active fail2ban 2>/dev/null || true)"
    echo "    Cron       : $(systemctl is-active cron 2>/dev/null || true)"
    echo
    echo "  Akses:"
    echo "    Dashboard  : ${BIN_LINK}"
    echo "    SSH        : 22"
    echo "    Dropbear   : 2222"
    echo "    HTTP       : 80"
    echo "    HTTPS      : 443"
    echo
    echo "  SSL:"
    if [[ -n "${domain}" &&
          -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        echo "    Status     : Aktif"
    else
        echo "    Status     : Belum tersedia"
    fi
    echo
    echo "  Nagara Tunnel Lite siap digunakan."
    echo
}

main() {
    require_root

    echo
    log "${APP_NAME} v${APP_VERSION}"
    log "Nagara Tunnel Lite Installer"
    echo

    check_os
    update_system
    install_dependencies

    create_directories
    copy_project
    create_config

    ask_domain

    install_xray
    create_xray_config

    configure_nginx
    configure_ssl
    configure_dropbear
    configure_haproxy
    configure_fail2ban

    create_database
    create_nagara_command
    enable_services

    final_check
    show_complete
}

main "$@"
