#!/usr/bin/env bash
# Startet den lokalen MCP-Server und Quick- oder Named-Cloudflare-Tunnel.
set -euo pipefail

cd "$(dirname "$0")/../.."
REPO_ROOT="$PWD"
ORCH="$REPO_ROOT/orchestrator"
MCP_DIR="$ORCH/mcp"
CONFIG="$ORCH/config.env"
SECRETS="$ORCH/secrets.env"
[ -f "$CONFIG" ] || { echo "mcp-start: $CONFIG fehlt" >&2; exit 2; }

# shellcheck disable=SC1090
source "$CONFIG"
if [ -f "$SECRETS" ]; then
  [ "$(stat -c '%a' "$SECRETS")" = 600 ] \
    || { echo "mcp-start: $SECRETS muss Modus 600 haben" >&2; exit 2; }
  # shellcheck disable=SC1090
  source "$SECRETS"
fi

REPO_PATH="${REPO_PATH:-$REPO_ROOT}"
MCP_HOST="${MCP_HOST:-127.0.0.1}"
PORT="${PORT:-8765}"
MCP_PATH="${MCP_PATH:-/mcp}"
TUNNEL_MODE="${TUNNEL_MODE:-quick}"
MCP_PYTHON="${MCP_PYTHON:-${MCP_ENV_DIR:-}/bin/python}"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-$(command -v cloudflared || true)}"

[ -d "$REPO_PATH" ] || { echo "mcp-start: REPO_PATH fehlt: $REPO_PATH" >&2; exit 2; }
[ -x "$MCP_PYTHON" ] || { echo "mcp-start: MCP-Python fehlt: $MCP_PYTHON" >&2; exit 2; }
[ -x "$CLOUDFLARED_BIN" ] || { echo "mcp-start: cloudflared fehlt: $CLOUDFLARED_BIN" >&2; exit 2; }
case "$PORT" in ''|*[!0-9]*) echo "mcp-start: PORT ungültig" >&2; exit 2 ;; esac
grep -Eq '^/mcp(-[a-f0-9]{16,64})?$' <<<"$MCP_PATH" || { echo "mcp-start: MCP_PATH ungültig" >&2; exit 2; }

SERVER_LOG="$MCP_DIR/server.log"
TUNNEL_LOG="$MCP_DIR/tunnel.log"
URL_FILE="$MCP_DIR/connector.url"
rm -f "$URL_FILE"
SERVER_PID=""
TUNNEL_PID=""

cleanup() {
  local rc="${1:-0}"
  [ -z "$TUNNEL_PID" ] || kill "$TUNNEL_PID" 2>/dev/null || true
  [ -z "$SERVER_PID" ] || kill "$SERVER_PID" 2>/dev/null || true
  wait "$TUNNEL_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  return "$rc"
}
trap 'cleanup $?' EXIT INT TERM

echo "mcp-start: Server $MCP_HOST:$PORT$MCP_PATH (REPO_PATH=$REPO_PATH)"
env -i PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" HOME="${HOME:-/tmp}" LANG="${LANG:-C.UTF-8}" \
  REPO_PATH="$REPO_PATH" MCP_HOST="$MCP_HOST" PORT="$PORT" MCP_PATH="$MCP_PATH" \
  PROJECT_SLUG="${PROJECT_SLUG:-$(basename "$REPO_ROOT")}" \
  "$MCP_PYTHON" "$MCP_DIR/server.py" > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!

HTTP_CODE=000
for _ in $(seq 1 30); do
  kill -0 "$SERVER_PID" 2>/dev/null || { tail -n 40 "$SERVER_LOG" >&2; exit 2; }
  HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' "http://$MCP_HOST:$PORT$MCP_PATH" 2>/dev/null || true)"
  [ "$HTTP_CODE" != 000 ] && break
  sleep 1
done
[ "$HTTP_CODE" != 000 ] || { echo "mcp-start: Serverprobe ohne Antwort" >&2; exit 2; }
echo "mcp-start: Serverprobe HTTP $HTTP_CODE"

ORIGIN="http://$MCP_HOST:$PORT"
case "$TUNNEL_MODE" in
  quick)
    env -i PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" HOME="${HOME:-/tmp}" LANG="${LANG:-C.UTF-8}" \
      "$CLOUDFLARED_BIN" tunnel --url "$ORIGIN" > "$TUNNEL_LOG" 2>&1 &
    TUNNEL_PID=$!
    PUBLIC_BASE=""
    for _ in $(seq 1 40); do
      PUBLIC_BASE="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1 || true)"
      [ -n "$PUBLIC_BASE" ] && break
      kill -0 "$TUNNEL_PID" 2>/dev/null || { tail -n 40 "$TUNNEL_LOG" >&2; exit 2; }
      sleep 1
    done
    [ -n "$PUBLIC_BASE" ] || { echo "mcp-start: keine Quick-Tunnel-URL" >&2; exit 2; }
    ;;
  named)
    [ -n "${TUNNEL_HOSTNAME:-}" ] || { echo "mcp-start: TUNNEL_HOSTNAME fehlt" >&2; exit 2; }
    if [ -n "${TUNNEL_TOKEN:-}" ]; then
      env -i PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" HOME="${HOME:-/tmp}" LANG="${LANG:-C.UTF-8}" \
        TUNNEL_TOKEN="$TUNNEL_TOKEN" "$CLOUDFLARED_BIN" tunnel run --url "$ORIGIN" > "$TUNNEL_LOG" 2>&1 &
    elif [ -n "${TUNNEL_NAME:-}" ]; then
      env -i PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" HOME="${HOME:-/tmp}" LANG="${LANG:-C.UTF-8}" \
        "$CLOUDFLARED_BIN" tunnel run --url "$ORIGIN" "$TUNNEL_NAME" > "$TUNNEL_LOG" 2>&1 &
    else
      echo "mcp-start: TUNNEL_TOKEN oder TUNNEL_NAME fehlt" >&2
      exit 2
    fi
    TUNNEL_PID=$!
    sleep 3
    kill -0 "$TUNNEL_PID" 2>/dev/null || { tail -n 40 "$TUNNEL_LOG" >&2; exit 2; }
    PUBLIC_BASE="https://${TUNNEL_HOSTNAME#https://}"
    PUBLIC_BASE="${PUBLIC_BASE%/}"
    ;;
  *) echo "mcp-start: TUNNEL_MODE muss quick oder named sein" >&2; exit 2 ;;
esac

CONNECTOR_URL="${PUBLIC_BASE}${MCP_PATH}"
printf '%s\n' "$CONNECTOR_URL" > "$URL_FILE"
echo "mcp-start: Connector-URL $CONNECTOR_URL"
echo "mcp-start: URL wie ein Geheimnis behandeln; Logs: $SERVER_LOG, $TUNNEL_LOG"

set +e
wait -n "$SERVER_PID" "$TUNNEL_PID"
WAIT_RC=$?
set -e
echo "mcp-start: Server oder Tunnel beendet (rc=$WAIT_RC)" >&2
exit "$WAIT_RC"
