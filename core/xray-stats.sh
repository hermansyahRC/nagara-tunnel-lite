#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/nagara-tunnel-lite"
DB="${APP_DIR}/users/users.db"
XRAY="/usr/local/bin/xray"
API_SERVER="127.0.0.1:10085"

die() {
    echo "[XRAY-STATS] ERROR: $*" >&2
    exit 1
}

require_tools() {
    [[ -x "$XRAY" ]] || die "Xray tidak ditemukan: $XRAY"
    command -v jq >/dev/null 2>&1 || die "jq tidak ditemukan"
}

human_bytes() {
    awk -v bytes="${1:-0}" '
    BEGIN {
        if (bytes < 1024)
            printf "%.0f B", bytes
        else if (bytes < 1024^2)
            printf "%.2f KB", bytes/1024
        else if (bytes < 1024^3)
            printf "%.2f MB", bytes/1024^2
        else if (bytes < 1024^4)
            printf "%.2f GB", bytes/1024^3
        else
            printf "%.2f TB", bytes/1024^4
    }'
}

api_stats() {
    "$XRAY" api statsquery \
        --server="$API_SERVER" \
        -pattern "user>>>nagara-" 2>/dev/null
}

traffic() {
    local data

    data="$(api_stats)" || die "Gagal membaca Xray Stats API."

    echo
    echo "=============================================================="
    echo "                    XRAY USER TRAFFIC"
    echo "=============================================================="
    printf "%-20s %-15s %-15s %-15s\n" \
        "USERNAME" "UPLOAD" "DOWNLOAD" "TOTAL"
    echo "--------------------------------------------------------------"

    if ! jq -e '.stat and (.stat | length > 0)' >/dev/null 2>&1 <<<"$data"; then
        echo "Belum ada data traffic."
        echo "=============================================================="
        echo
        return 0
    fi

    jq -r '
        .stat[]
        | select(.name | startswith("user>>>nagara-"))
        | [
            (.name | split(">>>")[1] | sub("^nagara-"; "")),
            (.name | split(">>>")[3]),
            (.value // 0)
          ]
        | @tsv
    ' <<<"$data" |
    awk -F'\t' '
    function human(bytes) {
        if (bytes < 1024)
            return sprintf("%.0f B", bytes)
        if (bytes < 1024^2)
            return sprintf("%.2f KB", bytes / 1024)
        if (bytes < 1024^3)
            return sprintf("%.2f MB", bytes / 1024^2)
        if (bytes < 1024^4)
            return sprintf("%.2f GB", bytes / 1024^3)
        return sprintf("%.2f TB", bytes / 1024^4)
    }

    {
        user = $1
        direction = $2
        value = $3 + 0

        users[user] = 1

        if (direction == "uplink")
            upload[user] += value
        else if (direction == "downlink")
            download[user] += value
    }

    END {
        for (user in users)
            print user

    }' |
    sort -u |
    while IFS= read -r user; do
        awk -F'\t' -v target="$user" '
        function human(bytes) {
            if (bytes < 1024)
                return sprintf("%.0f B", bytes)
            if (bytes < 1024^2)
                return sprintf("%.2f KB", bytes / 1024)
            if (bytes < 1024^3)
                return sprintf("%.2f MB", bytes / 1024^2)
            if (bytes < 1024^4)
                return sprintf("%.2f GB", bytes / 1024^3)
            return sprintf("%.2f TB", bytes / 1024^4)
        }

        {
            if ($1 == target) {
                if ($2 == "uplink")
                    up += $3
                else if ($2 == "downlink")
                    down += $3
            }
        }

        END {
            total = up + down

            printf "%-20s %-15s %-15s %-15s\n",
                target,
                human(up),
                human(down),
                human(total)
        }
        ' <<<"$(
            jq -r '
                .stat[]
                | select(.name | startswith("user>>>nagara-"))
                | [
                    (.name | split(">>>")[1] | sub("^nagara-"; "")),
                    (.name | split(">>>")[3]),
                    (.value // 0)
                  ]
                | @tsv
            ' <<<"$data"
        )"
    done

    echo "--------------------------------------------------------------"

    jq -r '
        .stat[]
        | select(.name | startswith("user>>>nagara-"))
        | [
            (.name | split(">>>")[3]),
            (.value // 0)
          ]
        | @tsv
    ' <<<"$data" |
    awk -F'\t' '
    {
        if ($1 == "uplink")
            total_up += $2
        else if ($1 == "downlink")
            total_down += $2
    }

    function human(bytes) {
        if (bytes < 1024)
            return sprintf("%.0f B", bytes)
        if (bytes < 1024^2)
            return sprintf("%.2f KB", bytes / 1024)
        if (bytes < 1024^3)
            return sprintf("%.2f MB", bytes / 1024^2)
        if (bytes < 1024^4)
            return sprintf("%.2f GB", bytes / 1024^3)
        return sprintf("%.2f TB", bytes / 1024^4)
    }

    END {
        total = total_up + total_down

        printf "%-20s %-15s %-15s %-15s\n",
            "TOTAL",
            human(total_up),
            human(total_down),
            human(total)
    }'

    echo "=============================================================="
    echo
}

online() {
    echo
    echo "=============================================================="
    echo "                    XRAY ONLINE USERS"
    echo "=============================================================="

    local result
    result="$("$XRAY" api statsgetallonlineusers \
        --server="$API_SERVER" 2>/dev/null || true)"

    if [[ -z "$result" || "$result" == "{}" ]]; then
        echo "Tidak ada user online yang terdeteksi."
        echo
        return 0
    fi

    echo "$result" | jq .
    echo
}

user_online() {
    local username="${1:-}"

    [[ -n "$username" ]] || die "Gunakan: $0 user <username>"

    local email="nagara-${username}"

    echo
    echo "=============================================================="
    echo "                  SESSION USER: ${username}"
    echo "=============================================================="

    "$XRAY" api statsonline \
        --server="$API_SERVER" \
        -email "$email" 2>&1 || true

    echo
}

user_ip() {
    local username="${1:-}"

    [[ -n "$username" ]] || die "Gunakan: $0 ip <username>"

    local email="nagara-${username}"

    echo
    echo "=============================================================="
    echo "                     IP USER: ${username}"
    echo "=============================================================="

    "$XRAY" api statsonlineiplist \
        --server="$API_SERVER" \
        -email "$email" 2>&1 || true

    echo
}

usage() {
    cat <<EOF

Nagara Tunnel Lite - Xray Statistics

Usage:
  $0 traffic
  $0 online
  $0 user <username>
  $0 ip <username>

Contoh:
  $0 traffic
  $0 online
  $0 user jhon
  $0 ip jhon

API:
  ${API_SERVER}

EOF
}

main() {
    require_tools

    case "${1:-}" in
        traffic)
            traffic
            ;;
        online)
            online
            ;;
        user)
            user_online "${2:-}"
            ;;
        ip)
            user_ip "${2:-}"
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
