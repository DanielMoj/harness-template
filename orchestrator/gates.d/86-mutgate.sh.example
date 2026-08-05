#!/usr/bin/env bash
# Mutation-Ratchet v2: Pre-Mutation-Tod=error, Äquivalenz nur nach Reviewer-Approval.
set -euo pipefail
source "$ORCH/gates.d/_lib.sh"
gate_load_config

MUT_SCOPE_REGEX="${MUT_SCOPE_REGEX:-^src/.*\.(ts|js|py)$}"
MUT_REPORT="${MUT_REPORT:-reports/mutation/mutation.json}"
MUT_SCORE_MIN="${MUT_SCORE_MIN:-65}"
MUT_SCORE_FLOOR="${MUT_SCORE_FLOOR:-50}"
MUT_RATCHET_TOL="${MUT_RATCHET_TOL:-2}"
BASELINE_FILE="$ORCH/state/mut-baseline"
APPROVED="$ORCH/handoff/$MILESTONE/MUT-EQUIV-APPROVED.json"

CHANGED="$(git -C "$REPO_ROOT" diff --name-only "$BASE_SHA" | grep -E -- "$MUT_SCOPE_REGEX" | paste -sd, - || true)"
if [ -z "$CHANGED" ]; then
  echo "mutgate: pass (kein geänderter Mutations-Scope)"
  exit 0
fi
[ -n "${MUT_CMD:-}" ] || { echo "mutgate: MUT_CMD ist leer" >&2; exit 2; }

score_from_report() {
  local approved_json='[]'
  [ ! -f "$APPROVED" ] || approved_json="$(jq -c '.approved // []' "$APPROVED" 2>/dev/null || echo '[]')"
  jq -r --argjson approved "$approved_json" '
    [ .files | to_entries[] as $file
      | $file.value.mutants[]
      | . + {sourceFile:$file.key} ] as $mutants
    | ([ $mutants[] | select(.status=="Killed" or .status=="Timeout") ] | length) as $detected
    | ([ $mutants[] | select(.status=="Survived" or .status=="NoCoverage") ]) as $survivors
    | ([ $survivors[] | select(. as $m | any($approved[]; . as $a
        | ($m.sourceFile | endswith($a.file))
        and ($m.mutatorName == $a.mutator)
        and ($m.location.start.line == $a.line))) ] | length) as $equivalent
    | (($survivors|length)-$equivalent) as $undetected
    | if ($detected+$undetected)==0 then 100
      else 100*$detected/($detected+$undetected) end
    | (. * 100 | round) / 100
  ' "$REPO_ROOT/$MUT_REPORT"
}

run_mutation() {
  rm -f "$REPO_ROOT/$MUT_REPORT"
  export MUT_FILES="$CHANGED"
  set +e
  bash -c "$MUT_CMD"
  MUT_RC=$?
  set -e
  if [ ! -f "$REPO_ROOT/$MUT_REPORT" ]; then
    echo "mutgate: Werkzeug starb vor der Mutation (rc=$MUT_RC, Report fehlt: $MUT_REPORT)" >&2
    return 2
  fi
  SCORE="$(score_from_report 2>/dev/null)" || {
    echo "mutgate: Report ist nicht im erwarteten Stryker-Format" >&2
    return 2
  }
  return 0
}

if [ -f "$BASELINE_FILE" ]; then
  BASELINE="$(cat "$BASELINE_FILE")"
  REQUIRED="$(awk -v b="$BASELINE" -v f="$MUT_SCORE_FLOOR" -v t="$MUT_RATCHET_TOL" 'BEGIN {r=b-t; if(r<f)r=f; printf "%.2f",r}')"
else
  BASELINE="n/a"
  REQUIRED="$MUT_SCORE_MIN"
fi

run_mutation || exit $?
FIRST_SCORE="$SCORE"
if ! awk -v score="$SCORE" -v required="$REQUIRED" 'BEGIN {exit !(score>=required)}'; then
  echo "mutgate: $SCORE < $REQUIRED; genau ein Flake-Rerun"
  run_mutation || exit $?
  SCORE="$(awk -v a="$FIRST_SCORE" -v b="$SCORE" 'BEGIN {printf "%.2f",(a>b)?a:b}')"
fi

if ! awk -v score="$SCORE" -v required="$REQUIRED" 'BEGIN {exit !(score>=required)}'; then
  echo "mutgate: fail (score=$SCORE required=$REQUIRED baseline=$BASELINE floor=$MUT_SCORE_FLOOR)"
  exit 1
fi

if [ ! -f "$BASELINE_FILE" ] || awk -v score="$SCORE" -v baseline="$(cat "$BASELINE_FILE" 2>/dev/null || echo -1)" 'BEGIN {exit !(score>baseline)}'; then
  printf '%s\n' "$SCORE" > "$BASELINE_FILE"
fi
echo "mutgate: pass (score=$SCORE required=$REQUIRED baseline=$(cat "$BASELINE_FILE") floor=$MUT_SCORE_FLOOR)"
