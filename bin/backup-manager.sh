#!/usr/bin/env bash

set -Eeuo pipefail

BASE_DIR="/opt/nagara-tunnel-lite"
BACKUP_DIR="$BASE_DIR/backups/full"
XRAY_CONFIG="/usr/local/etc/xray/config.json"

mkdir -p "$BACKUP_DIR"

timestamp() {
    date '+%Y%m%d-%H%M%S'
}

pause_menu() {
    echo
    read -r -p "Tekan Enter untuk kembali..."
}

create_backup() {
    local stamp
    local backup_file
    local temp_dir

    stamp="$(timestamp)"
    backup_file="$BACKUP_DIR/nagara-backup-$stamp.tar.gz"
    temp_dir="$(mktemp -d)"

    echo
    echo "========================================"
    echo "          CREATE FULL BACKUP"
    echo "========================================"
    echo
    echo "Menyiapkan backup..."

    mkdir -p "$temp_dir/project"
    mkdir -p "$temp_dir/system"

    echo "→ Backup project..."
    cp -a "$BASE_DIR/config" "$temp_dir/project/" 2>/dev/null || true
    cp -a "$BASE_DIR/users" "$temp_dir/project/" 2>/dev/null || true
    cp -a "$BASE_DIR/bin" "$temp_dir/project/" 2>/dev/null || true
    cp -a "$BASE_DIR/core" "$temp_dir/project/" 2>/dev/null || true
    cp -a "$BASE_DIR/menu.sh" "$temp_dir/project/" 2>/dev/null || true
    cp -a "$BASE_DIR/install.sh" "$temp_dir/project/" 2>/dev/null || true

    echo "→ Backup Xray config..."
    if [[ -f "$XRAY_CONFIG" ]]; then
        mkdir -p "$temp_dir/system/xray"
        cp -a "$XRAY_CONFIG" "$temp_dir/system/xray/config.json"
    fi

    echo "→ Backup Nginx config..."
    if [[ -d /etc/nginx ]]; then
        mkdir -p "$temp_dir/system/nginx"
        cp -a /etc/nginx/sites-available "$temp_dir/system/nginx/" 2>/dev/null || true
        cp -a /etc/nginx/sites-enabled "$temp_dir/system/nginx/" 2>/dev/null || true
    fi

    echo "→ Backup HAProxy config..."
    if [[ -f /etc/haproxy/haproxy.cfg ]]; then
        mkdir -p "$temp_dir/system/haproxy"
        cp -a /etc/haproxy/haproxy.cfg "$temp_dir/system/haproxy/"
    fi

    echo "→ Backup Dropbear config..."
    if [[ -f /etc/default/dropbear ]]; then
        mkdir -p "$temp_dir/system/dropbear"
        cp -a /etc/default/dropbear "$temp_dir/system/dropbear/"
    fi

    echo "→ Membuat arsip..."

    tar -czf "$backup_file" \
        -C "$temp_dir" \
        project \
        system

    rm -rf "$temp_dir"

    if [[ -f "$backup_file" ]]; then
        echo
        echo "✓ BACKUP BERHASIL"
        echo
        echo "File : $backup_file"
        echo "Size : $(du -h "$backup_file" | awk '{print $1}')"
    else
        echo
        echo "✗ BACKUP GAGAL"
    fi

    pause_menu
}

list_backups() {
    echo
    echo "========================================"
    echo "             LIST BACKUPS"
    echo "========================================"
    echo

    shopt -s nullglob
    local files=("$BACKUP_DIR"/*.tar.gz)
    shopt -u nullglob

    if (( ${#files[@]} == 0 )); then
        echo "Belum ada full backup."
        pause_menu
        return
    fi

    printf "%-4s %-32s %-10s\n" "NO" "BACKUP" "SIZE"
    printf "%-4s %-32s %-10s\n" "----" "--------------------------------" "----------"

    local i=1
    local file
    for file in "${files[@]}"; do
        printf "%-4s %-32s %-10s\n" \
            "$i" \
            "$(basename "$file")" \
            "$(du -h "$file" | awk '{print $1}')"
        ((i++))
    done

    pause_menu
}

restore_backup() {
    echo
    echo "========================================"
    echo "            RESTORE BACKUP"
    echo "========================================"
    echo

    shopt -s nullglob
    local files=("$BACKUP_DIR"/*.tar.gz)
    shopt -u nullglob

    if (( ${#files[@]} == 0 )); then
        echo "Belum ada backup."
        pause_menu
        return
    fi

    local i=1
    local file
    for file in "${files[@]}"; do
        echo "$i. $(basename "$file")"
        ((i++))
    done

    echo
    read -r -p "Pilih nomor backup: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#files[@]} )); then
        echo
        echo "Pilihan tidak valid."
        pause_menu
        return
    fi

    file="${files[$((choice-1))]}"

    echo
    echo "Backup yang dipilih:"
    echo "$(basename "$file")"
    echo
    echo "PERINGATAN:"
    echo "Restore akan mengganti file konfigurasi/project dengan"
    echo "versi yang ada di dalam backup."
    echo

    read -r -p "Lanjutkan restore? ketik YES: " confirm

    if [[ "$confirm" != "YES" ]]; then
        echo
        echo "Restore dibatalkan."
        pause_menu
        return
    fi

    local restore_dir
    restore_dir="$(mktemp -d)"

    echo
    echo "Mengekstrak backup..."

    if ! tar -xzf "$file" -C "$restore_dir"; then
        rm -rf "$restore_dir"
        echo
        echo "✗ Backup tidak dapat diekstrak."
        pause_menu
        return
    fi

    echo "Memulihkan project..."

    if [[ -d "$restore_dir/project/config" ]]; then
        cp -a "$restore_dir/project/config/." "$BASE_DIR/config/"
    fi

    if [[ -d "$restore_dir/project/users" ]]; then
        cp -a "$restore_dir/project/users/." "$BASE_DIR/users/"
    fi

    if [[ -d "$restore_dir/project/bin" ]]; then
        cp -a "$restore_dir/project/bin/." "$BASE_DIR/bin/"
    fi

    if [[ -d "$restore_dir/project/core" ]]; then
        cp -a "$restore_dir/project/core/." "$BASE_DIR/core/"
    fi

    if [[ -f "$restore_dir/project/menu.sh" ]]; then
        cp -a "$restore_dir/project/menu.sh" "$BASE_DIR/menu.sh"
    fi

    if [[ -f "$restore_dir/project/install.sh" ]]; then
        cp -a "$restore_dir/project/install.sh" "$BASE_DIR/install.sh"
    fi

    echo "Memulihkan konfigurasi Xray..."

    if [[ -f "$restore_dir/system/xray/config.json" ]]; then
        mkdir -p "$(dirname "$XRAY_CONFIG")"
        cp -a "$restore_dir/system/xray/config.json" "$XRAY_CONFIG"
    fi

    echo "Memulihkan konfigurasi Nginx..."

    if [[ -d "$restore_dir/system/nginx/sites-available" ]]; then
        mkdir -p /etc/nginx
        cp -a "$restore_dir/system/nginx/sites-available" /etc/nginx/
    fi

    if [[ -d "$restore_dir/system/nginx/sites-enabled" ]]; then
        mkdir -p /etc/nginx
        cp -a "$restore_dir/system/nginx/sites-enabled" /etc/nginx/
    fi

    echo "Memulihkan konfigurasi HAProxy..."

    if [[ -f "$restore_dir/system/haproxy/haproxy.cfg" ]]; then
        mkdir -p /etc/haproxy
        cp -a "$restore_dir/system/haproxy/haproxy.cfg" /etc/haproxy/
    fi

    echo "Memulihkan konfigurasi Dropbear..."

    if [[ -f "$restore_dir/system/dropbear/dropbear" ]]; then
        mkdir -p /etc/default
        cp -a "$restore_dir/system/dropbear/dropbear" /etc/default/
    fi

    rm -rf "$restore_dir"

    chmod +x "$BASE_DIR/menu.sh" 2>/dev/null || true
    chmod +x "$BASE_DIR/bin/"*.sh 2>/dev/null || true
    chmod +x "$BASE_DIR/core/"*.sh 2>/dev/null || true

    echo
    echo "✓ RESTORE BERHASIL"
    echo
    echo "Disarankan restart service yang diperlukan melalui"
    echo "menu XRAY / DOMAIN / SSL setelah restore."
    pause_menu
}

delete_backup() {
    echo
    echo "========================================"
    echo "             DELETE BACKUP"
    echo "========================================"
    echo

    shopt -s nullglob
    local files=("$BACKUP_DIR"/*.tar.gz)
    shopt -u nullglob

    if (( ${#files[@]} == 0 )); then
        echo "Belum ada backup."
        pause_menu
        return
    fi

    local i=1
    local file
    for file in "${files[@]}"; do
        echo "$i. $(basename "$file")"
        ((i++))
    done

    echo
    read -r -p "Pilih nomor backup yang dihapus: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#files[@]} )); then
        echo
        echo "Pilihan tidak valid."
        pause_menu
        return
    fi

    file="${files[$((choice-1))]}"

    echo
    echo "Akan menghapus:"
    echo "$(basename "$file")"
    echo

    read -r -p "Ketik DELETE untuk konfirmasi: " confirm

    if [[ "$confirm" != "DELETE" ]]; then
        echo
        echo "Penghapusan dibatalkan."
        pause_menu
        return
    fi

    rm -f "$file"

    echo
    echo "✓ Backup berhasil dihapus."
    pause_menu
}

backup_info() {
    echo
    echo "========================================"
    echo "              BACKUP INFO"
    echo "========================================"
    echo
    echo "Full backup directory :"
    echo "$BACKUP_DIR"
    echo
    echo "Xray backup directory :"
    echo "$BASE_DIR/backups/xray"
    echo

    echo "Project:"
    echo "  $BASE_DIR/config/config.conf"
    echo "  $BASE_DIR/users/users.db"
    echo "  $BASE_DIR/bin/"
    echo "  $BASE_DIR/core/"
    echo "  $BASE_DIR/menu.sh"
    echo
    echo "System:"
    echo "  $XRAY_CONFIG"
    echo "  /etc/nginx/sites-available/"
    echo "  /etc/nginx/sites-enabled/"
    echo "  /etc/haproxy/haproxy.cfg"
    echo "  /etc/default/dropbear"
    echo

    if [[ -d "$BACKUP_DIR" ]]; then
        echo "Jumlah full backup : $(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' | wc -l)"
    fi

    pause_menu
}

main_menu() {
    while true; do
        clear

        echo "========================================"
        echo "           BACKUP / RESTORE"
        echo "========================================"
        echo
        echo "1. CREATE BACKUP"
        echo "2. LIST BACKUPS"
        echo "3. RESTORE BACKUP"
        echo "4. DELETE BACKUP"
        echo "5. BACKUP INFO"
        echo "0. BACK"
        echo
        printf "Pilih menu: "
        read -r choice

        case "$choice" in
            1) create_backup ;;
            2) list_backups ;;
            3) restore_backup ;;
            4) delete_backup ;;
            5) backup_info ;;
            0) exit 0 ;;
            *)
                echo
                echo "Pilihan tidak valid."
                sleep 1
                ;;
        esac
    done
}

main_menu
