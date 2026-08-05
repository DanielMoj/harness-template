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
)

for event in done parked stale; do
  grep -Fx "$event" "$NOTIFY_LOG" >/dev/null
done
printf 'notify-capture: %s\n' "$(sort -u "$NOTIFY_LOG" | paste -sd, -)"
echo 'T-4 PASS: notify=DONE,PARKED watchdog=STALE watchdog-exit=1'
