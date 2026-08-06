#!/usr/bin/env bash
# T-8: infrastructure-error semantics and executable example-gate fixtures.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

CASE_ROOT="$(new_case_root)"
trap 'cleanup_case "$CASE_ROOT"' EXIT

ERROR_REPO="$CASE_ROOT/error-loop/repo"
mkdir -p "$(dirname "$ERROR_REPO")"
prepare_orchestrator_case TERROR "$ERROR_REPO"
set +e
(
  cd "$ERROR_REPO"
  PATH="$ERROR_REPO/tests/template/fixtures/fake-bin:$PATH" \
    FAKE_NOTIFY_LOG="$CASE_ROOT/error-notify.log" bash orchestrator/orchestrate.sh
) > "$CASE_ROOT/error-loop.log" 2>&1
error_loop_rc=$?
set -e
[ "$error_loop_rc" = 3 ]
(
  cd "$ERROR_REPO"
  test -f orchestrator/state/M0/parked
  grep -F 'Infrastruktur (Gate error)' orchestrator/state/M0/parked >/dev/null
  test ! -e orchestrator/state/M0/round
  test ! -e orchestrator/state/M0/5c-rebuild.done
  ! find orchestrator/state/M0 -maxdepth 1 -name 'rework-r*.done' -print -quit | grep -q .
  for attempt in 0 1 2; do
    test -f "orchestrator/state/M0/gates-r1-infra$attempt.done"
  done
  jq -e '.phase=="parked" and .round==1 and .needs_human==true and .exit==3' \
    orchestrator/state/summary.json >/dev/null
)
[ "$(grep -c 'Infrastruktur-Wiederholung' "$CASE_ROOT/error-loop.log")" = 2 ]
! grep -Eq '60-rework|62-rebuild|REBUILD M0' "$CASE_ROOT/error-loop.log"

MUT_REPO="$CASE_ROOT/mutgate/repo"
materialize_tree "$MUT_REPO"
mkdir -p "$MUT_REPO/src"
printf 'export const value = 1;\n' > "$MUT_REPO/src/core.js"
init_fixture_repo "$MUT_REPO"
MUT_BASE="$(git -C "$MUT_REPO" rev-parse HEAD)"
printf 'export const changed = 2;\n' >> "$MUT_REPO/src/core.js"
mkdir -p "$MUT_REPO/orchestrator/state/M0" "$MUT_REPO/orchestrator/handoff/M0"
cat > "$MUT_REPO/orchestrator/config.env" <<'EOF'
MUT_SCOPE_REGEX='^src/.*\.js$'
MUT_REPORT=reports/mutation/mutation.json
MUT_SCORE_MIN=65
MUT_SCORE_FLOOR=50
MUT_RATCHET_TOL=2
MUT_CMD='mkdir -p reports/mutation && cp tests/template/fixtures/mutgate/pass.json reports/mutation/mutation.json'
EOF
(
  cd "$MUT_REPO"
  ORCH="$MUT_REPO/orchestrator" REPO_ROOT="$MUT_REPO" MILESTONE=M0 ROUND=1 BASE_SHA="$MUT_BASE" \
    bash orchestrator/gates.d/86-mutgate.sh.example
) > "$CASE_ROOT/mut-pass.log" 2>&1
grep -F 'mutgate: pass' "$CASE_ROOT/mut-pass.log" >/dev/null

printf '90\n' > "$MUT_REPO/orchestrator/state/mut-baseline"
sed -i 's#pass.json#ratchet-fail.json#' "$MUT_REPO/orchestrator/config.env"
set +e
(
  cd "$MUT_REPO"
  ORCH="$MUT_REPO/orchestrator" REPO_ROOT="$MUT_REPO" MILESTONE=M0 ROUND=1 BASE_SHA="$MUT_BASE" \
    bash orchestrator/gates.d/86-mutgate.sh.example
) > "$CASE_ROOT/mut-ratchet.log" 2>&1
mut_ratchet_rc=$?
set -e
[ "$mut_ratchet_rc" = 1 ]
grep -F 'mutgate: fail' "$CASE_ROOT/mut-ratchet.log" >/dev/null

sed -i "s#^MUT_CMD=.*#MUT_CMD='exit 127'#" "$MUT_REPO/orchestrator/config.env"
set +e
(
  cd "$MUT_REPO"
  ORCH="$MUT_REPO/orchestrator" REPO_ROOT="$MUT_REPO" MILESTONE=M0 ROUND=1 BASE_SHA="$MUT_BASE" \
    bash orchestrator/gates.d/86-mutgate.sh.example
) > "$CASE_ROOT/mut-error.log" 2>&1
mut_error_rc=$?
set -e
[ "$mut_error_rc" = 2 ]
grep -F 'Werkzeug starb vor der Mutation' "$CASE_ROOT/mut-error.log" >/dev/null

TRACE_REPO="$CASE_ROOT/trace/repo"
materialize_tree "$TRACE_REPO"
mkdir -p "$TRACE_REPO/docs" "$TRACE_REPO/tests/acceptance" \
  "$TRACE_REPO/orchestrator/handoff/M0"
printf '%s\n' '- K-TRACE-1: The fixture trace is exact.' > "$TRACE_REPO/docs/trace-spec.md"
cat > "$TRACE_REPO/orchestrator/milestones.json" <<'EOF'
[{"id":"M0","title":"Trace fixture","criteriaRef":["K-TRACE-1"],"deps":[],"effort":"low"}]
EOF
cat > "$TRACE_REPO/orchestrator/handoff/M0/CRITERIA.json" <<'EOF'
{"criteria":[{"id":"K-TRACE-1","quote":"- K-TRACE-1: The fixture trace is exact.","source":"docs/trace-spec.md"}],"open":[]}
EOF
printf '%s\n' '# K-TRACE-1' 'test -s docs/trace-spec.md' > "$TRACE_REPO/tests/acceptance/trace.sh"
init_fixture_repo "$TRACE_REPO"
TRACE_BASE="$(git -C "$TRACE_REPO" rev-parse HEAD)"
(
  cd "$TRACE_REPO"
  ORCH="$TRACE_REPO/orchestrator" REPO_ROOT="$TRACE_REPO" MILESTONE=M0 ROUND=1 BASE_SHA="$TRACE_BASE" \
    bash orchestrator/gates.d/70-trace.sh.example
) > "$CASE_ROOT/trace.log" 2>&1
grep -F 'trace: alle Kriterien sind wörtlich und beidseitig verknüpft' "$CASE_ROOT/trace.log" >/dev/null

GOLDEN_REPO="$CASE_ROOT/golden/repo"
materialize_tree "$GOLDEN_REPO"
mkdir -p "$GOLDEN_REPO/tests/golden"
printf 'old\n' > "$GOLDEN_REPO/tests/golden/value.txt"
init_fixture_repo "$GOLDEN_REPO"
GOLDEN_BASE="$(git -C "$GOLDEN_REPO" rev-parse HEAD)"
printf 'new\n' > "$GOLDEN_REPO/tests/golden/value.txt"
set +e
(
  cd "$GOLDEN_REPO"
  ORCH="$GOLDEN_REPO/orchestrator" REPO_ROOT="$GOLDEN_REPO" MILESTONE=M0 ROUND=1 BASE_SHA="$GOLDEN_BASE" \
    bash orchestrator/gates.d/87-golden-adr.sh.example
) > "$CASE_ROOT/golden-fail.log" 2>&1
golden_fail_rc=$?
set -e
[ "$golden_fail_rc" = 1 ]
mkdir -p "$GOLDEN_REPO/docs/decisions"
printf '# ADR fixture\n' > "$GOLDEN_REPO/docs/decisions/ADR-fixture.md"
git -C "$GOLDEN_REPO" add docs/decisions/ADR-fixture.md
(
  cd "$GOLDEN_REPO"
  ORCH="$GOLDEN_REPO/orchestrator" REPO_ROOT="$GOLDEN_REPO" MILESTONE=M0 ROUND=1 BASE_SHA="$GOLDEN_BASE" \
    bash orchestrator/gates.d/87-golden-adr.sh.example
) > "$CASE_ROOT/golden-pass.log" 2>&1
grep -F 'Änderung und ADR liegen im selben Meilenstein' "$CASE_ROOT/golden-pass.log" >/dev/null

RC5_REPO="$CASE_ROOT/rc5/repo"
materialize_tree "$RC5_REPO"
cat > "$RC5_REPO/orchestrator/gates.d/10-rc5.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$ORCH/gates.d/_lib.sh"
gate_load_config
gate_run_configured TEST_CMD rc5
EOF
chmod +x "$RC5_REPO/orchestrator/gates.d/10-rc5.sh"
printf "TEST_CMD='exit 5'\n" > "$RC5_REPO/orchestrator/config.env"
init_fixture_repo "$RC5_REPO"
set +e
(cd "$RC5_REPO" && ROUND=1 bash orchestrator/verifier.sh M0) > "$CASE_ROOT/rc5.log" 2>&1
rc5_rc=$?
set -e
[ "$rc5_rc" = 1 ]
jq -e '.result=="fail" and .gates.rc5=="fail"' \
  "$RC5_REPO/orchestrator/state/M0/gates.json" >/dev/null

TERRITORY_REPO="$CASE_ROOT/territory-gate/repo"
materialize_tree "$TERRITORY_REPO"
init_fixture_repo "$TERRITORY_REPO"
TERRITORY_BASE="$(git -C "$TERRITORY_REPO" rev-parse HEAD)"
mkdir -p "$TERRITORY_REPO/src" "$TERRITORY_REPO/orchestrator/state/M0"
printf 'phase change\n' > "$TERRITORY_REPO/src/change.txt"
printf '2026-08-06T00:00:00+02:00\tbuilder\t40-build\t1\t%s\n' "$TERRITORY_BASE" \
  > "$TERRITORY_REPO/orchestrator/state/M0/territory-ok"
(
  cd "$TERRITORY_REPO"
  git add -A
  git commit -qm 'fixture: model phase'
)
(
  cd "$TERRITORY_REPO"
  ORCH="$TERRITORY_REPO/orchestrator" REPO_ROOT="$TERRITORY_REPO" MILESTONE=M0 ROUND=1 \
    bash orchestrator/gates.d/82-territory.sh.example
) > "$CASE_ROOT/territory-pass.log" 2>&1
sed -i 's/\t1\t/\t2\t/' "$TERRITORY_REPO/orchestrator/state/M0/territory-ok"
set +e
(
  cd "$TERRITORY_REPO"
  ORCH="$TERRITORY_REPO/orchestrator" REPO_ROOT="$TERRITORY_REPO" MILESTONE=M0 ROUND=1 \
    bash orchestrator/gates.d/82-territory.sh.example
) > "$CASE_ROOT/territory-stale.log" 2>&1
territory_stale_rc=$?
set -e
[ "$territory_stale_rc" = 1 ]

printf 'T-8 evidence gate-error: '
grep -m1 -F 'Infrastruktur-Wiederholung 1/2' "$CASE_ROOT/error-loop.log"
printf 'T-8 evidence gate-park: '
grep -m1 -F 'Infrastruktur (Gate error)' "$CASE_ROOT/error-loop.log"
printf 'T-8 evidence mut-pass: '; tail -n 1 "$CASE_ROOT/mut-pass.log"
printf 'T-8 evidence mut-ratchet: '; tail -n 1 "$CASE_ROOT/mut-ratchet.log"
printf 'T-8 evidence mut-error: '; tail -n 1 "$CASE_ROOT/mut-error.log"
printf 'T-8 evidence trace: '; tail -n 1 "$CASE_ROOT/trace.log"
printf 'T-8 evidence golden-fail: '; tail -n 1 "$CASE_ROOT/golden-fail.log"
printf 'T-8 evidence golden-pass: '; tail -n 1 "$CASE_ROOT/golden-pass.log"
printf 'T-8 evidence rc5: '; grep -m1 -F 'gate rc5: fail' "$CASE_ROOT/rc5.log"
printf 'T-8 evidence territory-stale: '; tail -n 1 "$CASE_ROOT/territory-stale.log"
echo 'T-8 PASS: gate-error=2-retries-no-round rc5=fail mutgate=pass,ratchet-fail,error trace=pass golden-adr=fail,pass territory-marker=current'
