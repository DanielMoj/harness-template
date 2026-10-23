#!/usr/bin/env bash
# T-7: adversarial regressions for territory, logs, secrets, preflight, and deps.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

CASE_ROOT="$(new_case_root)"
trap 'cleanup_case "$CASE_ROOT"' EXIT

run_orchestrator() {
  local repo="$1" log_file="$2"
  shift 2
  set +e
  (
    cd "$repo"
    PATH="$repo/tests/template/fixtures/fake-bin:$PATH" \
      FAKE_NOTIFY_LOG="$CASE_ROOT/notify.log" "$@" bash orchestrator/orchestrate.sh
  ) > "$log_file" 2>&1
  LAST_RC=$?
  set -e
}

HIDDEN_REPO="$CASE_ROOT/hidden/repo"
mkdir -p "$(dirname "$HIDDEN_REPO")"
prepare_orchestrator_case T2 "$HIDDEN_REPO"
cat >> "$HIDDEN_REPO/orchestrator/config.env" <<'EOF'
ACCEPTANCE_HIDDEN_TERRITORY_PROBE=1
ACCEPTANCE_ENV_CAPTURE=1
EOF
printf '%s\n' 'TUNNEL_TOKEN=fixture-tunnel-LEAK' 'OPENAI_API_KEY=sk-fixture-LEAK' \
  > "$HIDDEN_REPO/orchestrator/secrets.env"
chmod 600 "$HIDDEN_REPO/orchestrator/secrets.env"
run_orchestrator "$HIDDEN_REPO" "$CASE_ROOT/hidden.log" \
  env TUNNEL_TOKEN=parent-fixture-LEAK OPENAI_API_KEY=sk-parent-fixture-LEAK
[ "$LAST_RC" = 0 ]
grep -F 'builder verletzt Territorium: orchestrator/.lock/stray' "$CASE_ROOT/hidden.log" >/dev/null
(
  cd "$HIDDEN_REPO"
  test ! -e orchestrator/.lock/stray
  test ! -e reports/evil.txt
  test -f src/model-env.txt
  ! grep -Eq 'TUNNEL_TOKEN|OPENAI_API_KEY|fixture-LEAK' src/model-env.txt
  test "$(find orchestrator/logs -maxdepth 1 -name 'M0-40-build-r1-a*.log' | wc -l)" = 2
  test -n "$(find orchestrator/logs -maxdepth 1 -name 'M0-40-build-r1-a1-*.log' -print -quit)"
  test -n "$(find orchestrator/logs -maxdepth 1 -name 'M0-40-build-r1-a2-*.log' -print -quit)"
)

TAMPER_REPO="$CASE_ROOT/tamper/repo"
mkdir -p "$(dirname "$TAMPER_REPO")"
prepare_orchestrator_case T2 "$TAMPER_REPO"
printf '\nACCEPTANCE_LOG_TAMPER_PROBE=1\n' >> "$TAMPER_REPO/orchestrator/config.env"
run_orchestrator "$TAMPER_REPO" "$CASE_ROOT/tamper.log" env
[ "$LAST_RC" = 0 ]
grep -F 'orchestrator/logs/** (Hash-Manifest)' "$CASE_ROOT/tamper.log" >/dev/null
! grep -Rqs 'FAELSCHUNG durch das Modell' "$TAMPER_REPO/orchestrator/logs"
test "$(find "$TAMPER_REPO/orchestrator/logs" -maxdepth 1 -name 'M0-40-build-r1-a*.log' | wc -l)" = 2

FLAG_REPO="$CASE_ROOT/flag/repo"
mkdir -p "$(dirname "$FLAG_REPO")"
prepare_orchestrator_case T2 "$FLAG_REPO"
sed -i "s#^BUILDER_CMD=.*#BUILDER_CMD='bash tests/template/fake-model.sh builder --fixture-safe \$EXTRA_FLAGS'#" \
  "$FLAG_REPO/orchestrator/config.env"
printf '\nEXTRA_FLAGS=--dangerously-skip-permissions\n' >> "$FLAG_REPO/orchestrator/config.env"
run_orchestrator "$FLAG_REPO" "$CASE_ROOT/flag.log" env
[ "$LAST_RC" = 2 ]
grep -F 'nicht erlaubte $-Referenz' "$CASE_ROOT/flag.log" >/dev/null

# Same pattern with the flag written literally, so the ban list itself is reached.
# Arguments: case name, role variable, role, extra flags, expected FATAL text.
banned_flag_case() {
  local name="$1" role_var="$2" role="$3" flags="$4" expected="$5" repo
  repo="$CASE_ROOT/ban-$name/repo"
  mkdir -p "$(dirname "$repo")"
  prepare_orchestrator_case T2 "$repo"
  sed -i "s#^${role_var}=.*#${role_var}='bash tests/template/fake-model.sh $role --fixture-safe $flags'#" \
    "$repo/orchestrator/config.env"
  if [ "$role_var" = QA_CMD ]; then
    sed -i 's/^QA_ENABLED=0$/QA_ENABLED=1/' "$repo/orchestrator/config.env"
    grep -q '^QA_CMD=' "$repo/orchestrator/config.env" \
      || printf "\nQA_CMD='bash tests/template/fake-model.sh qa --fixture-safe %s'\n" "$flags" \
        >> "$repo/orchestrator/config.env"
  fi
  run_orchestrator "$repo" "$CASE_ROOT/ban-$name.log" env
  [ "$LAST_RC" = 2 ] || { echo "T-7 FAIL: $name rc=$LAST_RC" >&2; return 1; }
  grep -F -- "$expected" "$CASE_ROOT/ban-$name.log" >/dev/null \
    || { echo "T-7 FAIL: $name ohne Meldung '$expected'" >&2; return 1; }
  test ! -e "$repo/orchestrator/state/M0/1-acceptance.done"
}
BYPASS_TEXT='gefährlicher Bypass-/Full-Access-/Auto-Freigabe-Modus in Rollenkommando gefunden'
RESUME_TEXT='Resume-/Session-Flags sind verboten'
banned_flag_case gemini-yolo-eq QA_CMD qa '--approval-mode=yolo' "$BYPASS_TEXT: --approval-mode=yolo"
banned_flag_case gemini-yolo-space BUILDER_CMD builder '--approval-mode yolo' "$BYPASS_TEXT: --approval-mode yolo"
banned_flag_case codex-bypass BUILDER_CMD builder '--dangerously-bypass-approvals-and-sandbox' \
  "$BYPASS_TEXT: dangerously-bypass-approvals-and-sandbox"
banned_flag_case codex-bypass-generic BUILDER_CMD builder '--dangerously-bypass-hook-trust' \
  "$BYPASS_TEXT: dangerously-bypass-hook-trust"
banned_flag_case qwen-auto QA_CMD qa '--approval-mode auto' "$BYPASS_TEXT: --approval-mode auto"
banned_flag_case claude-allow-skip REVIEWER_CMD reviewer '--allow-dangerously-skip-permissions' \
  "$BYPASS_TEXT: dangerously-skip-permissions"
banned_flag_case claude-auto REVIEWER_CMD reviewer '--permission-mode auto' "$BYPASS_TEXT: --permission-mode auto"
banned_flag_case codex-approve-for-me BUILDER_CMD builder '--approve-for-me' "$BYPASS_TEXT: --approve-for-me"
banned_flag_case codex-resume BUILDER_CMD builder 'resume --last' "$RESUME_TEXT; jede Phase ist eine frische Session: resume"
banned_flag_case gemini-session-file QA_CMD qa '--session-file s.json' \
  "$RESUME_TEXT; jede Phase ist eine frische Session: --session-file"

# Positive cases: safe edit modes of Gemini CLI (auto_edit) and Qwen Code (auto-edit)
# pass the ban list, the safe-mode pattern and the strict QA route probe.
allowed_qa_mode_case() {
  local name="$1" mode="$2" repo
  repo="$CASE_ROOT/allow-$name/repo"
  mkdir -p "$(dirname "$repo")"
  prepare_orchestrator_case T2 "$repo"
  sed -i 's/^AUTONOMY_LEVEL=3$/AUTONOMY_LEVEL=0/' "$repo/orchestrator/config.env"
  sed -i 's/^QA_ENABLED=0$/QA_ENABLED=1/' "$repo/orchestrator/config.env"
  cat >> "$repo/orchestrator/config.env" <<EOF
QA_MODEL=fake-qa
QA_CMD='bash tests/template/fake-model.sh qa --fixture-safe --approval-mode $mode'
QA_HELP_CMD='bash tests/template/fake-model.sh --help'
QA_REQUIRED_FLAGS='--fixture-safe'
QA_SAFE_MODE_PATTERN='--approval-mode[ =]auto[-_]edit'
QA_ENV_ALLOWLIST='ACCEPTANCE_SCENARIO'
QA_PROBE_STRICT=1
QA_PROBE_RETRIES=1
QA_PROBE_SLEEP=0
EOF
  run_orchestrator "$repo" "$CASE_ROOT/allow-$name.log" env
  [ "$LAST_RC" = 0 ] || { echo "T-7 FAIL: $name rc=$LAST_RC" >&2; return 1; }
  grep -F 'QA-Routenprobe bestanden (fake-qa); Ausgabe: orchestrator/logs/qa-probe-' \
    "$CASE_ROOT/allow-$name.log" >/dev/null
  grep -Fx OK "$(find "$repo/orchestrator/logs" -maxdepth 1 -name 'qa-probe-*-1.log' -print -quit)" >/dev/null
  test -f "$repo/orchestrator/state/M0/1-acceptance.done"
}
allowed_qa_mode_case gemini-auto-edit auto_edit
allowed_qa_mode_case qwen-auto-edit auto-edit

EMPTY_GUARD_REPO="$CASE_ROOT/empty-guard/repo"
mkdir -p "$(dirname "$EMPTY_GUARD_REPO")"
prepare_orchestrator_case T2 "$EMPTY_GUARD_REPO"
sed -i 's/^BUILDER_SAFE_MODE_PATTERN=.*/BUILDER_SAFE_MODE_PATTERN=/' \
  "$EMPTY_GUARD_REPO/orchestrator/config.env"
run_orchestrator "$EMPTY_GUARD_REPO" "$CASE_ROOT/empty-guard.log" env
[ "$LAST_RC" = 2 ]
grep -F 'BUILDER-SAFE_MODE_PATTERN ist leer' "$CASE_ROOT/empty-guard.log" >/dev/null

GUARDS_OFF_REPO="$CASE_ROOT/guards-off/repo"
mkdir -p "$(dirname "$GUARDS_OFF_REPO")"
prepare_orchestrator_case T2 "$GUARDS_OFF_REPO"
sed -i 's/^AUTONOMY_LEVEL=3$/AUTONOMY_LEVEL=0/' "$GUARDS_OFF_REPO/orchestrator/config.env"
sed -i 's/^ROLE_GUARDS=on$/ROLE_GUARDS=off/' "$GUARDS_OFF_REPO/orchestrator/config.env"
sed -i -E 's/^(BUILDER|REVIEWER)_(REQUIRED_FLAGS|SAFE_MODE_PATTERN)=.*/\1_\2=/' \
  "$GUARDS_OFF_REPO/orchestrator/config.env"
run_orchestrator "$GUARDS_OFF_REPO" "$CASE_ROOT/guards-off.log" env
[ "$LAST_RC" = 0 ]
grep -F 'ROLE_GUARDS=OFF' "$CASE_ROOT/guards-off.log" >/dev/null
jq -e '.role_guards=="off"' "$GUARDS_OFF_REPO/orchestrator/state/summary.json" >/dev/null

MISSING_REPO="$CASE_ROOT/missing-prompt/repo"
mkdir -p "$(dirname "$MISSING_REPO")"
prepare_orchestrator_case T2 "$MISSING_REPO"
rm "$MISSING_REPO/orchestrator/prompts/10-acceptance.md"
run_orchestrator "$MISSING_REPO" "$CASE_ROOT/missing-prompt.log" env
[ "$LAST_RC" = 2 ]
grep -F 'Vertragspfad fehlt: orchestrator/prompts/10-acceptance.md' "$CASE_ROOT/missing-prompt.log" >/dev/null
test ! -e "$MISSING_REPO/orchestrator/state/M0/8-done.done"

CRITERIA_REPO="$CASE_ROOT/criteria/repo"
mkdir -p "$(dirname "$CRITERIA_REPO")"
prepare_orchestrator_case T2 "$CRITERIA_REPO"
jq '.[0].criteriaRef=["K-M0|BAD"]' "$CRITERIA_REPO/orchestrator/milestones.json" \
  > "$CRITERIA_REPO/orchestrator/.milestones.tmp"
mv "$CRITERIA_REPO/orchestrator/.milestones.tmp" "$CRITERIA_REPO/orchestrator/milestones.json"
run_orchestrator "$CRITERIA_REPO" "$CASE_ROOT/criteria.log" env
[ "$LAST_RC" = 2 ]
grep -F 'Meilensteinmanifest verletzt' "$CASE_ROOT/criteria.log" >/dev/null

CYCLE_REPO="$CASE_ROOT/cycle/repo"
mkdir -p "$(dirname "$CYCLE_REPO")"
prepare_orchestrator_case T2 "$CYCLE_REPO"
cp "$CYCLE_REPO/tests/template/fixtures/milestones-cycle.json" \
  "$CYCLE_REPO/orchestrator/milestones.json"
run_orchestrator "$CYCLE_REPO" "$CASE_ROOT/cycle.log" env
[ "$LAST_RC" = 2 ]
grep -F 'Meilensteinmanifest enthält einen deps-Zyklus' "$CASE_ROOT/cycle.log" >/dev/null
grep -Fx fatal "$CASE_ROOT/notify.log" >/dev/null

QA_BOUND_REPO="$CASE_ROOT/qa-bound/repo"
mkdir -p "$(dirname "$QA_BOUND_REPO")"
prepare_orchestrator_case T2 "$QA_BOUND_REPO"
sed -i 's/^QA_REQUIRED_FROM=$/QA_REQUIRED_FROM=UNKNOWN/' "$QA_BOUND_REPO/orchestrator/config.env"
run_orchestrator "$QA_BOUND_REPO" "$CASE_ROOT/qa-bound.log" env
[ "$LAST_RC" = 2 ]
grep -F 'QA_REQUIRED_FROM ist keine Meilenstein-ID des Manifests: UNKNOWN' "$CASE_ROOT/qa-bound.log" >/dev/null

DEPS_REPO="$CASE_ROOT/deps/repo"
mkdir -p "$(dirname "$DEPS_REPO")"
prepare_orchestrator_case T2 "$DEPS_REPO"
set +e
(
  cd "$DEPS_REPO"
  PATH="$DEPS_REPO/tests/template/fixtures/fake-bin:$PATH" \
    FAKE_NOTIFY_LOG="$CASE_ROOT/deps-notify.log" bash orchestrator/orchestrate.sh M1
) > "$CASE_ROOT/deps.log" 2>&1
deps_rc=$?
set -e
[ "$deps_rc" = 2 ]
grep -F 'offene Abhängigkeiten: M0' "$CASE_ROOT/deps.log" >/dev/null
jq -e '.phase=="fatal" and .exit==2 and .needs_human==true' \
  "$DEPS_REPO/orchestrator/state/summary.json" >/dev/null

IDENT_REPO="$CASE_ROOT/identity/repo"
mkdir -p "$(dirname "$IDENT_REPO")" "$CASE_ROOT/identity/home"
prepare_orchestrator_case T2 "$IDENT_REPO"
(
  cd "$IDENT_REPO"
  git config --unset user.name
  git config --unset user.email
)
run_orchestrator "$IDENT_REPO" "$CASE_ROOT/identity.log" \
  env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null HOME="$CASE_ROOT/identity/home"
[ "$LAST_RC" = 2 ]
grep -F 'git user.name fehlt' "$CASE_ROOT/identity.log" >/dev/null
test ! -e "$IDENT_REPO/orchestrator/state/M0/8-done.done"

BOOTSTRAP_REPO="$CASE_ROOT/bootstrap-identity/repo"
mkdir -p "$(dirname "$BOOTSTRAP_REPO")" "$CASE_ROOT/bootstrap-identity/home"
materialize_tree "$BOOTSTRAP_REPO"
init_fixture_repo "$BOOTSTRAP_REPO"
(
  cd "$BOOTSTRAP_REPO"
  git config --unset user.name
  git config --unset user.email
)
set +e
(
  cd "$BOOTSTRAP_REPO"
  env -i PATH="$PATH" HOME="$CASE_ROOT/bootstrap-identity/home" LANG="${LANG:-C.UTF-8}" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash bootstrap.sh --non-interactive --no-start
) > "$CASE_ROOT/bootstrap-identity.log" 2>&1
bootstrap_identity_rc=$?
set -e
[ "$bootstrap_identity_rc" = 2 ]
grep -F 'git user.name fehlt' "$CASE_ROOT/bootstrap-identity.log" >/dev/null

PRESET_REPO="$CASE_ROOT/preset/repo"
mkdir -p "$(dirname "$PRESET_REPO")"
prepare_orchestrator_case T2 "$PRESET_REPO"
cat >> "$PRESET_REPO/orchestrator/config.env" <<'EOF'
ACCEPTANCE_REVIEWER_EXTRA_PATH_PROBE=1
REVIEWER_EXTRA_PATHS_REGEX='^stilbibel\.md$'
EOF
sed -i 's/^AUTONOMY_LEVEL=3$/AUTONOMY_LEVEL=0/' "$PRESET_REPO/orchestrator/config.env"
run_orchestrator "$PRESET_REPO" "$CASE_ROOT/preset.log" env
[ "$LAST_RC" = 0 ]
test -s "$PRESET_REPO/stilbibel.md"
! grep -F 'verletzt Territorium: stilbibel.md' "$CASE_ROOT/preset.log" >/dev/null

record_behavior territory-enforcement
record_behavior flag-ban
record_behavior sandbox-guard
echo 'T-7 evidence rollback: lock-stray=absent report-evil=absent model-secrets=absent attempt-logs=2'
echo 'T-7 evidence preset-hook: reviewer stilbibel.md accepted'
for evidence_file in \
  hidden.log tamper.log flag.log \
  ban-gemini-yolo-eq.log ban-gemini-yolo-space.log ban-codex-bypass.log ban-codex-bypass-generic.log \
  ban-qwen-auto.log ban-claude-allow-skip.log ban-claude-auto.log ban-codex-approve-for-me.log \
  ban-codex-resume.log ban-gemini-session-file.log \
  empty-guard.log guards-off.log \
  missing-prompt.log criteria.log cycle.log qa-bound.log deps.log \
  identity.log bootstrap-identity.log; do
  printf 'T-7 evidence %s: ' "$evidence_file"
  grep -m1 -E 'verletzt Territorium|FATAL:|ROLE_GUARDS=OFF' "$CASE_ROOT/$evidence_file"
done
for evidence_file in allow-gemini-auto-edit.log allow-qwen-auto-edit.log; do
  printf 'T-7 evidence %s: ' "$evidence_file"
  grep -m1 -F 'QA-Routenprobe bestanden' "$CASE_ROOT/$evidence_file"
done
echo 'T-7 PASS: hidden-territory=rollback logs=hash-protected env=allowlisted flags=expanded ban-list=yolo,bypass,auto,resume safe-edit-modes=auto_edit,auto-edit guards=explicit preflight=contracts manifest=cycle qa-bound=validated deps=FATAL identity=FATAL preset-hooks=accepted'
