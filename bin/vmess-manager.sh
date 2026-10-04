#!/usr/bin/env bash

APP_DIR="/opt/nagara-tunnel-lite"
DB="$APP_DIR/users/users.db"
XRAY_SYNC="$APP_DIR/core/xray-sync.sh"

if [[ -f "$APP_DIR/config/config.conf" ]]; then
    source "$APP_DIR/config/config.conf"
fi

if [[ -f "$APP_DIR/core/colors.sh" ]]; then
    source "$APP_DIR/core/colors.sh"
fi

if [[ -f "$APP_DIR/bin/telegram-notify.sh" ]]; then
    source "$APP_DIR/bin/telegram-notify.sh"
fi

pause_menu() {
    echo
    read -r -p "Press Enter to continue..." _
}

sync_xray() {
    echo
    echo "────────────────────────────────────────────────────────"
    echo "                    XRAY SYNC"
    echo "────────────────────────────────────────────────────────"
    echo
    echo "Menyinkronkan konfigurasi Xray..."
    echo

    if "$XRAY_SYNC"; then
        echo
        echo -e "${GREEN}✓ Config Xray berhasil diperbarui.${RESET}"
        echo -e "${GREEN}✓ Xray berhasil direstart.${RESET}"
        return 0
    else
        echo
        echo -e "${RED}✗ Sinkronisasi Xray gagal.${RESET}"
        echo -e "${YELLOW}Database sudah berubah, tetapi Xray belum menggunakan perubahan tersebut.${RESET}"
        return 1
    fi
}

header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${WHITE}                  VMESS MANAGER                       ${CYAN}║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
    echo
}

show_menu() {
    echo "┌────────────────────────────────────────────────────────┐"
    echo "│                                                        │"
    echo "│     1. ADD VMESS USER                                  │"
    echo "│     2. CREATE TRIAL                                    │"
    echo "│     3. DELETE VMESS USER                               │"
    echo "│     4. RENEW VMESS USER                                │"
    echo "│     5. LIST VMESS USERS                                │"
    echo "│     6. USER DETAIL                                     │"
    echo "│     7. DISABLE / ENABLE USER                           │"
    echo "│     8. CHANGE IP LIMIT                                 │"
    echo "│     9. GENERATE CONFIG                                 │"
    echo "│     0. BACK                                             │"
    echo "│                                                        │"
    echo "└────────────────────────────────────────────────────────┘"
    echo
    printf "  Select From Options [ 0 - 9 ] : "
}

get_user_list() {
    sqlite3 -separator '|' "$DB" "
        SELECT username, expiry_date, limit_ip, status
        FROM users
        WHERE LOWER(protocol)='vmess'
        ORDER BY id;
    "
}

select_user() {
    mapfile -t user_list < <(get_user_list)

    if [[ ${#user_list[@]} -eq 0 ]]; then
        echo
        echo -e "${YELLOW}Belum ada VMess user.${RESET}"
        return 1
    fi

    local i=1

    echo
    for row in "${user_list[@]}"; do
        IFS='|' read -r username expiry limit_ip status <<< "$row"

        printf "  %-3s %-22s Exp: %-10s Limit: %-3s Status: %s\n" \
            "$i." "$username" "$expiry" "$limit_ip" "$status"

        ((i++))
    done

    echo
    echo "  0. BACK"
    echo

    local max_choice=${#user_list[@]}

    read -r -p "Pilih User [ 0 - $max_choice ] : " user_choice

    if [[ "$user_choice" == "0" ]]; then
        return 2
    fi

    if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || \
       (( user_choice < 1 || user_choice > max_choice )); then
        echo
        echo -e "${RED}Pilihan user tidak valid.${RESET}"
        return 1
    fi

    SELECTED_USER="${user_list[$((user_choice-1))]}"
    return 0
}

show_success_header() {
    echo
    echo "════════════════════════════════════════════════════════"
    echo -e "${GREEN}              $1${RESET}"
    echo "════════════════════════════════════════════════════════"
}

show_failed_header() {
    echo
    echo "════════════════════════════════════════════════════════"
    echo -e "${RED}              $1${RESET}"
    echo "════════════════════════════════════════════════════════"
}


create_trial() {
    header
    echo "CREATE VMESS TRIAL"
    echo "────────────────────────────────────────────────────────"
    echo
    echo "Duration : 3 jam"
    echo "Limit IP : 1"
    echo

    local suffix username uuid expiry

    suffix="$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
    username="trial-vmess-${suffix}"
    uuid="$(cat /proc/sys/kernel/random/uuid)"
    expiry="$(date -d "+30 minutes" "+%Y-%m-%d %H:%M:%S")"

    echo "Username : $username"
    echo "UUID     : $uuid"
    echo "Expiry   : $expiry"
    echo "Limit IP : 1"
    echo

    if ! sqlite3 "$DB" "
        INSERT INTO users
        (username, protocol, uuid, limit_ip, expiry_date, status)
        VALUES
        ('$username', 'vmess', '$uuid', 1, '$expiry', 'active');
    "; then
        show_failed_header "TRIAL GAGAL DIBUAT"
        echo
        echo "Gagal menyimpan trial ke database."
        pause_menu
        return
    fi

    echo "Trial tersimpan. Menyinkronkan Xray..."
    echo

    if sync_xray; then
        show_success_header "VMESS TRIAL BERHASIL DIBUAT"
        echo
        echo "Username    : $username"
        echo "UUID        : $uuid"
        echo "Expired     : $expiry"
        echo "Limit IP    : 1"
        echo "Status      : active"
        echo
        echo -e "${GREEN}✓ Trial aktif di Xray.${RESET}"
        show_vmess_links "$username" "$uuid"
    else
        echo
        echo "Sinkronisasi gagal."
        echo "Menghapus kembali trial dari database..."

        sqlite3 "$DB" "
            DELETE FROM users
            WHERE username='$username'
              AND protocol='vmess';
        "

        show_failed_header "VMESS TRIAL DIBATALKAN"
        echo
        echo "Trial tidak dibiarkan tersimpan karena Xray gagal sync."
    fi

    pause_menu
}


show_vmess_links() {
    local username="$1"
    local uuid="$2"
    local domain="$DOMAIN"
    local link_json
    local vmess_ws_tls
    local vmess_ws_80
    local vmess_grpc_tls

    echo
    echo "════════════════════════════════════════════════════════"
    echo "                 VMESS IMPORT CONFIG"
    echo "════════════════════════════════════════════════════════"
    echo
    echo "Username : $username"
    echo

    # VMess WS TLS 443
    link_json="$(python3 - "$username" "$uuid" "$domain" <<'PYJSON'
import json
import sys
import base64

username, uuid, domain = sys.argv[1:4]

cfg = {
    "v": "2",
    "ps": f"{username} - WS TLS 443",
    "add": domain,
    "port": "443",
    "id": uuid,
    "aid": "0",
    "scy": "auto",
    "net": "ws",
    "type": "none",
    "host": domain,
    "path": "/vmess-ws",
    "tls": "tls",
    "sni": domain,
    "alpn": ""
}

raw = json.dumps(cfg, separators=(",", ":"))
print(base64.b64encode(raw.encode()).decode())
PYJSON
)"

    vmess_ws_tls="vmess://${link_json}"

    echo "VMess WS TLS 443"
    echo "$vmess_ws_tls"
    echo
    echo "────────────────────────────────────────────────────────"

    # VMess WS 80
    link_json="$(python3 - "$username" "$uuid" "$domain" <<'PYJSON'
import json
import sys
import base64

username, uuid, domain = sys.argv[1:4]

cfg = {
    "v": "2",
    "ps": f"{username} - WS 80",
    "add": domain,
    "port": "80",
    "id": uuid,
    "aid": "0",
    "scy": "auto",
    "net": "ws",
    "type": "none",
    "host": domain,
    "path": "/vmess-ws",
    "tls": "",
    "sni": ""
}

raw = json.dumps(cfg, separators=(",", ":"))
print(base64.b64encode(raw.encode()).decode())
PYJSON
)"

    vmess_ws_80="vmess://${link_json}"

    echo "VMess WS 80"
    echo "$vmess_ws_80"
    echo
    echo "────────────────────────────────────────────────────────"

    # VMess gRPC TLS 443
    link_json="$(python3 - "$username" "$uuid" "$domain" <<'PYJSON'
import json
import sys
import base64

username, uuid, domain = sys.argv[1:4]

cfg = {
    "v": "2",
    "ps": f"{username} - gRPC TLS 443",
    "add": domain,
    "port": "443",
    "id": uuid,
    "aid": "0",
    "scy": "auto",
    "net": "grpc",
    "type": "none",
    "host": "",
    "path": "vmess-grpc",
    "tls": "tls",
    "sni": domain,
    "alpn": ""
}

raw = json.dumps(cfg, separators=(",", ":"))
print(base64.b64encode(raw.encode()).decode())
PYJSON
)"

    vmess_grpc_tls="vmess://${link_json}"

    echo "VMess gRPC TLS 443"
    echo "$vmess_grpc_tls"
    echo
    echo "────────────────────────────────────────────────────────"
    echo "Copy salah satu link di atas → Import from clipboard"
    echo "di V2RayNG."
    echo

    # Telegram notification
    telegram_message="NAGARA TUNNEL LITE

VMESS ACCOUNT

Username : $username
Server   : $domain

VMess WS TLS 443
$vmess_ws_tls

VMess WS 80
$vmess_ws_80

VMess gRPC TLS 443
$vmess_grpc_tls"

    if telegram_send "$telegram_message"; then
        if [[ "${TELEGRAM_ENABLED:-false}" == "true" ]]; then
            echo -e "${GREEN}✓ Link VMess dikirim ke Telegram.${RESET}"
        fi
    else
        if [[ "${TELEGRAM_ENABLED:-false}" == "true" ]]; then
            echo -e "${YELLOW}⚠ Gagal mengirim link ke Telegram.${RESET}"
        fi
    fi

    echo
}

main() {
    while true; do
        header
        show_menu
        read -r choice

        case "$choice" in

        1)
            header
            echo "ADD VMESS USER"
            echo "────────────────────────────────────────────────────────"
            echo

            read -r -p "Username       : " username
            read -r -p "Active Days    : " active_days
            read -r -p "Limit IP       : " limit_ip

            if [[ -z "$username" || -z "$active_days" || -z "$limit_ip" ]]; then
                echo
                echo -e "${RED}✗ Semua field wajib diisi.${RESET}"
                pause_menu
                continue
            fi

            if ! [[ "$limit_ip" =~ ^[0-9]+$ ]] || (( limit_ip < 1 )); then
                echo
                echo -e "${RED}✗ Limit IP harus berupa angka minimal 1.${RESET}"
                pause_menu
                continue
            fi

            if ! [[ "$active_days" =~ ^[0-9]+$ ]] || (( active_days < 1 )); then
                echo
                echo -e "${RED}✗ Active Days harus berupa angka minimal 1.${RESET}"
                pause_menu
                continue
            fi

            expiry="$(date -d "+${active_days} days" +%Y-%m-%d)"

            if sqlite3 "$DB" \
                "SELECT 1 FROM users WHERE username='$username' LIMIT 1;" |
                grep -q 1; then

                echo
                echo -e "${RED}✗ Username sudah digunakan.${RESET}"
                pause_menu
                continue
            fi

            uuid="$(cat /proc/sys/kernel/random/uuid)"

            echo
            echo "Menyimpan user ke database..."

            if ! sqlite3 "$DB" "
                INSERT INTO users
                (username, protocol, uuid, limit_ip, expiry_date, status)
                VALUES
                ('$username', 'vmess', '$uuid', '$limit_ip', '$expiry', 'active');
            "; then

                show_failed_header "VMESS USER GAGAL DIBUAT"
                echo
                echo "Gagal menyimpan user ke database."
                pause_menu
                continue
            fi

            echo -e "${GREEN}✓ User berhasil disimpan ke database.${RESET}"

            if sync_xray; then
                show_success_header "VMESS USER BERHASIL DIBUAT"
                echo
                echo "Username    : $username"
                echo "UUID        : $uuid"
                echo "Expired     : $expiry"
                echo "Limit IP    : $limit_ip"
                echo "Status      : active"
                echo
                echo -e "${GREEN}✓ User aktif di Xray.${RESET}"
                show_vmess_links "$username" "$uuid"
            else
                show_failed_header "VMESS USER BERHASIL DISIMPAN"
                echo
                echo "Username    : $username"
                echo "UUID        : $uuid"
                echo "Expired     : $expiry"
                echo "Limit IP    : $limit_ip"
                echo "Status      : active"
                echo
                echo -e "${RED}✗ Xray belum menggunakan perubahan.${RESET}"
            fi

            pause_menu
            ;;

        2)
            create_trial
            ;;

        3)
            header
            echo "DELETE VMESS USER"
            echo "────────────────────────────────────────────────────────"

            if ! select_user; then
                [[ $? -eq 2 ]] && continue
                pause_menu
                continue
            fi

            IFS='|' read -r username expiry limit_ip status <<< "$SELECTED_USER"

            echo
            echo "User yang akan dihapus:"
            echo
            echo "Username : $username"
            echo "Expiry   : $expiry"
            echo "Limit IP : $limit_ip"
            echo "Status   : $status"
            echo

            read -r -p "Hapus user $username? [y/N] : " confirm

            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo
                echo "Penghapusan dibatalkan."
                pause_menu
                continue
            fi

            echo
            echo "Menghapus user dari database..."

            if ! sqlite3 "$DB" "
                DELETE FROM users
                WHERE username='$username'
                  AND LOWER(protocol)='vmess';
            "; then

                show_failed_header "VMESS USER GAGAL DIHAPUS"
                pause_menu
                continue
            fi

            echo -e "${GREEN}✓ User berhasil dihapus dari database.${RESET}"

            if sync_xray; then
                show_success_header "VMESS USER BERHASIL DIHAPUS"
                echo
                echo "Username : $username"
                echo "Status   : deleted"
            else
                show_failed_header "USER DIHAPUS, XRAY GAGAL SYNC"
                echo
                echo "Username : $username"
                echo
                echo -e "${RED}✗ Config Xray belum diperbarui.${RESET}"
            fi

            pause_menu
            ;;

        4)
            header
            echo "RENEW VMESS USER"
            echo "────────────────────────────────────────────────────────"

            if ! select_user; then
                [[ $? -eq 2 ]] && continue
                pause_menu
                continue
            fi

            IFS='|' read -r username current_expiry limit_ip status <<< "$SELECTED_USER"

            echo
            echo "Username          : $username"
            echo "Expired Sekarang  : $current_expiry"
            echo "Status Sekarang   : $status"
            echo

            read -r -p "Tambah Hari       : " add_days

            if ! [[ "$add_days" =~ ^[0-9]+$ ]] || (( add_days < 1 )); then
                echo
                echo -e "${RED}✗ Tambah Hari harus berupa angka minimal 1.${RESET}"
                pause_menu
                continue
            fi

            today="$(date +%Y-%m-%d)"

            if [[ "$current_expiry" < "$today" ]]; then
                new_expiry="$(date -d "+${add_days} days" +%Y-%m-%d)"
            else
                new_expiry="$(date -d "$current_expiry + ${add_days} days" +%Y-%m-%d)"
            fi

            echo
            echo "Memperbarui masa aktif..."

            if ! sqlite3 "$DB" "
                UPDATE users
                SET expiry_date='$new_expiry',
                    status='active',
                    updated_at=CURRENT_TIMESTAMP
                WHERE username='$username'
                  AND LOWER(protocol)='vmess';
            "; then

                show_failed_header "RENEW VMESS GAGAL"
                pause_menu
                continue
            fi

            echo -e "${GREEN}✓ Masa aktif berhasil diperbarui.${RESET}"

            if sync_xray; then
                show_success_header "VMESS USER BERHASIL DIRENEW"
                echo
                echo "Username     : $username"
                echo "Expired Lama : $current_expiry"
                echo "Tambah Hari  : $add_days"
                echo "Expired Baru : $new_expiry"
                echo "Status       : active"
            else
                show_failed_header "RENEW BERHASIL, XRAY GAGAL SYNC"
                echo
                echo "Username     : $username"
                echo "Expired Baru : $new_expiry"
                echo "Status       : active"
                echo
                echo -e "${RED}✗ Xray belum menggunakan perubahan expiry.${RESET}"
            fi

            pause_menu
            ;;

        5)
            header
            echo "VMESS USERS"
            echo "────────────────────────────────────────────────────────"
            echo

            if [[ ! -f "$DB" ]]; then
                echo -e "${RED}Database belum tersedia.${RESET}"
                pause_menu
                continue
            fi

            sqlite3 -header -column "$DB" "
                SELECT
                    username AS USERNAME,
                    expiry_date AS EXPIRED,
                    limit_ip AS LIMIT_IP,
                    status AS STATUS
                FROM users
                WHERE LOWER(protocol)='vmess'
                ORDER BY id;
            "

            pause_menu
            ;;

        6)
            header
            echo "VMESS USER DETAIL"
            echo "────────────────────────────────────────────────────────"

            if ! select_user; then
                [[ $? -eq 2 ]] && continue
                pause_menu
                continue
            fi

            IFS='|' read -r username expiry limit_ip status <<< "$SELECTED_USER"

            echo

            sqlite3 -separator '|' "$DB" "
                SELECT username,
                       protocol,
                       uuid,
                       password,
                       limit_ip,
                       expiry_date,
                       status,
                       created_at,
                       updated_at
                FROM users
                WHERE username='$username'
                  AND LOWER(protocol)='vmess'
                LIMIT 1;
            " | while IFS='|' read -r \
                username protocol uuid password limit_ip expiry status created updated
            do
                echo "Username     : $username"
                echo "Protocol     : VMess"
                echo "UUID         : $uuid"
                echo "Limit IP     : $limit_ip"
                echo "Expiry Date  : $expiry"
                echo "Status       : $status"
                echo "Created      : $created"
                echo "Updated      : $updated"
            done

            echo
            pause_menu
            ;;

        7)
            header
            echo "DISABLE / ENABLE VMESS USER"
            echo "────────────────────────────────────────────────────────"

            if ! select_user; then
                [[ $? -eq 2 ]] && continue
                pause_menu
                continue
            fi

            IFS='|' read -r username expiry limit_ip current_status <<< "$SELECTED_USER"

            echo
            echo "Username        : $username"
            echo "Status Sekarang : $current_status"
            echo

            if [[ "$current_status" == "active" ]]; then
                new_status="disabled"
                action="DISABLED"
            else
                new_status="active"
                action="ENABLED"
            fi

            read -r -p "Ubah status menjadi $new_status? [y/N] : " confirm

            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo
                echo "Perubahan dibatalkan."
                pause_menu
                continue
            fi

            echo
            echo "Mengubah status user..."

            if ! sqlite3 "$DB" "
                UPDATE users
                SET status='$new_status',
                    updated_at=CURRENT_TIMESTAMP
                WHERE username='$username'
                  AND LOWER(protocol)='vmess';
            "; then

                show_failed_header "PERUBAHAN STATUS GAGAL"
                pause_menu
                continue
            fi

            echo -e "${GREEN}✓ Status database berhasil diubah.${RESET}"

            if sync_xray; then
                show_success_header "VMESS USER BERHASIL DI-$action"
                echo
                echo "Username : $username"
                echo "Status   : $current_status -> $new_status"

                if [[ "$new_status" == "active" ]]; then
                    echo
                    echo -e "${GREEN}✓ User kembali aktif di Xray.${RESET}"
                else
                    echo
                    echo -e "${GREEN}✓ User dikeluarkan dari Xray.${RESET}"
                fi
            else
                show_failed_header "STATUS BERUBAH, XRAY GAGAL SYNC"
                echo
                echo "Username : $username"
                echo "Status   : $current_status -> $new_status"
            fi

            pause_menu
            ;;

        8)
            header
            echo "CHANGE VMESS IP LIMIT"
            echo "────────────────────────────────────────────────────────"

            if ! select_user; then
                [[ $? -eq 2 ]] && continue
                pause_menu
                continue
            fi

            IFS='|' read -r username expiry current_limit status <<< "$SELECTED_USER"

            echo
            echo "Username         : $username"
            echo "Limit IP Sekarang : $current_limit"
            echo

            read -r -p "Limit IP Baru     : " new_limit

            if ! [[ "$new_limit" =~ ^[0-9]+$ ]] || (( new_limit < 1 )); then
                echo
                echo -e "${RED}✗ Limit IP harus berupa angka minimal 1.${RESET}"
                pause_menu
                continue
            fi

            echo
            read -r -p "Ubah Limit IP menjadi $new_limit? [y/N] : " confirm

            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo
                echo "Perubahan dibatalkan."
                pause_menu
                continue
            fi

            echo
            echo "Mengubah IP Limit..."

            if ! sqlite3 "$DB" "
                UPDATE users
                SET limit_ip=$new_limit,
                    updated_at=CURRENT_TIMESTAMP
                WHERE username='$username'
                  AND LOWER(protocol)='vmess';
            "; then

                show_failed_header "IP LIMIT GAGAL DIUBAH"
                pause_menu
                continue
            fi

            show_success_header "VMESS IP LIMIT BERHASIL DIUBAH"
            echo
            echo "Username : $username"
            echo "Limit    : $current_limit -> $new_limit"
            echo "Status   : $status"
            echo
            echo "Catatan: IP Limit tersimpan di database."
            echo "Enforcement akan digunakan oleh Online Monitor."

            pause_menu
            ;;

        9)
            header
            echo "GENERATE VMESS CONFIG"
            echo "────────────────────────────────────────────────────────"

            if ! select_user; then
                [[ $? -eq 2 ]] && continue
                pause_menu
                continue
            fi

            IFS='|' read -r username expiry limit_ip status <<< "$SELECTED_USER"

            user_data="$(
                sqlite3 -separator '|' "$DB" "
                    SELECT uuid
                    FROM users
                    WHERE username='$username'
                      AND LOWER(protocol)='vmess'
                    LIMIT 1;
                "
            )"

            uuid="$user_data"

            if [[ -z "$uuid" ]]; then
                echo
                echo -e "${RED}✗ UUID user tidak ditemukan.${RESET}"
                pause_menu
                continue
            fi

            echo
            echo "Username    : $username"
            echo "Expiry      : $expiry"
            echo "Limit IP    : $limit_ip"
            echo "Status      : $status"

            show_vmess_links "$username" "$uuid"

            pause_menu
            ;;

        0)
            return
            ;;

        *)
            echo
            echo -e "${RED}Pilihan tidak valid.${RESET}"
            sleep 1
            ;;

        esac
    done
}

main
