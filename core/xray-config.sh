#!/usr/bin/env bash

set -Eeuo pipefail

DB="/opt/nagara-tunnel-lite/users/users.db"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"

TMP_CONFIG="/tmp/nagara-xray-config.json"

log() {
    echo "[XRAY-CONFIG] $*"
}

die() {
    echo "[XRAY-CONFIG] ERROR: $*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || die "File tidak ditemukan: $1"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Command tidak ditemukan: $1"
}

require_file "$DB"
require_file "$XRAY_BIN"
require_command sqlite3
require_command jq

TODAY="$(date +%Y-%m-%d)"

VMESS_USERS='[]'
VLESS_USERS='[]'
TROJAN_USERS='[]'

while IFS='|' read -r username uuid limit expiry; do
    [[ -n "$username" ]] || continue

    VMESS_USERS="$(
        jq \
            --arg id "$uuid" \
            --arg email "nagara-$username" \
            --argjson level 0 \
            '. + [{
                "id": $id,
                "alterId": 0,
                "email": $email,
                "security": "auto",
                "level": $level
            }]' <<< "$VMESS_USERS"
    )"
done < <(
    sqlite3 -separator '|' "$DB" "
        SELECT username, uuid, limit_ip, expiry_date
        FROM users
        WHERE protocol='vmess'
          AND status='active'
          AND uuid IS NOT NULL
          AND uuid != ''
          AND (
              expiry_date IS NULL
              OR expiry_date = ''
              OR expiry_date >= '$TODAY'
          )
        ORDER BY id;
    "
)

while IFS='|' read -r username uuid limit expiry; do
    [[ -n "$username" ]] || continue

    VLESS_USERS="$(
        jq \
            --arg id "$uuid" \
            --arg email "nagara-$username" \
            '. + [{
                "id": $id,
                "email": $email,
                "level": 0
            }]' <<< "$VLESS_USERS"
    )"
done < <(
    sqlite3 -separator '|' "$DB" "
        SELECT username, uuid, limit_ip, expiry_date
        FROM users
        WHERE protocol='vless'
          AND status='active'
          AND uuid IS NOT NULL
          AND uuid != ''
          AND (
              expiry_date IS NULL
              OR expiry_date = ''
              OR expiry_date >= '$TODAY'
          )
        ORDER BY id;
    "
)

while IFS='|' read -r username password limit expiry; do
    [[ -n "$username" ]] || continue

    TROJAN_USERS="$(
        jq \
            --arg password "$password" \
            --arg email "nagara-$username" \
            '. + [{
                "password": $password,
                "email": $email,
                "level": 0
            }]' <<< "$TROJAN_USERS"
    )"
done < <(
    sqlite3 -separator '|' "$DB" "
        SELECT username, password, limit_ip, expiry_date
        FROM users
        WHERE protocol='trojan'
          AND status='active'
          AND password IS NOT NULL
          AND password != ''
          AND (
              expiry_date IS NULL
              OR expiry_date = ''
              OR expiry_date >= '$TODAY'
          )
        ORDER BY id;
    "
)

jq -n \
    --argjson vmess "$VMESS_USERS" \
    --argjson vless "$VLESS_USERS" \
    --argjson trojan "$TROJAN_USERS" '
{
  "log": {
    "loglevel": "warning"
  },

  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    },

    {
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vless",
      "settings": {
        "clients": $vless,
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/nagara-ws"
        }
      },
      "tag": "vless-in"
    },

    {
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "vmess",
      "settings": {
        "clients": $vmess
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess-ws"
        }
      },
      "tag": "vmess-in"
    },

    {
      "listen": "127.0.0.1",
      "port": 10003,
      "protocol": "trojan",
      "settings": {
        "clients": $trojan
      },
      "tag": "trojan-in"
    }
  ],

  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
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
        "inboundTag": ["api"],
        "outboundTag": "direct"
      }
    ]
  }
}
' > "$TMP_CONFIG"

"$XRAY_BIN" run -test -config "$TMP_CONFIG" >/dev/null 2>&1 \
    || die "Generated Xray configuration tidak valid."

install -o root -g root -m 0644 "$TMP_CONFIG" "$XRAY_CONFIG"

rm -f "$TMP_CONFIG"

log "Configuration berhasil dibuat."
log "VMess  : $(jq 'length' <<< "$VMESS_USERS") user"
log "VLESS  : $(jq 'length' <<< "$VLESS_USERS") user"
log "Trojan : $(jq 'length' <<< "$TROJAN_USERS") user"
log "Config : $XRAY_CONFIG"
