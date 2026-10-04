#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="/opt/nagara-tunnel-lite"
DB="$BASE_DIR/users/users.db"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
SYNC="$BASE_DIR/core/xray-sync.sh"

[[ -f "$DB" ]] || exit 0
[[ -f "$XRAY_CONFIG" ]] || exit 0
[[ -x "$SYNC" ]] || exit 0

expired_found=0

while IFS= read -r username; do
    [[ -n "$username" ]] || continue

    # Xray memakai email "nagara-USERNAME".
    # -F = pencarian literal, aman untuk username dengan karakter khusus.
    if grep -qF "\"nagara-${username}\"" "$XRAY_CONFIG"; then
        echo "[XRAY-EXPIRY] Expired account masih ada di config: $username"
        expired_found=1
        break
    fi
done < <(
    sqlite3 -noheader "$DB" "
        SELECT username
        FROM users
        WHERE LOWER(status)='active'
          AND expiry_date IS NOT NULL
          AND (
              (length(expiry_date)=10 AND expiry_date < date('now'))
              OR
              (length(expiry_date)>10 AND datetime(expiry_date) < datetime('now'))
          )
        ORDER BY id;
    "
)

if (( expired_found == 1 )); then
    echo "[XRAY-EXPIRY] Menjalankan Xray sync..."
    "$SYNC"
    echo "[XRAY-EXPIRY] Selesai."
else
    echo "[XRAY-EXPIRY] Tidak ada expired account yang masih aktif di config."
fi
