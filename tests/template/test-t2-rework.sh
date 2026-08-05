#!/usr/bin/env bash
# T-2: zwei Mini-Meilensteine, zwei Gates, rot -> Rework -> gruen.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

CASE_ROOT="$(new_case_root)"
trap 'cleanup_case "$CASE_ROOT"' EXIT
REPO="$CASE_ROOT/repo"
NOTIFY_LOG="$CASE_ROOT/notify.log"
RUN_LOG="$CASE_ROOT/t2-run.log"
prepare_orchestrator_case T2 "$REPO"

echo '[T-2] orchestrator run'
set +e
(
  cd "$REPO"
  PATH="$REPO/tests/template/fixtures/fake-bin:$PATH" \
    FAKE_NOTIFY_LOG="$NOTIFY_LOG" bash orchestrator/orchestrate.sh
) 2>&1 | tee "$RUN_LOG"
RC=${PIPESTATUS[0]}
set -e
[ "$RC" = 0 ] || { echo "T-2 FAIL: exit=$RC" >&2; exit 1; }

(
  cd "$REPO"
  for ms in M0 M1; do
    test -f "orchestrator/state/$ms/8-done.done"
    git rev-parse -q --verify "refs/tags/plan/$ms" >/dev/null
    git rev-parse -q --verify "refs/tags/done/$ms" >/dev/null
    jq -e '.result=="pass" and .gates.product=="pass" and .gates.behavior=="pass"' \
      "orchestrator/state/$ms/gates.json" >/dev/null
  done
  git log --format=%s | grep -F 'orch(M0): gates r1 (rc=1)'
  git log --format=%s | grep -F 'orch(M0): builder 60-rework r2'
  test ! -e src/reviewer-territory-violation.txt
  test "$(git tag --list 'done/M*' | wc -l)" = 2
  jq -c '{contract,project,phase,milestone,gates,parked,exit}' orchestrator/state/summary.json
)
[ "$(grep -c '^done$' "$NOTIFY_LOG")" = 2 ]
grep -F 'gate behavior: fail' "$RUN_LOG" >/dev/null
grep -F 'gate behavior: pass' "$RUN_LOG" >/dev/null
grep -F 'Transportfehler builder/20-plan' "$RUN_LOG" >/dev/null
grep -F 'reviewer verletzt Territorium' "$RUN_LOG" >/dev/null
echo 'T-2 PASS: milestones=2 gates=2 red=1 rework=1 transport-retry=1 territory-retry=1 done=2 exit=0'
