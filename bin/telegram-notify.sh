#!/usr/bin/env bash

APP_DIR="/opt/nagara-tunnel-lite"
CONFIG_FILE="$APP_DIR/runtime/telegram.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

TELEGRAM_ENABLED="${TELEGRAM_ENABLED:-false}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

telegram_send() {
    local message="$1"

    [[ "$TELEGRAM_ENABLED" == "true" ]] || return 0
    [[ -n "$TELEGRAM_BOT_TOKEN" ]] || return 0
    [[ -n "$TELEGRAM_CHAT_ID" ]] || return 0

    curl -fsS --max-time 10 \
        -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        --data-urlencode "disable_web_page_preview=true" \
        >/dev/null 2>&1 || return 1

    return 0
}

telegram_test() {
    telegram_send "NAGARA TUNNEL LITE

Telegram notification aktif.

Server : $(hostname)
Time   : $(date '+%Y-%m-%d %H:%M:%S')"

    return $?
}

if [[ "${1:-}" == "--test" ]]; then
    telegram_test
    exit $?
fi
