#!/usr/bin/env bash
# T-4: echte Notify-Aufrufe fuer DONE/PARKED und STALE-Watchdog.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

CASE_ROOT="$(new_case_root)"
trap 'cleanup_case "$CASE_ROOT"' EXIT
REPO="$CASE_ROOT/repo"
NOTIFY_LOG="$CASE_ROOT/notify.log"
prepare_orchestrator_case T2 "$REPO"

(
  cd "$REPO"
  export PATH="$REPO/tests/template/fixtures/fake-bin:$PATH"
  export FAKE_NOTIFY_LOG="$NOTIFY_LOG"
  bash orchestrator/notify.sh DONE 'M0 abgeschlossen'
  bash orchestrator/notify.sh PARKED 'M0 geparkt'
  mkdir -p orchestrator/.lock
  printf '%s\n' "$PPID" > orchestrator/.lock/pid
  jq '.ts="2000-01-01T00:00:00+00:00"' orchestrator/state/summary.json \
    > orchestrator/state/.summary-stale.json
  mv orchestrator/state/.summary-stale.json orchestrator/state/summary.json
  set +e
  WATCHDOG_NOW_EPOCH=2000000000 bash orchestrator/watchdog.sh
  watchdog_rc=$?
  set -e
  [ "$watchdog_rc" = 1 ]
  cp orchestrator/state/summary.json "$CASE_ROOT/summary-before-double-start.json"
  heartbeat_epoch="$(date -d "$(jq -r .ts "$CASE_ROOT/summary-before-double-start.json")" +%s)"
  notify_before="$(wc -l < "$NOTIFY_LOG")"
  set +e
  bash orchestrator/orchestrate.sh > "$CASE_ROOT/double-start.log" 2>&1
  double_start_rc=$?
  set -e
  [ "$double_start_rc" = 2 ]
  grep -F "Orchestrator läuft bereits (PID $PPID)" "$CASE_ROOT/double-start.log" >/dev/null
  cmp -s "$CASE_ROOT/summary-before-double-start.json" orchestrator/state/summary.json
  [ "$(wc -l < "$NOTIFY_LOG")" = "$notify_before" ]
  set +e
  WATCHDOG_STALE_SECONDS=30 \
    WATCHDOG_NOW_EPOCH=$((heartbeat_epoch + 60)) bash orchestrator/watchdog.sh
  watchdog_after_rc=$?
  set -e
  [ "$watchdog_after_rc" = 1 ]

  rm -f orchestrator/.lock/pid
  printf 'foreign fixture\n' > orchestrator/.lock/stray
  set +e
  bash orchestrator/orchestrate.sh > "$CASE_ROOT/foreign-lock.log" 2>&1
  foreign_lock_rc=$?
  set -e
  [ "$foreign_lock_rc" = 2 ]
  grep -F 'verwaister Lock enthält Fremdinhalt' "$CASE_ROOT/foreign-lock.log" >/dev/null
  grep -F 'Aufräumen: PID prüfen' "$CASE_ROOT/foreign-lock.log" >/dev/null
  mkdir -p orchestrator/state/M0 orchestrator/state/M1
  touch orchestrator/state/M0/8-done.done orchestrator/state/M1/8-done.done
  bash orchestrator/status.sh '' parked >/dev/null
  jq -e '.milestone.id=="" and .phase=="parked" and .needs_human==true' \
    orchestrator/state/summary.json >/dev/null
)

for event in done parked stale; do
  grep -Fx "$event" "$NOTIFY_LOG" >/dev/null
done
printf 'notify-capture: %s\n' "$(sort -u "$NOTIFY_LOG" | paste -sd, -)"
record_behavior lock-orphan
echo 'T-4 PASS: notify=DONE,PARKED watchdog=STALE double-start=isolated foreign-lock=FATAL status-precedence=parked watchdog-exit=1'
