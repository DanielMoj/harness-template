#!/usr/bin/env bash
# T-6: active QA, QA parking, digit-free milestone IDs, and level-0 progress.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

CASE_ROOT="$(new_case_root)"
trap 'cleanup_case "$CASE_ROOT"' EXIT

ACTIVE_REPO="$CASE_ROOT/active/repo"
mkdir -p "$(dirname "$ACTIVE_REPO")"
prepare_orchestrator_case T6 "$ACTIVE_REPO"
set +e
(
  cd "$ACTIVE_REPO"
  PATH="$ACTIVE_REPO/tests/template/fixtures/fake-bin:$PATH" \
    FAKE_NOTIFY_LOG="$CASE_ROOT/active-notify.log" bash orchestrator/orchestrate.sh
) > "$CASE_ROOT/active.log" 2>&1
active_rc=$?
set -e
[ "$active_rc" = 0 ]
(
  cd "$ACTIVE_REPO"
  for ms in setup kapitel-eins; do
    test -f "orchestrator/state/$ms/5b-qa.done"
    test -f "orchestrator/state/$ms/qa-r1.done"
    test -x "tests/e2e/$ms-qa.sh"
    test -s "orchestrator/handoff/$ms/QA.md"
    test -f "orchestrator/state/$ms/8-done.done"
  done
)

PARK_REPO="$CASE_ROOT/park/repo"
mkdir -p "$(dirname "$PARK_REPO")"
prepare_orchestrator_case T6 "$PARK_REPO"
sed -i 's/^QA_ENABLED=1$/QA_ENABLED=0/' "$PARK_REPO/orchestrator/config.env"
set +e
(
  cd "$PARK_REPO"
  PATH="$PARK_REPO/tests/template/fixtures/fake-bin:$PATH" \
    FAKE_NOTIFY_LOG="$CASE_ROOT/park-notify.log" bash orchestrator/orchestrate.sh
) > "$CASE_ROOT/park.log" 2>&1
park_rc=$?
set -e
[ "$park_rc" = 3 ]
(
  cd "$PARK_REPO"
  test -f orchestrator/state/setup/parked
  test ! -f orchestrator/state/setup/round
  test ! -e orchestrator/state/setup/5b-qa.done
  ! find orchestrator/state/setup -maxdepth 1 -name 'rework-r*.done' -print -quit | grep -q .
  jq -e '.phase=="parked" and .needs_human==true and .exit==3' \
    orchestrator/state/summary.json >/dev/null
)

PROBE_REPO="$CASE_ROOT/probe-untrusted/repo"
mkdir -p "$(dirname "$PROBE_REPO")"
prepare_orchestrator_case T6 "$PROBE_REPO"
sed -i 's/^QA_PROBE_STRICT=0$/QA_PROBE_STRICT=1/' "$PROBE_REPO/orchestrator/config.env"
sed -i "s/^QA_ENV_ALLOWLIST=.*/QA_ENV_ALLOWLIST='ACCEPTANCE_SCENARIO ACCEPTANCE_QA_PROBE'/" \
  "$PROBE_REPO/orchestrator/config.env"
printf '%s\n' ACCEPTANCE_QA_PROBE=untrusted QA_PROBE_RETRIES=1 QA_PROBE_SLEEP=0 \
  >> "$PROBE_REPO/orchestrator/config.env"
set +e
(
  cd "$PROBE_REPO"
  PATH="$PROBE_REPO/tests/template/fixtures/fake-bin:$PATH" \
    FAKE_NOTIFY_LOG="$CASE_ROOT/probe-notify.log" bash orchestrator/orchestrate.sh
) > "$CASE_ROOT/probe-untrusted.log" 2>&1
probe_rc=$?
set -e
[ "$probe_rc" = 2 ]
grep -F 'QA-Routenprobe strict fehlgeschlagen' "$CASE_ROOT/probe-untrusted.log" >/dev/null
grep -F 'WARN: QA-Routenprobe 1/1 fehlgeschlagen (rc=41); Ausgabe: orchestrator/logs/qa-probe-' \
  "$CASE_ROOT/probe-untrusted.log" >/dev/null
PROBE_LOG="$(find "$PROBE_REPO/orchestrator/logs" -maxdepth 1 -name 'qa-probe-*-1.log' -print -quit)"
grep -F 'Approval mode overridden to "default" because the current folder is not trusted.' \
  "$PROBE_LOG" >/dev/null
test ! -e "$PROBE_REPO/orchestrator/state/setup/1-acceptance.done"

LEVEL0_REPO="$CASE_ROOT/level0/repo"
mkdir -p "$(dirname "$LEVEL0_REPO")"
prepare_orchestrator_case T6 "$LEVEL0_REPO"
sed -i 's/^AUTONOMY_LEVEL=3$/AUTONOMY_LEVEL=0/' "$LEVEL0_REPO/orchestrator/config.env"
sed -i 's/^QA_ENABLED=1$/QA_ENABLED=0/' "$LEVEL0_REPO/orchestrator/config.env"
sed -i 's/^QA_REQUIRED_FROM=setup$/QA_REQUIRED_FROM=/' "$LEVEL0_REPO/orchestrator/config.env"
PHASES_FILE="$CASE_ROOT/level0-phases.txt"
: > "$PHASES_FILE"
for invocation in 1 2 3 4 5 6 7 8; do
  (
    cd "$LEVEL0_REPO"
    PATH="$LEVEL0_REPO/tests/template/fixtures/fake-bin:$PATH" \
      FAKE_NOTIFY_LOG="$CASE_ROOT/level0-notify.log" bash orchestrator/orchestrate.sh setup
  ) > "$CASE_ROOT/level0-$invocation.log" 2>&1
  jq -r '.phase' "$LEVEL0_REPO/orchestrator/state/summary.json" >> "$PHASES_FILE"
done
[ "$(sort -u "$PHASES_FILE" | wc -l)" = 8 ]
diff -u <(printf '%s\n' 10-acceptance 20-plan 30-plan-review 30-plan-approved 40-build gates 50-code-review done) \
  "$PHASES_FILE"
(
  cd "$LEVEL0_REPO"
  test -f orchestrator/state/setup/plan-r1-planned.done
  test -f orchestrator/state/setup/plan-r1-reviewed.done
  test -f orchestrator/state/setup/gates-r1-infra0.done
  test -f orchestrator/state/setup/code-review-r1-infra0.done
  test -f orchestrator/state/setup/8-done.done
)

record_behavior qa-park
printf 'T-6 evidence: '
grep -m1 -F 'QA-Route inaktiv' "$CASE_ROOT/park.log"
printf 'T-6 phases: %s\n' "$(paste -sd, "$PHASES_FILE")"
printf 'T-6 evidence probe: %s\n' "$(grep -m1 -F 'Approval mode overridden' "$PROBE_LOG")"
echo 'T-6 PASS: qa=active qa-park=pre-round qa-probe=logged,strict-FATAL autonomy0=8-distinct-phases digit-free-ids=2'
