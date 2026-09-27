#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="Nagara Tunnel Lite"
APP_VERSION="2.0.0"
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
        warning "Nagara Tunnel Lite saat ini ditargetkan untuk Ubuntu."
        warning "OS terdeteksi: ${PRETTY_NAME}"
        exit 1
    fi

    success "OS: ${PRETTY_NAME}"
}

update_system() {
    log "Memperbarui daftar paket..."

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
        cron

    success "Dependency dasar selesai."
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
    log "Menyalin file Nagara Tunnel Lite..."

    if [[ "${REPO_DIR}" != "${APP_DIR}" ]]; then
        cp -a "${REPO_DIR}/." "${APP_DIR}/"
    fi

    chmod +x "${APP_DIR}/install.sh" 2>/dev/null || true
    chmod +x "${APP_DIR}/menu.sh" 2>/dev/null || true
    chmod +x "${APP_DIR}/bin/"*.sh 2>/dev/null || true
    chmod +x "${APP_DIR}/core/"*.sh 2>/dev/null || true

    success "File aplikasi tersalin."
}

create_settings() {
    log "Membuat konfigurasi dasar..."

    cat > "${APP_DIR}/config/settings.conf" <<EOF
# Nagara Tunnel Lite
APP_NAME="${APP_NAME}"
APP_VERSION="${APP_VERSION}"

APP_DIR="${APP_DIR}"
LOG_DIR="${LOG_DIR}"

XRAY_ENABLED="false"
NGINX_ENABLED="false"
SSL_ENABLED="false"
HAPROXY_ENABLED="false"
DROPBEAR_ENABLED="false"

DOMAIN=""
SSL_EMAIL=""

VMESS_ENABLED="true"
VLESS_ENABLED="true"
TROJAN_ENABLED="true"
EOF

    success "Konfigurasi dasar dibuat."
}

create_database() {
    log "Membuat database user..."

    DB="${APP_DIR}/users/users.db"

    sqlite3 "${DB}" <<'SQL'
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

    chmod 600 "${DB}"

    success "Database siap."
}

create_nagara_command() {
    log "Membuat command menu..."

    cat > "${BIN_LINK}" <<EOF
#!/bin/bash
exec "${APP_DIR}/menu.sh" "\$@"
EOF

    chmod +x "${BIN_LINK}"

    # Kompatibilitas command lama
    cat > /usr/local/bin/nagara <<EOF
#!/bin/bash
exec "${APP_DIR}/menu.sh" "\$@"
EOF

    chmod +x /usr/local/bin/nagara

    success "Command 'menu' tersedia."
    success "Command lama 'nagara' tetap tersedia."
}

final_check() {
    log "Menjalankan pengecekan akhir..."

    local failed=0

    [[ -d "${APP_DIR}" ]] || failed=1
    [[ -f "${APP_DIR}/config/settings.conf" ]] || failed=1
    [[ -f "${APP_DIR}/users/users.db" ]] || failed=1
    [[ -x "${BIN_LINK}" ]] || failed=1

    if [[ "${failed}" -eq 0 ]]; then
        success "Semua pengecekan dasar berhasil."
    else
        error "Pengecekan akhir menemukan masalah."
        exit 1
    fi
}

show_complete() {
    echo
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║              NAGARA TUNNEL LITE                      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo
    echo "  Installation Complete"
    echo
    echo "  Version : ${APP_VERSION}"
    echo "  Path    : ${APP_DIR}"
    echo
    echo "  Jalankan dashboard dengan:"
    echo
    echo "      menu"
    echo
}

main() {
    require_root

    echo
    log "${APP_NAME} v${APP_VERSION}"
    log "Memulai instalasi..."
    echo

    check_os
    update_system
    install_dependencies
    create_directories
    copy_project
    create_settings
    create_database
    create_nagara_command
    final_check
    show_complete
}

main "$@"
