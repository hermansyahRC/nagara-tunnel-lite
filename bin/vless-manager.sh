#!/bin/bash

# ============================================================
# Nagara Tunnel Lite
# VLESS Manager
# ============================================================

set -u

APP_DIR="/opt/nagara-tunnel-lite"
DB="$APP_DIR/users/users.db"

if [[ -f "$APP_DIR/config/config.conf" ]]; then
    source "$APP_DIR/config/config.conf"
fi

# ============================================================
# COLORS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# ============================================================
# BASIC FUNCTIONS
# ============================================================

header() {
    clear

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${WHITE}                  VLESS MANAGER                        ${CYAN}║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
    echo
}

pause_menu() {
    echo
    read -r -p "Tekan Enter untuk kembali..."
}

check_db() {
    if [[ ! -f "$DB" ]]; then
        echo -e "${RED}Database tidak ditemukan:${RESET}"
        echo "$DB"
        pause_menu
        return 1
    fi

    return 0
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# ============================================================
# XRAY SYNC
# ============================================================

sync_xray() {
    echo
    echo "────────────────────────────────────────────────────────"
    echo "                    XRAY SYNC"
    echo "────────────────────────────────────────────────────────"
    echo
    echo "Menyinkronkan konfigurasi Xray..."
    echo

    if "$APP_DIR/core/xray-sync.sh"; then
        echo
        echo -e "${GREEN}✓ Config Xray berhasil diperbarui.${RESET}"
        echo -e "${GREEN}✓ Xray berhasil direstart.${RESET}"
        return 0
    else
        echo
        echo -e "${RED}✗ Sinkronisasi Xray gagal.${RESET}"
        return 1
    fi
}

# ============================================================
# VLESS DIRECT IMPORT LINK
# ============================================================

show_vless_links() {
    local username="$1"
    local uuid="$2"

    local domain="$DOMAIN"
    local encoded_path="%2Fnagara-ws"
    local encoded_name

    encoded_name="$(printf '%s' "$username" | sed 's/ /%20/g')"

    local vless_ws_tls
    local vless_ws_80
    local vless_grpc_tls

    vless_ws_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=${encoded_path}&sni=${domain}#${encoded_name}%20-%20WS%20TLS%20443"

    vless_ws_80="vless://${uuid}@${domain}:80?encryption=none&security=none&type=ws&host=${domain}&path=${encoded_path}#${encoded_name}%20-%20WS%2080"

    vless_grpc_tls="vless://${uuid}@${domain}:443?encryption=none&security=tls&type=grpc&serviceName=vless-grpc&sni=${domain}#${encoded_name}%20-%20gRPC%20TLS%20443"

    echo
    echo "════════════════════════════════════════════════════════"
    echo "                 VLESS CONFIG"
    echo "════════════════════════════════════════════════════════"
    echo
    echo "Username : $username"
    echo "UUID     : $uuid"
    echo
    echo "VLESS WS TLS 443:"
    echo
    echo "$vless_ws_tls"
    echo
    echo "VLESS WS 80:"
    echo
    echo "$vless_ws_80"
    echo

    echo "VLESS gRPC TLS 443:"
    echo
    echo "$vless_grpc_tls"
    echo
    echo "Service Name : vless-grpc"
    echo
    echo "Copy salah satu link → Import from clipboard di V2RayNG."
    echo

    echo "$vless_ws_tls" | xclip -selection clipboard 2>/dev/null || true
}

# ============================================================
# 1. ADD VLESS USER
# ============================================================

add_user() {
    header

    echo "ADD VLESS USER"
    echo "────────────────────────────────────────────────────────"
    echo

    read -r -p "Username       : " username
    read -r -p "Active Days    : " active_days
    read -r -p "Limit IP       : " limit_ip

    if [[ -z "$username" ]]; then
        echo
        echo -e "${RED}Username tidak boleh kosong.${RESET}"
        pause_menu
        return
    fi

    if ! [[ "$username" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo
        echo -e "${RED}Username hanya boleh berisi huruf, angka, titik, dash, dan underscore.${RESET}"
        pause_menu
        return
    fi

    if ! [[ "$active_days" =~ ^[0-9]+$ ]] || (( active_days < 1 )); then
        echo
        echo -e "${RED}Active Days harus berupa angka minimal 1.${RESET}"
        pause_menu
        return
    fi

    if ! [[ "$limit_ip" =~ ^[0-9]+$ ]] || (( limit_ip < 1 )); then
        echo
        echo -e "${RED}Limit IP harus berupa angka minimal 1.${RESET}"
        pause_menu
        return
    fi

    local exists

    exists="$(
        sqlite3 "$DB" "
            SELECT COUNT(*)
            FROM users
            WHERE LOWER(username)=LOWER('$username');
        "
    )"

    if [[ "$exists" != "0" ]]; then
        echo
        echo -e "${RED}Username sudah digunakan.${RESET}"
        pause_menu
        return
    fi

    local uuid
    local expiry

    uuid="$(generate_uuid)"
    expiry="$(date -d "+${active_days} days" +%Y-%m-%d)"

    sqlite3 "$DB" "
        INSERT INTO users (
            username,
            protocol,
            uuid,
            password,
            limit_ip,
            expiry_date,
            status,
            created_at,
            updated_at
        )
        VALUES (
            '$username',
            'vless',
            '$uuid',
            NULL,
            $limit_ip,
            '$expiry',
            'active',
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
        );
    "

    echo
    echo "User tersimpan. Menyinkronkan Xray..."
    echo

    if sync_xray; then
        echo
        echo -e "${GREEN}VLESS user berhasil dibuat.${RESET}"
        echo
        echo "Username : $username"
        echo "Duration : $active_days days"
        echo "UUID     : $uuid"
        echo "Expiry   : $expiry"
        echo "Limit IP : $limit_ip"
        echo "Status   : active"

        show_vless_links "$username" "$uuid"
    else
        echo
        echo -e "${RED}Sinkronisasi Xray gagal.${RESET}"
        echo "Menghapus kembali user dari database..."

        sqlite3 "$DB" "
            DELETE FROM users
            WHERE username='$username'
              AND protocol='vless';
        "

        echo
        echo "VLESS user dibatalkan."
    fi

    pause_menu
}

# ============================================================
# 2. CREATE VLESS TRIAL
# ============================================================

create_trial() {
    header

    echo "CREATE VLESS TRIAL"
    echo "────────────────────────────────────────────────────────"
    echo
    echo "Duration : 3 jam"
    echo "Limit IP : 1"
    echo

    local suffix username uuid expiry

    suffix="$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
    username="trial-vless-${suffix}"
    uuid="$(generate_uuid)"
    expiry="$(date -d "+3 hours" "+%Y-%m-%d %H:%M:%S")"

    echo "Username : $username"
    echo "UUID     : $uuid"
    echo "Expiry   : $expiry"
    echo "Limit IP : 1"
    echo

    if ! sqlite3 "$DB" "
        INSERT INTO users
        (
            username,
            protocol,
            uuid,
            password,
            limit_ip,
            expiry_date,
            status,
            created_at,
            updated_at
        )
        VALUES
        (
            '$username',
            'vless',
            '$uuid',
            NULL,
            1,
            '$expiry',
            'active',
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
        );
    "; then
        echo
        echo -e "${RED}✗ Gagal menyimpan trial ke database.${RESET}"
        pause_menu
        return
    fi

    echo "Trial tersimpan. Menyinkronkan Xray..."
    echo

    if sync_xray; then
        echo
        echo "════════════════════════════════════════════════════════"
        echo "              VLESS TRIAL BERHASIL DIBUAT"
        echo "════════════════════════════════════════════════════════"
        echo
        echo "Username    : $username"
        echo "UUID        : $uuid"
        echo "Expired     : $expiry"
        echo "Limit IP    : 1"
        echo "Status      : active"
        echo
        echo -e "${GREEN}✓ Trial aktif di Xray.${RESET}"

        show_vless_links "$username" "$uuid"
    else
        echo
        echo "Sinkronisasi gagal."
        echo "Menghapus kembali trial dari database..."

        sqlite3 "$DB" "
            DELETE FROM users
            WHERE username='$username'
              AND protocol='vless';
        "

        echo
        echo "════════════════════════════════════════════════════════"
        echo "              VLESS TRIAL DIBATALKAN"
        echo "════════════════════════════════════════════════════════"
        echo
        echo "Trial tidak dibiarkan tersimpan karena Xray gagal sync."
    fi

    pause_menu
}

# ============================================================
# 3. DELETE VLESS USER
# ============================================================

delete_user() {
    header

    echo "DELETE VLESS USER"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t user_list < <(
        sqlite3 -separator '|' "$DB" "
            SELECT username, expiry_date, limit_ip
            FROM users
            WHERE LOWER(protocol)='vless'
            ORDER BY id;
        "
    )

    if [[ ${#user_list[@]} -eq 0 ]]; then
        echo "Belum ada VLESS user."
        pause_menu
        return
    fi

    local i=1

    for row in "${user_list[@]}"; do
        IFS='|' read -r username expiry limit_ip <<< "$row"

        printf "  %-3s %-22s Exp: %-10s Limit: %s\n" \
            "$i." "$username" "$expiry" "$limit_ip"

        ((i++))
    done

    echo
    echo "  0. BACK"
    echo

    local max_choice=${#user_list[@]}

    read -r -p "Pilih User [ 0 - $max_choice ] : " user_choice

    if [[ "$user_choice" == "0" ]]; then
        return
    fi

    if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || \
       (( user_choice < 1 || user_choice > max_choice )); then

        echo
        echo -e "${RED}Pilihan user tidak valid.${RESET}"
        pause_menu
        return
    fi

    local selected
    selected="${user_list[$((user_choice-1))]}"

    IFS='|' read -r username expiry limit_ip <<< "$selected"

    echo
    echo "User yang akan dihapus:"
    echo
    echo "Username : $username"
    echo "Expiry   : $expiry"
    echo "Limit IP : $limit_ip"
    echo

    read -r -p "Hapus user $username? [y/N] : " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo
        echo "Penghapusan dibatalkan."
        pause_menu
        return
    fi

    sqlite3 "$DB" "
        DELETE FROM users
        WHERE username='$username'
          AND LOWER(protocol)='vless';
    "

    echo
    echo -e "${GREEN}VLESS user berhasil dihapus.${RESET}"
    echo
    echo "Username : $username"

    pause_menu
}

# ============================================================
# 3. RENEW VLESS USER
# ============================================================

renew_user() {
    header

    echo "RENEW VLESS USER"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t user_list < <(
        sqlite3 -separator '|' "$DB" "
            SELECT username, expiry_date, limit_ip
            FROM users
            WHERE LOWER(protocol)='vless'
            ORDER BY id;
        "
    )

    if [[ ${#user_list[@]} -eq 0 ]]; then
        echo "Belum ada VLESS user."
        pause_menu
        return
    fi

    local i=1

    for row in "${user_list[@]}"; do
        IFS='|' read -r username expiry limit_ip <<< "$row"

        printf "  %-3s %-22s Exp: %-10s Limit: %s\n" \
            "$i." "$username" "$expiry" "$limit_ip"

        ((i++))
    done

    echo
    echo "  0. BACK"
    echo

    local max_choice=${#user_list[@]}

    read -r -p "Pilih User [ 0 - $max_choice ] : " user_choice

    if [[ "$user_choice" == "0" ]]; then
        return
    fi

    if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || \
       (( user_choice < 1 || user_choice > max_choice )); then

        echo
        echo -e "${RED}Pilihan user tidak valid.${RESET}"
        pause_menu
        return
    fi

    local selected
    selected="${user_list[$((user_choice-1))]}"

    IFS='|' read -r username current_expiry limit_ip <<< "$selected"

    echo
    read -r -p "Tambah Hari : " add_days

    if ! [[ "$add_days" =~ ^[0-9]+$ ]] || (( add_days < 1 )); then
        echo
        echo -e "${RED}Tambah Hari harus berupa angka minimal 1.${RESET}"
        pause_menu
        return
    fi

    local today
    local new_expiry

    today="$(date +%Y-%m-%d)"

    if [[ "$current_expiry" < "$today" ]]; then
        new_expiry="$(date -d "+${add_days} days" +%Y-%m-%d)"
    else
        new_expiry="$(date -d "$current_expiry + ${add_days} days" +%Y-%m-%d)"
    fi

    sqlite3 "$DB" "
        UPDATE users
        SET expiry_date='$new_expiry',
            status='active',
            updated_at=CURRENT_TIMESTAMP
        WHERE username='$username'
          AND LOWER(protocol)='vless';
    "

    echo
    echo -e "${GREEN}VLESS user berhasil diperpanjang.${RESET}"
    echo
    echo "Username     : $username"
    echo "Expired Lama : $current_expiry"
    echo "Tambah Hari  : $add_days"
    echo "Expired Baru : $new_expiry"
    echo "Status       : active"

    pause_menu
}

# ============================================================
# 4. LIST VLESS USERS
# ============================================================

list_users() {
    header

    echo "VLESS USERS"
    echo "────────────────────────────────────────────────────────"
    echo
    echo "USERNAME    EXPIRED     LIMIT_IP  STATUS"
    echo "----------  ----------  --------  --------"

    local count

    count="$(
        sqlite3 "$DB" "
            SELECT COUNT(*)
            FROM users
            WHERE LOWER(protocol)='vless';
        "
    )"

    if [[ "$count" == "0" ]]; then
        echo
        echo "Belum ada VLESS user."
        pause_menu
        return
    fi

    sqlite3 -separator '|' "$DB" "
        SELECT username, expiry_date, limit_ip, status
        FROM users
        WHERE LOWER(protocol)='vless'
        ORDER BY id;
    " | while IFS='|' read -r username expiry limit_ip status; do

        printf "%-11s %-11s %-9s %s\n" \
            "$username" "$expiry" "$limit_ip" "$status"

    done

    echo
    echo "Total VLESS User : $count"

    pause_menu
}

# ============================================================
# 5. USER DETAIL
# ============================================================

user_detail() {
    header

    echo "VLESS USER DETAIL"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t user_list < <(
        sqlite3 -separator '|' "$DB" "
            SELECT username, expiry_date, limit_ip
            FROM users
            WHERE LOWER(protocol)='vless'
            ORDER BY id;
        "
    )

    if [[ ${#user_list[@]} -eq 0 ]]; then
        echo "Belum ada VLESS user."
        pause_menu
        return
    fi

    local i=1

    for row in "${user_list[@]}"; do
        IFS='|' read -r username expiry limit_ip <<< "$row"

        printf "  %-3s %-22s Exp: %-10s Limit: %s\n" \
            "$i." "$username" "$expiry" "$limit_ip"

        ((i++))
    done

    echo
    echo "  0. BACK"
    echo

    local max_choice=${#user_list[@]}

    read -r -p "Pilih User [ 0 - $max_choice ] : " user_choice

    if [[ "$user_choice" == "0" ]]; then
        return
    fi

    if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || \
       (( user_choice < 1 || user_choice > max_choice )); then

        echo
        echo -e "${RED}Pilihan user tidak valid.${RESET}"
        pause_menu
        return
    fi

    local selected
    selected="${user_list[$((user_choice-1))]}"

    IFS='|' read -r username expiry limit_ip <<< "$selected"

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
          AND LOWER(protocol)='vless'
        LIMIT 1;
    " | while IFS='|' read -r \
        username protocol uuid password limit_ip expiry status created updated
    do
        echo "Username     : $username"
        echo "Protocol     : VLESS"
        echo "UUID         : $uuid"
        echo "Limit IP     : $limit_ip"
        echo "Expiry Date  : $expiry"
        echo "Status       : $status"
        echo "Created      : $created"
        echo "Updated      : $updated"
    done

    pause_menu
}

# ============================================================
# 6. DISABLE / ENABLE USER
# ============================================================

toggle_user() {
    header

    echo "DISABLE / ENABLE VLESS USER"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t user_list < <(
        sqlite3 -separator '|' "$DB" "
            SELECT username, expiry_date, limit_ip, status
            FROM users
            WHERE LOWER(protocol)='vless'
            ORDER BY id;
        "
    )

    if [[ ${#user_list[@]} -eq 0 ]]; then
        echo "Belum ada VLESS user."
        pause_menu
        return
    fi

    local i=1

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
        return
    fi

    if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || \
       (( user_choice < 1 || user_choice > max_choice )); then

        echo
        echo -e "${RED}Pilihan user tidak valid.${RESET}"
        pause_menu
        return
    fi

    local selected
    selected="${user_list[$((user_choice-1))]}"

    IFS='|' read -r username expiry limit_ip current_status <<< "$selected"

    echo
    echo "Username       : $username"
    echo "Status Sekarang : $current_status"
    echo

    local new_status
    local action

    if [[ "$current_status" == "active" ]]; then
        new_status="disabled"
        action="disable"
    else
        new_status="active"
        action="enable"
    fi

    read -r -p "Ubah status menjadi $new_status? [y/N] : " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo
        echo "Perubahan dibatalkan."
        pause_menu
        return
    fi

    sqlite3 "$DB" "
        UPDATE users
        SET status='$new_status',
            updated_at=CURRENT_TIMESTAMP
        WHERE username='$username'
          AND LOWER(protocol)='vless';
    "

    echo
    echo -e "${GREEN}VLESS user berhasil di-$action.${RESET}"
    echo
    echo "Username : $username"
    echo "Status   : $current_status -> $new_status"

    pause_menu
}

# ============================================================
# 7. CHANGE IP LIMIT
# ============================================================

change_ip_limit() {
    header

    echo "CHANGE VLESS IP LIMIT"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t user_list < <(
        sqlite3 -separator '|' "$DB" "
            SELECT username, expiry_date, limit_ip, status
            FROM users
            WHERE LOWER(protocol)='vless'
            ORDER BY id;
        "
    )

    if [[ ${#user_list[@]} -eq 0 ]]; then
        echo "Belum ada VLESS user."
        pause_menu
        return
    fi

    local i=1

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
        return
    fi

    if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || \
       (( user_choice < 1 || user_choice > max_choice )); then

        echo
        echo -e "${RED}Pilihan user tidak valid.${RESET}"
        pause_menu
        return
    fi

    local selected
    selected="${user_list[$((user_choice-1))]}"

    IFS='|' read -r username expiry current_limit status <<< "$selected"

    echo
    echo "Username          : $username"
    echo "Limit IP Sekarang : $current_limit"
    echo

    local new_limit

    read -r -p "Limit IP Baru     : " new_limit

    if ! [[ "$new_limit" =~ ^[0-9]+$ ]] || (( new_limit < 1 )); then
        echo
        echo -e "${RED}Limit IP harus berupa angka minimal 1.${RESET}"
        pause_menu
        return
    fi

    echo
    read -r -p "Ubah Limit IP menjadi $new_limit? [y/N] : " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo
        echo "Perubahan dibatalkan."
        pause_menu
        return
    fi

    sqlite3 "$DB" "
        UPDATE users
        SET limit_ip=$new_limit,
            updated_at=CURRENT_TIMESTAMP
        WHERE username='$username'
          AND LOWER(protocol)='vless';
    "

    echo
    echo -e "${GREEN}VLESS IP Limit berhasil diubah.${RESET}"
    echo
    echo "Username : $username"
    echo "Limit    : $current_limit -> $new_limit"

    pause_menu
}

# ============================================================
# 8. GENERATE CONFIG
# ============================================================

generate_config() {
    header

    echo "GENERATE VLESS CONFIG"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t user_list < <(
        sqlite3 -separator '|' "$DB" "
            SELECT username, expiry_date, limit_ip
            FROM users
            WHERE LOWER(protocol)='vless'
            ORDER BY id;
        "
    )

    if [[ ${#user_list[@]} -eq 0 ]]; then
        echo "Belum ada VLESS user."
        pause_menu
        return
    fi

    local i=1

    for row in "${user_list[@]}"; do
        IFS='|' read -r username expiry limit_ip <<< "$row"

        printf "  %-3s %-22s Exp: %-10s Limit: %s\n" \
            "$i." "$username" "$expiry" "$limit_ip"

        ((i++))
    done

    echo
    echo "  0. BACK"
    echo

    local max_choice=${#user_list[@]}

    read -r -p "Pilih User [ 0 - $max_choice ] : " user_choice

    if [[ "$user_choice" == "0" ]]; then
        return
    fi

    if ! [[ "$user_choice" =~ ^[0-9]+$ ]] || \
       (( user_choice < 1 || user_choice > max_choice )); then

        echo
        echo -e "${RED}Pilihan user tidak valid.${RESET}"
        pause_menu
        return
    fi

    local selected
    selected="${user_list[$((user_choice-1))]}"

    IFS='|' read -r username expiry limit_ip <<< "$selected"

    local user_data
    local uuid
    local password
    local status

    user_data="$(
        sqlite3 -separator '|' "$DB" "
            SELECT uuid, password, status
            FROM users
            WHERE username='$username'
              AND LOWER(protocol)='vless'
            LIMIT 1;
        "
    )"

    IFS='|' read -r uuid password status <<< "$user_data"

    show_vless_links "$username" "$uuid"

    pause_menu
}

# ============================================================
# MAIN MENU
# ============================================================

main_menu() {

    if ! check_db; then
        exit 1
    fi

    while true; do

        header

        echo "┌────────────────────────────────────────────────────────┐"
        echo "│                                                        │"
        echo "│     1. ADD VLESS USER                                  │"
        echo "│     2. CREATE TRIAL                               │"
        echo "│     3. DELETE VLESS USER                                │"
        echo "│     4. RENEW VLESS USER                                │"
        echo "│     5. LIST VLESS USERS                                     │"
        echo "│     6. USER DETAIL                           │"
        echo "│     7. DISABLE / ENABLE USER                                 │"
        echo "│     8. CHANGE IP LIMIT                                 │"
        echo "│                                                        │"
        echo "│     9. GENERATE CONFIG                                             │"
        echo "│                                                        │"
        echo "└────────────────────────────────────────────────────────┘"
        echo

        printf "  Select From Options [ 0 - 9 ] : "
        read -r choice

        case "$choice" in

            1)
                add_user
                ;;

            2)
                create_trial
                ;;

            3)
                delete_user
                ;;

            4)
                renew_user
                ;;

            5)
                list_users
                ;;

            6)
                user_detail
                ;;

            7)
                toggle_user
                ;;

            8)
                change_ip_limit
                ;;

            9)
                generate_config
                ;;

            0)
                clear
                exit 0
                ;;

            *)
                echo
                echo -e "${RED}Pilihan tidak valid.${RESET}"
                sleep 1
                ;;

        esac

    done
}

main_menu
