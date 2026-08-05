#!/usr/bin/env bash
# Gate-Runner nach contracts/PROTOCOLS.md §4.
set -uo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
ORCH="$REPO_ROOT/orchestrator"
CONFIG="$ORCH/config.env"

if [ -f "$CONFIG" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG"
  set +a
fi

command -v jq >/dev/null 2>&1 || { echo "verifier: jq fehlt" >&2; exit 2; }
MILESTONE="${1:?Aufruf: bash orchestrator/verifier.sh <MS>}"
ROUND="${ROUND:-$(cat "$ORCH/state/$MILESTONE/round" 2>/dev/null || echo 1)}"
OUT="$ORCH/state/$MILESTONE"
mkdir -p "$OUT" "$OUT/shots"

if git rev-parse -q --verify "refs/tags/plan/$MILESTONE" >/dev/null 2>&1; then
  BASE_SHA="$(git rev-list -n 1 "plan/$MILESTONE")"
  BASE_REF="plan/$MILESTONE"
else
  BASE_SHA="$(git rev-parse HEAD)"
  BASE_REF="HEAD"
fi

export REPO_ROOT ORCH MILESTONE ROUND BASE_SHA
export GATE_ARTIFACT_DIR="$OUT/shots"
export GATES_PROGRESS_JSON="$OUT/.gates-progress.json"
printf '{}\n' > "$GATES_PROGRESS_JSON"

GATES_JSON='{}'
SUMMARIES_JSON='{}'
FAIL_COUNT=0
ERROR_COUNT=0
GATE_COUNT=0

run_gate() {
  local script="$1" file name rc status summary stdout_file stderr_file log_file
  file="$(basename "$script")"
  name="${file#[0-9][0-9]-}"
  name="${name%.sh}"
  stdout_file="$OUT/.gate-$name.stdout.$$"
  stderr_file="$OUT/.gate-$name.stderr.$$"
  log_file="$OUT/gate-$name.log"

  set +e
  "$script" > "$stdout_file" 2> "$stderr_file"
  rc=$?
  set -e
  case "$rc" in
    0) status=pass ;;
    1) status=fail; FAIL_COUNT=$((FAIL_COUNT+1)) ;;
    2) status=error; ERROR_COUNT=$((ERROR_COUNT+1)) ;;
    *) status=error; ERROR_COUNT=$((ERROR_COUNT+1)); printf 'Gate lieferte ungültigen Exit-Code %s (erlaubt: 0/1/2).\n' "$rc" >> "$stderr_file" ;;
  esac

  {
    echo "# stdout"
    cat "$stdout_file"
    if [ -s "$stderr_file" ]; then
      echo
      echo "# stderr"
      cat "$stderr_file"
    fi
    echo
    echo "# runner"
    echo "exit=$rc status=$status script=$file"
  } > "$log_file"
  summary="$(awk 'NF{line=$0} END{print line}' "$stdout_file")"
  [ -n "$summary" ] || summary="$name: $status (kein stdout-Kurzbefund)"
  rm -f "$stdout_file" "$stderr_file"

  GATES_JSON="$(jq -c --arg name "$name" --arg status "$status" '. + {($name):$status}' <<<"$GATES_JSON")"
  SUMMARIES_JSON="$(jq -c --arg name "$name" --arg summary "$summary" '. + {($name):$summary}' <<<"$SUMMARIES_JSON")"
  printf '%s\n' "$GATES_JSON" > "$GATES_PROGRESS_JSON"
  GATE_COUNT=$((GATE_COUNT+1))
  printf 'gate %s: %s — %s\n' "$name" "$status" "$summary"
}

mapfile -t ACTIVE_GATES < <(find "$ORCH/gates.d" -maxdepth 1 -type f -name '[0-9][0-9]-*.sh' -perm -u+x -print | LC_ALL=C sort)
if [ "${#ACTIVE_GATES[@]}" -eq 0 ]; then
  ERROR_COUNT=1
  SUMMARIES_JSON='{"runner":"Keine aktiven Gates. Beispiele nach NN-name.sh kopieren und ausführbar machen."}'
  echo "verifier: keine aktiven Gates" >&2
else
  for gate_script in "${ACTIVE_GATES[@]}"; do
    run_gate "$gate_script"
  done
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  RESULT=fail; EXIT_CODE=1
elif [ "$ERROR_COUNT" -gt 0 ]; then
  RESULT=error; EXIT_CODE=2
else
  RESULT=pass; EXIT_CODE=0
fi

TOOLCHAIN_JSON='{}'
if [ -x "$ORCH/lib/toolchain.sh" ]; then
  TOOLCHAIN_JSON="$("$ORCH/lib/toolchain.sh" versions-json 2>/dev/null || echo '{}')"
fi
SHA="$(git rev-parse HEAD)"
TS="$(date --iso-8601=seconds)"
TMP_JSON="$OUT/.gates.json.tmp.$$"
jq -n \
  --arg milestone "$MILESTONE" \
  --arg base "$BASE_SHA" \
  --arg baseRef "$BASE_REF" \
  --arg ts "$TS" \
  --arg sha "$SHA" \
  --arg bash "${BASH_VERSION:-unknown}" \
  --arg git "$(git --version | awk '{print $3}')" \
  --argjson round "$ROUND" \
  --argjson toolchain "$TOOLCHAIN_JSON" \
  --argjson gates "$GATES_JSON" \
  --argjson summaries "$SUMMARIES_JSON" \
  --arg result "$RESULT" \
  '{milestone:$milestone,round:$round,base:$base,baseRef:$baseRef,env:{ts:$ts,sha:$sha,bash:$bash,git:$git,toolchain:$toolchain},gates:$gates,summaries:$summaries,result:$result}' \
  > "$TMP_JSON"
mv "$TMP_JSON" "$OUT/gates.json"
rm -f "$GATES_PROGRESS_JSON"

echo "gates.json -> $OUT/gates.json (gates=$GATE_COUNT, result=$RESULT, exit=$EXIT_CODE)"
exit "$EXIT_CODE"
