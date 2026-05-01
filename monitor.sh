#!/usr/bin/env bash
# AWP API monitor — always alert every run.
#
# Pings $API_URL once and sends a Telegram message every cycle,
# regardless of whether state changed. Use this if you want a
# heartbeat showing the monitor is alive.
#
# Required env:
#   TELEGRAM_BOT_TOKEN
#   TELEGRAM_CHAT_ID
#   API_URL  (optional, defaults to minework)

set -uo pipefail

API_URL="${API_URL:-https://api.minework.net/api/iam/v1/me}"

# ─── Probe API ──
# Alive: any 2xx/3xx/4xx response (server answered)
# Dead: 5xx, timeout, connection refused
probe() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
              -m 15 \
              -A "awp-monitor/gh-actions" \
              "$API_URL" || echo "000")

  if [[ "$code" == "000" ]]; then
    echo "DEAD|network error or timeout"
    return
  fi
  if (( code >= 200 && code < 500 )); then
    echo "ALIVE|HTTP $code"
  else
    echo "DEAD|HTTP $code"
  fi
}

# ─── Telegram ──
send_telegram() {
  local text="$1"
  local response
  response=$(curl -s -w "\n%{http_code}" \
                  -X POST \
                  "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                  -d "chat_id=$TELEGRAM_CHAT_ID" \
                  -d "text=$text" \
                  -d "parse_mode=HTML" \
                  -d "disable_web_page_preview=true")
  local code
  code=$(echo "$response" | tail -1)
  if [[ "$code" != "200" ]]; then
    echo "Telegram failed with HTTP $code:" >&2
    echo "$response" | head -n -1 >&2
    return 1
  fi
}

# ─── Main ──
main() {
  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    echo "ERROR: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID secrets not set" >&2
    exit 1
  fi

  local result status detail
  result=$(probe)
  status="${result%%|*}"
  detail="${result##*|}"
  echo "[probe] $API_URL → $status ($detail)"

  local now msg
  now=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

  if [[ "$status" == "ALIVE" ]]; then
    msg="🟢 <b>API UP</b>%0A<b>Endpoint</b>: <code>$API_URL</code>%0A<b>Time</b>: $now%0A<b>Status</b>: $detail"
  else
    msg="🔴 <b>API DOWN</b>%0A<b>Endpoint</b>: <code>$API_URL</code>%0A<b>Time</b>: $now%0A<b>Error</b>: $detail"
  fi

  if send_telegram "$msg"; then
    echo "[alert] sent"
  else
    echo "[alert] FAILED" >&2
    exit 1
  fi
}

main
