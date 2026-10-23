#!/usr/bin/env bash
# T-10: Preset r-paket von Anfang bis Ende. Das Harness wird mit tools/install-into.sh in ein
# Fixture-Paket eingesetzt, M0 läuft mit den Modellattrappen und den R-Gates des Presets
# (Konfigurationszeilen und toolchain.json unverändert aus PRESET.md), danach prüft ein echter
# muttest-Lauf den Adapter gegen 86-mutgate. Ohne R endet der Test mit "übersprungen: R fehlt"
# und Exit 77, nie mit PASS.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if ! command -v Rscript >/dev/null 2>&1; then
  echo 'T-10 übersprungen: R fehlt'
  exit 77
fi
missing_r="$(Rscript -e 'p <- c("testthat", "pkgload"); cat(p[!vapply(p, requireNamespace, logical(1), quietly = TRUE)])' 2>/dev/null || echo Rscript-defekt)"
if [ -n "$missing_r" ]; then
  echo "T-10 übersprungen: R-Pakete fehlen: $missing_r"
  exit 77
fi

CASE_ROOT="$(new_case_root)"
trap 'cleanup_case "$CASE_ROOT"' EXIT

TEMPLATE="$CASE_ROOT/template"
materialize_tree "$TEMPLATE"
init_fixture_repo "$TEMPLATE"
FIXTURE="$TEMPLATE/tests/template/fixtures/r-paket"
PRESET="$TEMPLATE/projektierung/presets/r-paket/PRESET.md"
FAKE="$TEMPLATE/tests/template/fake-model.sh"

preset_block() {
  # Erster Codeblock nach dem Marker <!-- preset-test: NAME --> in PRESET.md.
  awk -v marker="<!-- preset-test: $1 -->" '
    $0 == marker { found = 1; next }
    found && /^```/ { if (inside) exit; inside = 1; next }
    inside { print }
  ' "$PRESET"
}

# Bestehendes Paket ohne Abnahmetests; den Abnahmetest schreibt der Reviewer in ACCEPTANCE.
PKG="$CASE_ROOT/paket"
mkdir -p "$PKG"
cp -a "$FIXTURE/." "$PKG/"
rm -rf "$PKG/tests/acceptance" "$PKG/spec.md"
init_fixture_repo "$PKG"
git -C "$PKG" config core.filemode false
INITIAL="$(git -C "$PKG" rev-parse HEAD)"

bash "$TEMPLATE/tools/install-into.sh" "$PKG" > "$CASE_ROOT/install.log" 2>&1
git -C "$PKG" commit -qm 'harness: einsetzen'

{
  cat <<EOF
PROJECT_SLUG=acceptance-tr
AUTONOMY_LEVEL=3
ACCEPTANCE_SCENARIO=TR
BUILDER_MODEL=fake-builder
BUILDER_CMD='bash $FAKE builder --fixture-safe'
BUILDER_HELP_CMD='bash $FAKE --help'
BUILDER_REQUIRED_FLAGS='--fixture-safe'
BUILDER_SAFE_MODE_PATTERN='--fixture-safe'
BUILDER_ENV_ALLOWLIST='ACCEPTANCE_SCENARIO'
REVIEWER_MODEL=fake-reviewer
REVIEWER_CMD='bash $FAKE reviewer --fixture-safe'
REVIEWER_HELP_CMD='bash $FAKE --help'
REVIEWER_REQUIRED_FLAGS='--fixture-safe'
REVIEWER_SAFE_MODE_PATTERN='--fixture-safe'
REVIEWER_ENV_ALLOWLIST='ACCEPTANCE_SCENARIO'
QA_ENABLED=0
QA_REQUIRED_FROM=
PHASE_TIMEOUT=120
MAX_ROUNDS_PLAN=2
MAX_ROUNDS_REWORK=2
RETRY_MAX=1
RETRY_SLEEP=0
GATE_ERROR_RETRIES=1
MAX_MS_PER_RUN=1
LADDER_ENABLED=0
NOTIFY_ENABLED=0
PUSH_REMOTE=0
BOOTSTRAP_AUTO=0
ROLE_GUARDS=on
EOF
  preset_block config-env
} > "$PKG/orchestrator/config.env"
grep -Fx "REBUILD_PATHS='R tests/testthat'" "$PKG/orchestrator/config.env" >/dev/null
grep -Fx "MUT_SCOPE_REGEX='^R/.*\\.R\$'" "$PKG/orchestrator/config.env" >/dev/null
preset_block toolchain > "$PKG/toolchain.json"
jq -e '.runtimes[0].command=="Rscript" and .manifests[0].path=="DESCRIPTION"' "$PKG/toolchain.json" >/dev/null
cat > "$PKG/orchestrator/milestones.json" <<'EOF'
[
  {
    "id": "M0",
    "title": "Toolchain, Preset und Gates auf dem vorhandenen Paket",
    "criteriaRef": ["K-M0-1", "K-M0-2", "K-M0-3"],
    "deps": [],
    "effort": "low"
  }
]
EOF
mkdir -p "$PKG/docs"
cp "$FIXTURE/spec.md" "$PKG/docs/99-acceptance-fixture.md"
for gate in 10-deps 20-lint 30-tests 70-trace 82-territory 86-mutgate 87-golden-adr; do
  cp "$PKG/orchestrator/gates.d/$gate.sh.example" "$PKG/orchestrator/gates.d/$gate.sh"
  chmod +x "$PKG/orchestrator/gates.d/$gate.sh"
  git -C "$PKG" add --chmod=+x "orchestrator/gates.d/$gate.sh"
done
git -C "$PKG" add -A
git -C "$PKG" commit -qm 'betreiber: Spec, Manifest und Gates'
git -C "$PKG" ls-files -s 'orchestrator/gates.d/[0-9][0-9]-*.sh' > "$CASE_ROOT/gate-modes.txt"
test "$(grep -c '^100755 ' "$CASE_ROOT/gate-modes.txt")" = 7
(cd "$PKG" && bash orchestrator/lib/toolchain.sh verify) > "$CASE_ROOT/toolchain.log" 2>&1

set +e
(
  cd "$PKG"
  bash orchestrator/orchestrate.sh M0
) > "$CASE_ROOT/run.log" 2>&1
run_rc=$?
set -e
if [ "$run_rc" != 0 ]; then
  tail -n 60 "$CASE_ROOT/run.log" >&2
  for gate_log in "$PKG"/orchestrator/state/M0/gate-*.log; do
    [ -f "$gate_log" ] && { echo "== $gate_log" >&2; tail -n 30 "$gate_log" >&2; }
  done
  echo "T-10 FAIL: orchestrate.sh M0 rc=$run_rc" >&2
  exit 1
fi
(
  cd "$PKG"
  test -f orchestrator/state/M0/8-done.done
  git rev-parse -q --verify refs/tags/done/M0 >/dev/null
  jq -e '.result=="pass" and ([.gates[]] | all(.=="pass"))
    and (.gates | keys) == ["deps","golden-adr","lint","mutgate","territory","tests","trace"]' \
    orchestrator/state/M0/gates.json >/dev/null
  # M0 für ein bestehendes Paket: nichts unter R/ geändert.
  git diff --quiet "$INITIAL" HEAD -- R
  test -f tests/acceptance/test-clamp-acceptance.R
  grep -F 'r-deps: pass' orchestrator/state/M0/gate-deps.log >/dev/null
  grep -F 'r-tests: tests/acceptance: 1 Testdatei(en)' orchestrator/state/M0/gate-tests.log >/dev/null
  grep -F 'r-tests: pass — 4 Tests in tests/testthat, tests/acceptance' orchestrator/state/M0/gate-tests.log >/dev/null
  grep -F 'r-check: pass — Status:' orchestrator/state/M0/gate-lint.log >/dev/null
  # Vollständige .Rbuildignore: R CMD check sieht keine Harness-Dateien.
  ! grep -E 'Non-standard files?/director|hidden files and directories \.\.\. NOTE' orchestrator/state/M0/gate-lint.log
  grep -F 'mutgate: pass (kein geänderter Mutations-Scope)' orchestrator/state/M0/gate-mutgate.log >/dev/null
  # Wie im PREFLIGHT toleriert: der Statusheartbeat nach dem letzten Commit.
  test -z "$(git status --porcelain | grep -vE '^ M (STATUS\.md|orchestrator/state/summary\.json)$' || true)"
)

MUTATION=übersprungen
if Rscript -e 'quit(status = if (requireNamespace("muttest", quietly = TRUE)) 0 else 1)' >/dev/null 2>&1; then
  MUT_BASE="$(git -C "$PKG" rev-parse HEAD)"
  sed -i '1a # Changed for the mutation adapter self-test; behaviour is unchanged.' "$PKG/R/clamp.R"
  git -C "$PKG" commit -qam 'fixture: R/clamp.R geändert'
  run_mutgate() {
    local minimum="$1" log_file="$2" rc
    set +e
    (
      cd "$PKG"
      MUT_SCORE_MIN="$minimum" ORCH="$PKG/orchestrator" REPO_ROOT="$PKG" MILESTONE=M1 ROUND=1 \
        BASE_SHA="$MUT_BASE" bash orchestrator/gates.d/86-mutgate.sh
    ) > "$log_file" 2>&1
    rc=$?
    set -e
    return "$rc"
  }
  if run_mutgate 90 "$CASE_ROOT/mut-strict.log"; then strict_rc=0; else strict_rc=$?; fi
  [ "$strict_rc" = 1 ] || { cat "$CASE_ROOT/mut-strict.log" >&2; echo "T-10 FAIL: mutgate strict rc=$strict_rc" >&2; exit 1; }
  if run_mutgate 65 "$CASE_ROOT/mut-pass.log"; then pass_rc=0; else pass_rc=$?; fi
  [ "$pass_rc" = 0 ] || { cat "$CASE_ROOT/mut-pass.log" >&2; echo "T-10 FAIL: mutgate rc=$pass_rc" >&2; exit 1; }
  REPORT="$PKG/reports/mutation/mutation.json"
  # Echter muttest-Bericht: Stryker-Felder, reale Status, der Grenzfall > → >= überlebt.
  jq -e '.files["R/clamp.R"].mutants | length > 0
    and all(.[]; (.status | IN("Killed","Survived","NoCoverage","RuntimeError","Timeout"))
      and (.mutatorName | type == "string") and (.location.start.line | type == "number"))
    and any(.[]; .status == "Killed")
    and any(.[]; .status == "Survived" and .mutatorName == "> → >=")' "$REPORT" >/dev/null
  expected="$(jq -r '[.files[].mutants[]] as $m
    | ([$m[] | select(.status=="Killed" or .status=="Timeout")] | length) as $d
    | ([$m[] | select(.status=="Survived" or .status=="NoCoverage")] | length) as $u
    | (10000 * $d / ($d + $u) | round) / 100' "$REPORT")"
  grep -F "mutgate: pass (score=$expected required=65" "$CASE_ROOT/mut-pass.log" >/dev/null
  grep -F "mutgate: fail (score=$expected required=90" "$CASE_ROOT/mut-strict.log" >/dev/null
  grep -F 'r-mutation: ' "$CASE_ROOT/mut-pass.log" >/dev/null
  test -z "$(git -C "$PKG" status --porcelain --untracked-files=no | grep -vE '^ M (STATUS\.md|orchestrator/state/summary\.json)$' || true)"
  MUTATION="muttest,score=$expected,fail@90,pass@65"
  printf 'T-10 evidence mutation: %s\n' "$(grep -m1 -F 'mutgate: pass' "$CASE_ROOT/mut-pass.log")"
else
  echo 'T-10 Mutationsadapter übersprungen: muttest fehlt'
fi

printf 'T-10 evidence toolchain: %s\n' "$(grep -m1 -F 'runtime R ok' "$CASE_ROOT/toolchain.log")"
printf 'T-10 evidence gates: %s\n' "$(jq -c '.gates' "$PKG/orchestrator/state/M0/gates.json")"
printf 'T-10 evidence check: %s\n' "$(grep -m1 -F 'r-check: pass' "$PKG/orchestrator/state/M0/gate-lint.log")"
echo "T-10 PASS: install=tools/install-into.sh preset-blocks=config-env,toolchain m0=done gates=deps,lint,tests,trace,territory,mutgate,golden-adr R/=unchanged rbuildignore=complete mutation=$MUTATION"
