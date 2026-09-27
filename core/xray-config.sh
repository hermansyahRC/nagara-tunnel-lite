#!/usr/bin/env bash

set -Eeuo pipefail

APP_DIR="/opt/nagara-tunnel-lite"
DB="$APP_DIR/users/users.db"
XRAY_CONFIG="/usr/local/etc/xray/config.json"

die() {
    echo "[XRAY-BUILDER] ERROR: $*" >&2
    exit 1
}

[[ -f "$DB" ]] || die "Database tidak ditemukan: $DB"
[[ -f "$XRAY_CONFIG" ]] || die "Config Xray tidak ditemukan: $XRAY_CONFIG"
command -v python3 >/dev/null 2>&1 || die "python3 tidak ditemukan"
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 tidak ditemukan"

TMP_CONFIG="$(mktemp)"

cleanup() {
    rm -f "$TMP_CONFIG"
}
trap cleanup EXIT

python3 - "$DB" "$XRAY_CONFIG" "$TMP_CONFIG" <<'PY'
import json
import sqlite3
import sys
from datetime import date, datetime

db_path = sys.argv[1]
config_path = sys.argv[2]
tmp_path = sys.argv[3]

with open(config_path, "r", encoding="utf-8") as f:
    config = json.load(f)

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row

rows = conn.execute("""
    SELECT username, protocol, uuid, password, limit_ip, expiry_date, status
    FROM users
    ORDER BY id
""").fetchall()

now = datetime.now()
today = now.date()

active = []

for row in rows:
    status = (row["status"] or "").lower()
    expiry = (row["expiry_date"] or "").strip()

    if status != "active":
        continue

    if expiry:
        try:
            # Akun biasa: YYYY-MM-DD
            if len(expiry) == 10:
                expiry_date = datetime.strptime(expiry, "%Y-%m-%d").date()

                if expiry_date < today:
                    continue

            # Trial: YYYY-MM-DD HH:MM:SS
            else:
                expiry_datetime = datetime.strptime(
                    expiry,
                    "%Y-%m-%d %H:%M:%S"
                )

                if expiry_datetime < now:
                    continue

        except ValueError:
            # Format expiry tidak dikenal.
            # Biarkan perilaku aman: akun tidak dimasukkan ke Xray.
            continue

    active.append(row)

# ------------------------------------------------------------
# Build clients from database
# ------------------------------------------------------------

vless_clients = []
vmess_clients = []
trojan_clients = []

for row in active:
    protocol = (row["protocol"] or "").lower()
    username = row["username"]
    uuid = row["uuid"]
    password = row["password"]

    if protocol == "vless" and uuid:
        vless_clients.append({
            "id": uuid,
            "email": "nagara-" + username,
            "level": 0
        })

    elif protocol == "vmess" and uuid:
        vmess_clients.append({
            "id": uuid,
            "alterId": 0,
            "email": "nagara-" + username,
            "security": "auto",
            "level": 0
        })

    elif protocol == "trojan" and password:
        trojan_clients.append({
            "password": password,
            "email": "nagara-" + username,
            "level": 0
        })

# ------------------------------------------------------------
# Locate existing inbounds by tag
# ------------------------------------------------------------

inbounds = config.get("inbounds", [])

# Add VLESS gRPC inbound if it does not exist yet.
if not any(x.get("tag") == "vless-grpc-in" for x in inbounds):
    inbounds.append({
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
        "tag": "vless-grpc-in"
    })

for inbound in inbounds:
    tag = inbound.get("tag")

    if tag == "vless-in":
        inbound.setdefault("settings", {})["clients"] = vless_clients

    elif tag == "vmess-in":
        inbound.setdefault("settings", {})["clients"] = vmess_clients

    elif tag == "trojan-in":
        inbound.setdefault("settings", {})["clients"] = trojan_clients
        inbound["streamSettings"] = {
            "network": "ws",
            "wsSettings": {
                "path": "/trojan-ws"
            }
        }

    elif tag == "vmess-grpc-in":
        # Keep existing VMess gRPC clients, then add
        # all active VMess users so every VMess account
        # can use the same gRPC transport.
        settings = inbound.setdefault("settings", {})
        existing_clients = settings.setdefault("clients", [])

        existing_ids = {
            client.get("id")
            for client in existing_clients
            if client.get("id")
        }

        for client in vmess_clients:
            client_id = client.get("id")

            if client_id and client_id not in existing_ids:
                existing_clients.append(dict(client))
                existing_ids.add(client_id)

    elif tag == "vless-grpc-in":
        inbound.setdefault("settings", {})["clients"] = vless_clients

with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)
    f.write("\n")

conn.close()
PY

# Validasi JSON
python3 -m json.tool "$TMP_CONFIG" >/dev/null || {
    echo "[XRAY-BUILDER] ERROR: JSON hasil builder tidak valid."
    exit 1
}

# Ganti config secara atomic
cp -a "$TMP_CONFIG" "$XRAY_CONFIG"

# Pastikan Xray dapat membaca config setelah builder selesai.
chown root:root "$XRAY_CONFIG"
chmod 644 "$XRAY_CONFIG"

echo "[XRAY-BUILDER] Config berhasil dibangun."
echo "[XRAY-BUILDER] VLESS : $(sqlite3 "$DB" "SELECT COUNT(*) FROM users WHERE LOWER(protocol)='vless' AND LOWER(status)='active' AND (expiry_date IS NULL OR (length(expiry_date)=10 AND expiry_date >= date('now')) OR (length(expiry_date)>10 AND datetime(expiry_date) >= datetime('now')));")"
echo "[XRAY-BUILDER] VMess : $(sqlite3 "$DB" "SELECT COUNT(*) FROM users WHERE LOWER(protocol)='vmess' AND LOWER(status)='active' AND (expiry_date IS NULL OR (length(expiry_date)=10 AND expiry_date >= date('now')) OR (length(expiry_date)>10 AND datetime(expiry_date) >= datetime('now')));")"
echo "[XRAY-BUILDER] Trojan: $(sqlite3 "$DB" "SELECT COUNT(*) FROM users WHERE LOWER(protocol)='trojan' AND LOWER(status)='active' AND (expiry_date IS NULL OR (length(expiry_date)=10 AND expiry_date >= date('now')) OR (length(expiry_date)>10 AND datetime(expiry_date) >= datetime('now')));")"
echo "[XRAY-BUILDER] VMess gRPC existing client dipertahankan."
