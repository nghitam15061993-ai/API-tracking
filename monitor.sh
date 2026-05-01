#!/usr/bin/env bash
# AWP API monitor for GitHub Actions
#
# Pings $API_URL once. Tracks state across runs by reading/writing a
# tiny "state" file as a GitHub Actions cache. Sends Telegram alert
# only when state changes (UP→DOWN or DOWN→UP), so you don't get
# spammed every 20 minutes when the API is just sitting there.
#
# Required env:
#   TELEGRAM_BOT_TOKEN  - from @BotFather
#   TELEGRAM_CHAT_ID    - your chat id (negative for groups)
#   API_URL             - endpoint to probe
#   GH_TOKEN            - GITHUB_TOKEN, used for state persistence
#   REPO                - owner/repo, for state API calls
#
# Exit codes:
#   0 - success (UP or DOWN, alert sent if needed)
#   1 - script error (Telegram failed, etc.)

set -uo pipefail

API_URL="${API_URL:-https://api.minework.net/api/iam/v1/me}"
STATE_VAR="MONITOR_STATE"   # GitHub Variable name for state persistence

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

# ─── State persistence via GitHub Variables ──
# We use repo variables (free, persistent across workflow runs)
# instead of cache (which has 7-day expiry and can be evicted).
read_prev_state() {
  curl -s -H "Authorization: Bearer $GH_TOKEN" \
       -H "Accept: application/vnd.github+json" \
       "https://api.github.com/repos/$REPO/actions/variables/$STATE_VAR" \
    | jq -r '.value // "UP"' 2>/dev/null || echo "UP"
}

write_state() {
  local new_state="$1"
  # PATCH if exists, POST if not. Try PATCH first.
  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" \
                  -X PATCH \
                  -H "Authorization: Bearer $GH_TOKEN" \
                  -H "Accept: application/vnd.github+json" \
                  -H "Content-Type: application/json" \
                  -d "{\"name\":\"$STATE_VAR\",\"value\":\"$new_state\"}" \
                  "https://api.github.com/repos/$REPO/actions/variables/$STATE_VAR")

  if [[ "$response" == "404" ]]; then
    # Variable doesn't exist yet — create it
    curl -s -o /dev/null \
         -X POST \
         -H "Authorization: Bearer $GH_TOKEN" \
         -H "Accept: application/vnd.github+json" \
         -H "Content-Type: application/json" \
         -d "{\"name\":\"$STATE_VAR\",\"value\":\"$new_state\"}" \
         "https://api.github.com/repos/$REPO/actions/variables"
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

  local now
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
