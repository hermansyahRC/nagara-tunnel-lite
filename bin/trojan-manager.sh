#!/usr/bin/env bash

set -u

APP_DIR="/opt/nagara-tunnel-lite"
DB="$APP_DIR/users/users.db"

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'

header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${WHITE}                 TROJAN MANAGER                        ${CYAN}║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${RESET}"
    echo
}

pause_menu() {
    echo
    read -r -p "Tekan Enter untuk kembali..."
}

check_db() {
    if [[ ! -f "$DB" ]]; then
        echo -e "${RED}Database tidak ditemukan:${RESET} $DB"
        pause_menu
        return 1
    fi
    return 0
}

generate_password() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16
    echo
}

add_user() {
    header
    echo "ADD TROJAN USER"
    echo "────────────────────────────────────────────────────────"
    echo

    read -r -p "Username       : " username

    if [[ -z "$username" ]]; then
        echo -e "${RED}Username tidak boleh kosong.${RESET}"
        pause_menu
        return
    fi

    if ! [[ "$username" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo -e "${RED}Username hanya boleh berisi huruf, angka, titik, underscore, dan dash.${RESET}"
        pause_menu
        return
    fi

    if sqlite3 "$DB" "SELECT 1 FROM users WHERE username='$username' LIMIT 1;" | grep -q 1; then
        echo -e "${RED}Username sudah digunakan.${RESET}"
        pause_menu
        return
    fi

    read -r -p "Active Days    : " days

    if ! [[ "$days" =~ ^[0-9]+$ ]] || (( days < 1 )); then
        echo -e "${RED}Active Days harus berupa angka minimal 1.${RESET}"
        pause_menu
        return
    fi

    read -r -p "Limit IP       : " limit_ip

    if ! [[ "$limit_ip" =~ ^[0-9]+$ ]] || (( limit_ip < 1 )); then
        echo -e "${RED}Limit IP harus berupa angka minimal 1.${RESET}"
        pause_menu
        return
    fi

    password="$(generate_password)"
    expiry_date="$(date -d "+${days} days" '+%Y-%m-%d')"

    sqlite3 "$DB" <<EOF
INSERT INTO users (
    username,
    protocol,
    uuid,
    password,
    limit_ip,
    expiry_date,
    status
) VALUES (
    '$username',
    'trojan',
    NULL,
    '$password',
    $limit_ip,
    '$expiry_date',
    'active'
);
EOF

    echo
    echo -e "${GREEN}Trojan user berhasil dibuat.${RESET}"
    echo "Username : $username"
    echo "Password : $password"
    echo "Duration : $days days"
    echo "Expiry   : $expiry_date"
    echo "Limit IP : $limit_ip"
    echo "Status   : active"

    pause_menu
}

delete_user() {
    header
    echo "DELETE TROJAN USER"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t users < <(
        sqlite3 -separator '|' "$DB" \
        "SELECT username, expiry_date, limit_ip
         FROM users
         WHERE protocol='trojan'
         ORDER BY username;"
    )

    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Belum ada Trojan user.${RESET}"
        pause_menu
        return
    fi

    local i=1
    local username expiry limit

    for row in "${users[@]}"; do
        IFS='|' read -r username expiry limit <<< "$row"
        printf "  %d.  %-22s Exp: %-10s Limit: %s\n" \
            "$i" "$username" "$expiry" "$limit"
        ((i++))
    done

    echo "  0. BACK"
    echo

    read -r -p "Pilih User [ 0 - ${#users[@]} ] : " choice

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
       (( choice < 1 || choice > ${#users[@]} )); then
        echo -e "${RED}Pilihan tidak valid.${RESET}"
        pause_menu
        return
    fi

    row="${users[$((choice-1))]}"
    IFS='|' read -r username expiry limit <<< "$row"

    echo
    echo "User yang akan dihapus:"
    echo "Username : $username"
    echo "Expiry   : $expiry"
    echo "Limit IP : $limit"
    echo

    read -r -p "Hapus user $username? [y/N] : " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Penghapusan dibatalkan."
        pause_menu
        return
    fi

    sqlite3 "$DB" \
        "DELETE FROM users
         WHERE username='$username'
         AND protocol='trojan';"

    echo
    echo -e "${GREEN}Trojan user berhasil dihapus.${RESET}"
    echo "Username : $username"

    pause_menu
}

renew_user() {
    header
    echo "RENEW TROJAN USER"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t users < <(
        sqlite3 -separator '|' "$DB" \
        "SELECT username, expiry_date, limit_ip
         FROM users
         WHERE protocol='trojan'
         ORDER BY username;"
    )

    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Belum ada Trojan user.${RESET}"
        pause_menu
        return
    fi

    local i=1
    local username expiry limit

    for row in "${users[@]}"; do
        IFS='|' read -r username expiry limit <<< "$row"
        printf "  %d.  %-22s Exp: %-10s Limit: %s\n" \
            "$i" "$username" "$expiry" "$limit"
        ((i++))
    done

    echo "  0. BACK"
    echo

    read -r -p "Pilih User [ 0 - ${#users[@]} ] : " choice

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
       (( choice < 1 || choice > ${#users[@]} )); then
        echo -e "${RED}Pilihan tidak valid.${RESET}"
        pause_menu
        return
    fi

    row="${users[$((choice-1))]}"
    IFS='|' read -r username expiry limit <<< "$row"

    echo
    read -r -p "Tambah Hari : " days

    if ! [[ "$days" =~ ^[0-9]+$ ]] || (( days < 1 )); then
        echo -e "${RED}Jumlah hari harus berupa angka minimal 1.${RESET}"
        pause_menu
        return
    fi

    old_expiry="$expiry"
    today="$(date '+%Y-%m-%d')"

    if [[ "$expiry" < "$today" ]]; then
        new_expiry="$(date -d "+${days} days" '+%Y-%m-%d')"
    else
        new_expiry="$(date -d "$expiry + ${days} days" '+%Y-%m-%d')"
    fi

    sqlite3 "$DB" <<EOF
UPDATE users
SET expiry_date='$new_expiry',
    status='active',
    updated_at=CURRENT_TIMESTAMP
WHERE username='$username'
  AND protocol='trojan';
EOF

    echo
    echo -e "${GREEN}Trojan user berhasil diperpanjang.${RESET}"
    echo "Username     : $username"
    echo "Expired Lama : $old_expiry"
    echo "Tambah Hari  : $days"
    echo "Expired Baru : $new_expiry"
    echo "Status       : active"

    pause_menu
}

list_users() {
    header
    echo "TROJAN USERS"
    echo "────────────────────────────────────────────────────────"
    echo

    printf "%-15s %-11s %-9s %-8s\n" \
        "USERNAME" "EXPIRED" "LIMIT_IP" "STATUS"

    printf "%-15s %-11s %-9s %-8s\n" \
        "---------------" "----------" "---------" "------"

    count="$(
        sqlite3 "$DB" \
        "SELECT COUNT(*)
         FROM users
         WHERE protocol='trojan';"
    )"

    if [[ "$count" -eq 0 ]]; then
        echo
        echo -e "${YELLOW}Belum ada Trojan user.${RESET}"
        pause_menu
        return
    fi

    sqlite3 -separator '|' "$DB" \
        "SELECT username, expiry_date, limit_ip, status
         FROM users
         WHERE protocol='trojan'
         ORDER BY username;" |
    while IFS='|' read -r username expiry limit status; do
        printf "%-15s %-11s %-9s %-8s\n" \
            "$username" "$expiry" "$limit" "$status"
    done

    echo
    echo "Total Trojan User : $count"

    pause_menu
}

user_detail() {
    header
    echo "TROJAN USER DETAIL"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t users < <(
        sqlite3 "$DB" \
        "SELECT username
         FROM users
         WHERE protocol='trojan'
         ORDER BY username;"
    )

    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Belum ada Trojan user.${RESET}"
        pause_menu
        return
    fi

    local i=1
    local username expiry limit

    for username in "${users[@]}"; do
        expiry="$(
            sqlite3 "$DB" \
            "SELECT expiry_date
             FROM users
             WHERE username='$username'
             AND protocol='trojan';"
        )"

        limit="$(
            sqlite3 "$DB" \
            "SELECT limit_ip
             FROM users
             WHERE username='$username'
             AND protocol='trojan';"
        )"

        printf "  %d.  %-22s Exp: %-10s Limit: %s\n" \
            "$i" "$username" "$expiry" "$limit"

        ((i++))
    done

    echo "  0. BACK"
    echo

    read -r -p "Pilih User [ 0 - ${#users[@]} ] : " choice

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
       (( choice < 1 || choice > ${#users[@]} )); then
        echo -e "${RED}Pilihan tidak valid.${RESET}"
        pause_menu
        return
    fi

    username="${users[$((choice-1))]}"

    IFS='|' read -r \
        username \
        protocol \
        password \
        limit \
        expiry \
        status \
        created \
        updated < <(
            sqlite3 -separator '|' "$DB" \
            "SELECT
                username,
                protocol,
                password,
                limit_ip,
                expiry_date,
                status,
                created_at,
                updated_at
             FROM users
             WHERE username='$username'
             AND protocol='trojan';"
        )

    echo
    echo "Username     : $username"
    echo "Protocol     : Trojan"
    echo "Password     : $password"
    echo "Limit IP     : $limit"
    echo "Expiry Date  : $expiry"
    echo "Status       : $status"
    echo "Created      : $created"
    echo "Updated      : $updated"

    pause_menu
}

toggle_user() {
    header
    echo "DISABLE / ENABLE TROJAN USER"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t users < <(
        sqlite3 -separator '|' "$DB" \
        "SELECT username, expiry_date, limit_ip, status
         FROM users
         WHERE protocol='trojan'
         ORDER BY username;"
    )

    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Belum ada Trojan user.${RESET}"
        pause_menu
        return
    fi

    local i=1
    local username expiry limit status

    for row in "${users[@]}"; do
        IFS='|' read -r username expiry limit status <<< "$row"

        printf "  %d.  %-22s Exp: %-10s Limit: %-3s Status: %s\n" \
            "$i" "$username" "$expiry" "$limit" "$status"

        ((i++))
    done

    echo "  0. BACK"
    echo

    read -r -p "Pilih User [ 0 - ${#users[@]} ] : " choice

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
       (( choice < 1 || choice > ${#users[@]} )); then
        echo -e "${RED}Pilihan tidak valid.${RESET}"
        pause_menu
        return
    fi

    row="${users[$((choice-1))]}"
    IFS='|' read -r username expiry limit status <<< "$row"

    echo
    echo "Username        : $username"
    echo "Status Sekarang : $status"

    if [[ "$status" == "active" ]]; then
        new_status="disabled"
        action="disable"
    else
        new_status="active"
        action="enable"
    fi

    read -r -p "Ubah status menjadi $new_status? [y/N] : " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Perubahan status dibatalkan."
        pause_menu
        return
    fi

    sqlite3 "$DB" <<EOF
UPDATE users
SET status='$new_status',
    updated_at=CURRENT_TIMESTAMP
WHERE username='$username'
  AND protocol='trojan';
EOF

    echo
    echo -e "${GREEN}Trojan user berhasil di-$action.${RESET}"
    echo "Username : $username"
    echo "Status   : $status -> $new_status"

    pause_menu
}

change_ip_limit() {
    header
    echo "CHANGE TROJAN IP LIMIT"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t users < <(
        sqlite3 -separator '|' "$DB" \
        "SELECT username, expiry_date, limit_ip, status
         FROM users
         WHERE protocol='trojan'
         ORDER BY username;"
    )

    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Belum ada Trojan user.${RESET}"
        pause_menu
        return
    fi

    local i=1
    local username expiry limit status

    for row in "${users[@]}"; do
        IFS='|' read -r username expiry limit status <<< "$row"

        printf "  %d.  %-22s Exp: %-10s Limit: %-3s Status: %s\n" \
            "$i" "$username" "$expiry" "$limit" "$status"

        ((i++))
    done

    echo "  0. BACK"
    echo

    read -r -p "Pilih User [ 0 - ${#users[@]} ] : " choice

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
       (( choice < 1 || choice > ${#users[@]} )); then
        echo -e "${RED}Pilihan tidak valid.${RESET}"
        pause_menu
        return
    fi

    row="${users[$((choice-1))]}"
    IFS='|' read -r username expiry limit status <<< "$row"

    echo
    echo "Username          : $username"
    echo "Limit IP Sekarang : $limit"

    read -r -p "Limit IP Baru     : " new_limit

    if ! [[ "$new_limit" =~ ^[0-9]+$ ]] || (( new_limit < 1 )); then
        echo -e "${RED}Limit IP harus berupa angka minimal 1.${RESET}"
        pause_menu
        return
    fi

    read -r -p "Ubah Limit IP menjadi $new_limit? [y/N] : " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Perubahan Limit IP dibatalkan."
        pause_menu
        return
    fi

    sqlite3 "$DB" <<EOF
UPDATE users
SET limit_ip=$new_limit,
    updated_at=CURRENT_TIMESTAMP
WHERE username='$username'
  AND protocol='trojan';
EOF

    echo
    echo -e "${GREEN}Trojan IP Limit berhasil diubah.${RESET}"
    echo "Username : $username"
    echo "Limit    : $limit -> $new_limit"

    pause_menu
}

generate_config() {
    header
    echo "GENERATE TROJAN CONFIG"
    echo "────────────────────────────────────────────────────────"
    echo

    mapfile -t users < <(
        sqlite3 "$DB" \
        "SELECT username
         FROM users
         WHERE protocol='trojan'
         ORDER BY username;"
    )

    if [[ ${#users[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Belum ada Trojan user.${RESET}"
        pause_menu
        return
    fi

    local i=1
    local username expiry limit

    for username in "${users[@]}"; do
        expiry="$(
            sqlite3 "$DB" \
            "SELECT expiry_date
             FROM users
             WHERE username='$username'
             AND protocol='trojan';"
        )"

        limit="$(
            sqlite3 "$DB" \
            "SELECT limit_ip
             FROM users
             WHERE username='$username'
             AND protocol='trojan';"
        )"

        printf "  %d.  %-22s Exp: %-10s Limit: %s\n" \
            "$i" "$username" "$expiry" "$limit"

        ((i++))
    done

    echo "  0. BACK"
    echo

    read -r -p "Pilih User [ 0 - ${#users[@]} ] : " choice

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
       (( choice < 1 || choice > ${#users[@]} )); then
        echo -e "${RED}Pilihan tidak valid.${RESET}"
        pause_menu
        return
    fi

    username="${users[$((choice-1))]}"

    IFS='|' read -r \
        username \
        password \
        expiry \
        limit \
        status < <(
            sqlite3 -separator '|' "$DB" \
            "SELECT
                username,
                password,
                expiry_date,
                limit_ip,
                status
             FROM users
             WHERE username='$username'
             AND protocol='trojan';"
        )

    echo
    echo "TROJAN CONFIG"
    echo "────────────────────────────────────────────────────────"
    echo "Username     : $username"
    echo "Password     : $password"
    echo "Expiry       : $expiry"
    echo "Limit IP     : $limit"
    echo "Status       : $status"
    echo
    echo -e "${GREEN}Account config berhasil dibuat.${RESET}"
    echo "Endpoint server belum dikonfigurasi."
    echo "Domain / Port / TLS / Transport akan diambil"
    echo "dari konfigurasi server pada tahap berikutnya."

    pause_menu
}

main_menu() {
    while true; do
        header

        echo "┌────────────────────────────────────────────────────────┐"
        echo "│                                                        │"
        echo "│     1. ADD TROJAN USER                                 │"
        echo "│     2. DELETE TROJAN USER                              │"
        echo "│     3. RENEW TROJAN USER                               │"
        echo "│     4. LIST TROJAN USERS                               │"
        echo "│     5. USER DETAIL                                     │"
        echo "│     6. DISABLE / ENABLE USER                           │"
        echo "│     7. CHANGE IP LIMIT                                 │"
        echo "│     8. GENERATE CONFIG                                 │"
        echo "│     0. BACK                                             │"
        echo "│                                                        │"
        echo "└────────────────────────────────────────────────────────┘"
        echo

        printf "  Select From Options [ 0 - 8 ] : "
        read -r choice

        case "$choice" in
            1) add_user ;;
            2) delete_user ;;
            3) renew_user ;;
            4) list_users ;;
            5) user_detail ;;
            6) toggle_user ;;
            7) change_ip_limit ;;
            8) generate_config ;;
            0) return ;;
            *)
                echo
                echo -e "${RED}Pilihan tidak valid.${RESET}"
                sleep 1
                ;;
        esac
    done
}

check_db || exit 1
main_menu
