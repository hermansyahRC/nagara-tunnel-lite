#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="/opt/nagara-tunnel-lite"
BUILDER="$BASE_DIR/core/xray-config.sh"

XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_SERVICE="xray"

BACKUP_DIR="/opt/nagara-tunnel-lite/backups/xray"

timestamp() {
    date '+%Y%m%d-%H%M%S'
}

log() {
    echo "[XRAY-SYNC] $*"
}

die() {
    echo "[XRAY-SYNC] ERROR: $*" >&2
    exit 1
}

mkdir -p "$BACKUP_DIR"

[[ -x "$BUILDER" ]] || die "Xray config builder tidak ditemukan: $BUILDER"
[[ -f "$XRAY_CONFIG" ]] || die "Xray config tidak ditemukan: $XRAY_CONFIG"

BACKUP_FILE="$BACKUP_DIR/config-$(timestamp).json"

log "Backup config aktif..."
cp -a "$XRAY_CONFIG" "$BACKUP_FILE"

log "Membangun config baru..."
"$BUILDER"

log "Testing config baru..."
if ! /usr/local/bin/xray run -test -config "$XRAY_CONFIG"; then
    log "Config baru ERROR. Mengembalikan config sebelumnya..."
    cp -a "$BACKUP_FILE" "$XRAY_CONFIG"
    die "Sync dibatalkan."
fi

log "Restart Xray..."
if systemctl restart "$XRAY_SERVICE"; then
    sleep 1
else
    log "Restart gagal. Rollback config..."
    cp -a "$BACKUP_FILE" "$XRAY_CONFIG"
    systemctl restart "$XRAY_SERVICE" || true
    die "Xray gagal restart."
fi

if systemctl is-active --quiet "$XRAY_SERVICE"; then
    log "Xray berhasil aktif."
    log "Sync selesai."
else
    log "Xray tidak aktif setelah restart."
    log "Rollback config sebelumnya..."

    cp -a "$BACKUP_FILE" "$XRAY_CONFIG"
    systemctl restart "$XRAY_SERVICE" || true

    die "Sync gagal. Config sebelumnya telah dikembalikan."
fi
