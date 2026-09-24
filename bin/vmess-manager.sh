#!/usr/bin/env bash

APP_DIR="/opt/nagara-tunnel-lite"
DB="$APP_DIR/users/users.db"
XRAY_SYNC="$APP_DIR/core/xray-sync.sh"

if [[ -f "$APP_DIR/core/colors.sh" ]]; then
    source "$APP_DIR/core/colors.sh"
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
    echo "│     2. DELETE VMESS USER                               │"
    echo "│     3. RENEW VMESS USER                                │"
    echo "│     4. LIST VMESS USERS                                │"
    echo "│     5. USER DETAIL                                     │"
    echo "│     6. DISABLE / ENABLE USER                           │"
    echo "│     7. CHANGE IP LIMIT                                 │"
    echo "│     8. GENERATE CONFIG                                 │"
    echo "│     0. BACK                                             │"
    echo "│                                                        │"
    echo "└────────────────────────────────────────────────────────┘"
    echo
    printf "  Select From Options [ 0 - 8 ] : "
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

        3)
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

        4)
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

        5)
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

        6)
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

        7)
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

        8)
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
                    SELECT uuid, password, status
                    FROM users
                    WHERE username='$username'
                      AND LOWER(protocol)='vmess'
                    LIMIT 1;
                "
            )"

            IFS='|' read -r uuid password status <<< "$user_data"

            echo
            echo "VMess CONFIG"
            echo "────────────────────────────────────────────────────────"
            echo
            echo "Username     : $username"
            echo "UUID         : $uuid"
            echo "Expiry       : $expiry"
            echo "Limit IP     : $limit_ip"
            echo "Status       : $status"
            echo
            echo "Config account berhasil dibuat."
            echo
            echo "Catatan:"
            echo "Endpoint server belum dikonfigurasi."
            echo "Domain / Port / TLS / Transport akan diambil"
            echo "dari konfigurasi server pada tahap berikutnya."
            echo

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
