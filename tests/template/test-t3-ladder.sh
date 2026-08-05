#!/usr/bin/env bash
# T-3: permanentes Rot erreicht Rebuild r4, Arbiter HUMAN, Park und Exit 3.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

CASE_ROOT="$(new_case_root)"
trap 'cleanup_case "$CASE_ROOT"' EXIT
REPO="$CASE_ROOT/repo"
NOTIFY_LOG="$CASE_ROOT/notify.log"
RUN_LOG="$CASE_ROOT/t3-run.log"
prepare_orchestrator_case T3 "$REPO"

echo '[T-3] orchestrator permanent-fail run'
set +e
(
  cd "$REPO"
  PATH="$REPO/tests/template/fixtures/fake-bin:$PATH" \
    FAKE_NOTIFY_LOG="$NOTIFY_LOG" bash orchestrator/orchestrate.sh
) 2>&1 | tee "$RUN_LOG"
RC=${PIPESTATUS[0]}
set -e
[ "$RC" = 3 ] || { echo "T-3 FAIL: expected exit 3, got $RC" >&2; exit 1; }

(
  cd "$REPO"
  test -f orchestrator/state/M0/5c-rebuild.done
  test -f orchestrator/state/M0/parked
  test -f orchestrator/ESCALATION-M0.md
  test -f orchestrator/ESCALATION.md
  test "$(cat orchestrator/state/M0/round)" = 4
  jq -e '.verdict=="HUMAN" and .phase=="code" and .round==4' \
    orchestrator/handoff/M0/verdict-arbiter.json >/dev/null
  jq -e '.contract==1 and .phase=="parked" and .needs_human==true and .exit==3 and (.parked|index("M0"))!=null' \
    orchestrator/state/summary.json >/dev/null
  git log --format=%s | grep -F 'orch(M0): reset builder territory for rebuild'
  git log --format=%s | grep -F 'orch(M0): reviewer 70-arbiter r4'
  jq -c '{contract,project,phase,round,needs_human,reason,parked,exit}' orchestrator/state/summary.json
)
grep -F 'REBUILD M0' "$RUN_LOG" >/dev/null
grep -F 'PARKED M0' "$RUN_LOG" >/dev/null
grep -Fx parked "$NOTIFY_LOG" >/dev/null
echo 'T-3 PASS: rebuild=r4 arbiter=HUMAN parked=M0 escalation=present exit=3'
