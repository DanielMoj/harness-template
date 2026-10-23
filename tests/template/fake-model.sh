#!/usr/bin/env bash
# Deterministische Rollen-Fixture: bedient echte Handoff-/Territoriumsvertraege.
set -euo pipefail

if [ "${1:-}" = --help ]; then
  echo "fake-model --help --fixture-safe (frische Einweg-Session; keine Resume-Flags)"
  exit 0
fi

ROLE="${1:?Aufruf: fake-model.sh builder|reviewer|qa}"
[ -n "${PROMPT_FILE:-}" ] && [ -f "$PROMPT_FILE" ] \
  || { echo "fake-model: PROMPT_FILE fehlt" >&2; exit 2; }

PROMPT_NAME="$(basename "$PROMPT_FILE")"
if [[ "$PROMPT_NAME" == qa-probe-* ]]; then
  # PREFLIGHT-Routenprobe; "untrusted" ahmt die stille Rueckstufung der Gemini CLI nach.
  if [ "${ACCEPTANCE_QA_PROBE:-ok}" = untrusted ]; then
    echo 'Approval mode overridden to "default" because the current folder is not trusted.' >&2
    echo 'fake-model: QA-Routenprobe ohne Schluessel abgebrochen (intentional acceptance probe)' >&2
    exit 41
  fi
  echo "OK"
  echo "fake-model: role=$ROLE phase=qa-probe args=$*"
  exit 0
fi
if [[ "$PROMPT_NAME" =~ ^(.+)-(10-acceptance|20-plan|30-plan-review|40-build|45-qa|50-code-review|60-rework|62-rebuild|70-arbiter)-r([0-9]+)- ]]; then
  MS="${BASH_REMATCH[1]}"
  PHASE="${BASH_REMATCH[2]}"
  ROUND="${BASH_REMATCH[3]}"
else
  echo "fake-model: unbekannter Promptname: $PROMPT_NAME" >&2
  exit 2
fi

ORCH=orchestrator
HANDOFF="$ORCH/handoff/$MS"
mkdir -p "$HANDOFF"

if [ "${ACCEPTANCE_TRANSPORT_PROBE:-0}" = 1 ] && [ "$MS" = M0 ] \
  && [ "$PHASE" = 20-plan ]; then
  transport_attempts="$(find "$ORCH/logs" -maxdepth 1 -type f -name "$MS-$PHASE-r$ROUND-a*.log" | wc -l)"
  if [ "$transport_attempts" = 1 ]; then
    echo 'HTTP 503 temporarily unavailable (intentional acceptance probe)' >&2
    exit 75
  fi
fi

if [ "${ACCEPTANCE_TERRITORY_PROBE:-0}" = 1 ] && [ "$MS" = M1 ] \
  && [ "$PHASE" = 10-acceptance ] \
  && ! grep -Fq 'vorige Versuch wurde wegen Territoriumsverletzung verworfen' "$PROMPT_FILE"; then
  mkdir -p src
  printf 'must be rolled back\n' > src/reviewer-territory-violation.txt
  echo 'fake-model: intentional territory violation on first attempt'
  exit 0
fi

json_to_file() {
  local destination="$1"
  shift
  jq -n "$@" > "$destination"
}

case "$PHASE" in
  10-acceptance)
    [ "$ROLE" = reviewer ] || exit 2
    if [ "${ACCEPTANCE_REVIEWER_EXTRA_PATH_PROBE:-0}" = 1 ]; then
      printf 'Normative fixture style guide.\n' > stilbibel.md
    fi
    criteria='[]'
    while IFS= read -r id; do
      quote="$(grep -F -- "$id:" docs/99-acceptance-fixture.md | head -n 1)"
      [ -n "$quote" ] || { echo "fake-model: Kriterium fehlt: $id" >&2; exit 2; }
      criteria="$(jq -c --arg id "$id" --arg quote "$quote" \
        '. + [{id:$id,quote:$quote,source:"docs/99-acceptance-fixture.md"}]' <<<"$criteria")"
    done < <(jq -r --arg ms "$MS" '.[] | select(.id==$ms) | .criteriaRef[]' "$ORCH/milestones.json")
    jq -n --argjson criteria "$criteria" '{criteria:$criteria,open:[]}' > "$HANDOFF/CRITERIA.json"
    mkdir -p tests/acceptance
    if [ "${ACCEPTANCE_SCENARIO:-}" = TR ]; then
      # R-Paket-Preset: der Abnahmetest des Fixture-Pakets, ausgeführt vom Test-Gate.
      cp "$(dirname "$0")/fixtures/r-paket/tests/acceptance/test-clamp-acceptance.R" tests/acceptance/
    else
      ids="$(jq -r --arg ms "$MS" '.[] | select(.id==$ms) | .criteriaRef | join(", ")' "$ORCH/milestones.json")"
      printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
        "# Criteria: $ids" "test -s src/$MS.txt" \
        "echo '$MS acceptance fixture: PASS'" > "tests/acceptance/$MS.sh"
      chmod +x "tests/acceptance/$MS.sh"
    fi
    ;;
  20-plan)
    [ "$ROLE" = builder ] || exit 2
    if [ "$ROUND" = 1 ]; then
      printf '# PLAN %s\n\nZiel: Fixture implementieren.\n\nDateien: src/%s.txt, PROGRESS.md.\n\nSchnittstellen: keine.\n\nReihenfolge: bauen, Gates, Review.\n\nRisiken: absichtlich rotes Behavior-Gate.\n\nTestplan: beide Gate-Steckplaetze.\n' \
        "$MS" "$MS" > "$HANDOFF/PLAN.md"
    else
      printf '# PLAN-UPDATE %s r%s\n\n- [E-GATE] akzeptiert: Produktcode wird korrigiert.\n' \
        "$MS" "$ROUND" > "$HANDOFF/PLAN-UPDATE.md"
    fi
    ;;
  30-plan-review)
    [ "$ROLE" = reviewer ] || exit 2
    printf '# PLAN-REVIEW %s r%s\n\nKeine blocking-Befunde.\n' "$MS" "$ROUND" \
      > "$HANDOFF/PLAN-REVIEW.md"
    # missing-plan: Review-Phase endet mit Exit 0, schreibt aber kein Verdict.
    if [ "${ACCEPTANCE_STALE_VERDICT_PROBE:-}" != missing-plan ]; then
      json_to_file "$HANDOFF/verdict-plan.json" \
        --arg ms "$MS" --argjson round "$ROUND" \
        '{milestone:$ms,phase:"plan",round:$round,verdict:"PASS",blocking:[],nonblocking:[]}'
    fi
    ;;
  40-build)
    [ "$ROLE" = builder ] || exit 2
    if [ "${ACCEPTANCE_HIDDEN_TERRITORY_PROBE:-0}" = 1 ] \
        && ! grep -Fq 'vorige Versuch wurde wegen Territoriumsverletzung verworfen' "$PROMPT_FILE"; then
      mkdir -p orchestrator/.lock reports
      printf 'model wrote operator territory\n' > orchestrator/.lock/stray
      printf 'model artifact from rejected attempt\n' > reports/evil.txt
    fi
    if [ "${ACCEPTANCE_LOG_TAMPER_PROBE:-0}" = 1 ] \
        && ! grep -Fq 'vorige Versuch wurde wegen Territoriumsverletzung verworfen' "$PROMPT_FILE"; then
      previous_prompt="$(find orchestrator/logs -maxdepth 1 -type f -name "$MS-10-acceptance-*-prompt.md" | head -n 1)"
      [ -z "$previous_prompt" ] || printf '\nFAELSCHUNG durch das Modell\n' >> "$previous_prompt"
    fi
    if [ "${ACCEPTANCE_SCENARIO:-}" != TR ]; then
      # Im R-Paket-Szenario ändert M0 nichts am Paket; src/ wäre dort kompilierter Code.
      mkdir -p src
      printf 'fixture implementation for %s\n' "$MS" > "src/$MS.txt"
    fi
    if [ "${ACCEPTANCE_ENV_CAPTURE:-0}" = 1 ]; then
      env | LC_ALL=C sort > src/model-env.txt
    fi
    printf '\n- %s build r%s: `printf fixture` → exit 0\n' "$MS" "$ROUND" >> PROGRESS.md
    ;;
  50-code-review)
    [ "$ROLE" = reviewer ] || exit 2
    if [ "${ACCEPTANCE_STALE_VERDICT_PROBE:-}" = code ] && [ "$ROUND" -ge 2 ]; then
      # Ab Runde 2 kein neues Verdict: Das PASS aus Runde 1 bleibt liegen.
      printf '# REVIEW %s r%s\n\nKein neues Verdict (absichtliche Probe).\n' "$MS" "$ROUND" \
        > "$HANDOFF/REVIEW.md"
      echo "fake-model: role=$ROLE phase=$PHASE milestone=$MS round=$ROUND scenario=${ACCEPTANCE_SCENARIO:-unset} args=$*"
      exit 0
    fi
    gate_result="$(jq -r '.result' "$ORCH/state/$MS/gates.json")"
    # code: In Runde 1 übersieht der Reviewer das rote Gate und gibt PASS.
    if [ "$gate_result" = pass ] || [ "${ACCEPTANCE_SCENARIO:-}" = TERROR ] \
        || [ "${ACCEPTANCE_STALE_VERDICT_PROBE:-}" = code ]; then
      printf '# REVIEW %s r%s\n\nGates sind gruen; keine blocking-Befunde.\n' "$MS" "$ROUND" \
        > "$HANDOFF/REVIEW.md"
      json_to_file "$HANDOFF/verdict-code.json" \
        --arg ms "$MS" --argjson round "$ROUND" \
        '{milestone:$ms,phase:"code",round:$round,verdict:"PASS",blocking:[],nonblocking:[]}'
    else
      printf '# REVIEW %s r%s\n\n- [E-GATE] blocking gate:behavior — Behavior-Gate ist rot — Produktcode korrigieren.\n' \
        "$MS" "$ROUND" > "$HANDOFF/REVIEW.md"
      json_to_file "$HANDOFF/verdict-code.json" \
        --arg ms "$MS" --argjson round "$ROUND" \
        '{milestone:$ms,phase:"code",round:$round,verdict:"REWORK",blocking:[{id:"E-GATE",ref:"gate:behavior",note:"absichtlicher Fixture-Befund"}],nonblocking:[]}'
    fi
    ;;
  60-rework)
    [ "$ROLE" = builder ] || exit 2
    mkdir -p src
    if [ "${ACCEPTANCE_SCENARIO:-}" = T2 ] && [ "$MS" = M0 ]; then
      printf 'behavior corrected in r%s\n' "$ROUND" > src/rework-ok
    else
      printf 'permanent-fail attempt r%s\n' "$ROUND" > "src/rework-$ROUND.txt"
    fi
    printf '# REWORK-NOTES %s r%s\n\n- [E-GATE] Produktpfad bearbeitet; Fixture-Gate entscheidet erneut.\n' \
      "$MS" "$ROUND" > "$HANDOFF/REWORK-NOTES.md"
    printf '\n- %s rework r%s: Fixture-Aenderung geschrieben → exit 0\n' "$MS" "$ROUND" >> PROGRESS.md
    ;;
  62-rebuild)
    [ "$ROLE" = builder ] || exit 2
    mkdir -p src
    printf 'rebuilt fixture implementation for %s\n' "$MS" > "src/$MS.txt"
    printf 'independent rebuild path r%s\n' "$ROUND" > "src/rebuild-$ROUND.txt"
    printf '\n- %s rebuild r%s: alternativer Fixture-Pfad → exit 0\n' "$MS" "$ROUND" >> PROGRESS.md
    ;;
  70-arbiter)
    [ "$ROLE" = reviewer ] || exit 2
    printf '# ARBITER %s\n\nHUMAN: Das absichtlich permanente Gate kann ohne Aenderung der Testvorgabe nicht aufgeloest werden.\n' \
      "$MS" > "$HANDOFF/ARBITER.md"
    json_to_file "$HANDOFF/verdict-arbiter.json" \
      --arg ms "$MS" --argjson round "$ROUND" \
      '{milestone:$ms,phase:"code",round:$round,verdict:"HUMAN",directive:"Betreiber muss den absichtlichen Dauer-Fail aufloesen."}'
    ;;
  45-qa)
    [ "$ROLE" = qa ] || exit 2
    mkdir -p tests/e2e
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
      "test -s src/$MS.txt" "echo '$MS QA fixture: PASS'" > "tests/e2e/$MS-qa.sh"
    chmod +x "tests/e2e/$MS-qa.sh"
    printf '# QA %s r%s\n\nAktive Fake-QA hat einen reproduzierbaren E2E-Zeugen geschrieben.\n' \
      "$MS" "$ROUND" > "$HANDOFF/QA.md"
    ;;
esac

echo "fake-model: role=$ROLE phase=$PHASE milestone=$MS round=$ROUND scenario=${ACCEPTANCE_SCENARIO:-unset} args=$*"
