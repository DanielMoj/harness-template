#!/usr/bin/env bash
# Ein best-effort POST an einen ntfy-kompatiblen Endpunkt.
set -uo pipefail

cd "$(dirname "$0")/.."
ORCH="$PWD/orchestrator"
if [ -f "$ORCH/config.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ORCH/config.env"
  set +a
fi

EVENT="${1:-}"
shift 2>/dev/null || true
MESSAGE="$*"
case "$EVENT" in
  FATAL|PARKED|ARBITER|NEEDS_HUMAN|DONE|STALE) ;;
  *) echo "notify: unbekanntes Ereignis '$EVENT'" >&2; exit 2 ;;
esac

if [ "${NOTIFY_ENABLED:-1}" != 1 ] || [ -z "${NOTIFY_URL:-}" ]; then
  echo "notify: disabled event=$EVENT"
  exit 0
fi

command -v curl >/dev/null 2>&1 || {
  echo "notify: curl fehlt" >&2
  exit 2
}

TITLE="${NOTIFY_TOPIC:-$(basename "$PWD")}: $EVENT"
if curl -fsS --max-time 10 \
  -H "Title: $TITLE" \
  -H "Tags: $(tr '[:upper:]' '[:lower:]' <<<"$EVENT")" \
  --data-binary "${MESSAGE:-$EVENT}" \
  "$NOTIFY_URL" >/dev/null; then
  echo "notify: sent event=$EVENT"
  exit 0
fi

echo "notify: failed event=$EVENT" >&2
exit 2
