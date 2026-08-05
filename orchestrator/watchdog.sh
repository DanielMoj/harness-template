#!/usr/bin/env bash
# Cron-Wächter: laufender Orchestrator + alter summary-Heartbeat => STALE.
set -uo pipefail

cd "$(dirname "$0")/.."
ORCH="$PWD/orchestrator"
if [ -f "$ORCH/config.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ORCH/config.env"
  set +a
fi

STALE_SECONDS="${WATCHDOG_STALE_SECONDS:-1800}"
case "$STALE_SECONDS" in ''|*[!0-9]*) echo "watchdog: WATCHDOG_STALE_SECONDS ungültig" >&2; exit 2 ;; esac

PID="$(cat "$ORCH/.lock/pid" 2>/dev/null || true)"
if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
  echo "watchdog: idle (kein laufender Orchestrator)"
  exit 0
fi

SUMMARY="$ORCH/state/summary.json"
[ -f "$SUMMARY" ] || {
  "$ORCH/notify.sh" STALE "Orchestrator PID $PID läuft, aber summary.json fehlt" >/dev/null 2>&1 || true
  echo "watchdog: STALE summary.json fehlt"
  exit 1
}
TS="$(jq -r '.ts // empty' "$SUMMARY" 2>/dev/null || true)"
[ -n "$TS" ] || { echo "watchdog: ungültiger summary-Zeitstempel" >&2; exit 2; }
HEARTBEAT_EPOCH="$(date -d "$TS" +%s 2>/dev/null || true)"
[ -n "$HEARTBEAT_EPOCH" ] || { echo "watchdog: Zeitstempel nicht parsebar: $TS" >&2; exit 2; }
NOW_EPOCH="${WATCHDOG_NOW_EPOCH:-$(date +%s)}"
AGE=$((NOW_EPOCH-HEARTBEAT_EPOCH))

if [ "$AGE" -gt "$STALE_SECONDS" ]; then
  MESSAGE="Orchestrator PID $PID läuft, Heartbeat ist ${AGE}s alt (Grenze ${STALE_SECONDS}s)"
  "$ORCH/notify.sh" STALE "$MESSAGE" >/dev/null 2>&1 || true
  echo "watchdog: STALE age=${AGE}s pid=$PID"
  exit 1
fi
echo "watchdog: fresh age=${AGE}s pid=$PID"
