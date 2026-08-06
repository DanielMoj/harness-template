#!/usr/bin/env bash
# Rendert den menschlichen Status und Vertrag v1 aus dem dateibasierten Zustand.
set -uo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
ORCH="$REPO_ROOT/orchestrator"

if [ -f "$ORCH/config.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ORCH/config.env"
  set +a
fi

command -v jq >/dev/null 2>&1 || {
  echo "status: jq fehlt" >&2
  exit 2
}

MILESTONES="$ORCH/milestones.json"
[ -f "$MILESTONES" ] || MILESTONES="$ORCH/milestones.json.example"
jq -e 'type=="array"' "$MILESTONES" >/dev/null || {
  echo "status: ungültiges Meilensteinmanifest: $MILESTONES" >&2
  exit 2
}

mkdir -p "$ORCH/state"
PROJECT="${PROJECT_SLUG:-$(basename "$REPO_ROOT")}"
TOTAL="$(jq 'length' "$MILESTONES")"
ARG_MS="${1:-${CURRENT_MS:-}}"
ARG_PHASE="${2:-${CURRENT_PHASE:-}}"
ARG_REASON="${3:-${STATUS_REASON:-}}"
ARG_EXIT="${4:-${STATUS_EXIT:-null}}"

phase_for() {
  local ms="$1" st="$ORCH/state/$1" hd="$ORCH/handoff/$1"
  if [ -f "$st/parked" ]; then echo parked
  elif [ -f "$st/8-done.done" ]; then echo done
  elif [ -f "$st/current-phase" ]; then cat "$st/current-phase"
  elif [ ! -f "$st/1-acceptance.done" ]; then echo 10-acceptance
  elif [ ! -f "$st/3-plan-approved.done" ]; then
    [ -f "$hd/verdict-plan.json" ] && echo 30-plan-review || echo 20-plan
  elif [ ! -f "$st/5-built.done" ]; then echo 40-build
  elif [ ! -f "$st/5b-qa.done" ]; then echo 45-qa
  elif [ -f "$hd/verdict-code.json" ]; then echo 50-code-review
  else echo gates
  fi
}

if [ -z "$ARG_MS" ]; then
  while IFS= read -r candidate; do
    if [ ! -f "$ORCH/state/$candidate/8-done.done" ]; then
      ARG_MS="$candidate"
      break
    fi
  done < <(jq -r '.[].id' "$MILESTONES")
fi

INDEX=0
ROUND=0
GATES='{}'
if [ -n "$ARG_MS" ]; then
  INDEX="$(jq -r --arg id "$ARG_MS" 'to_entries[] | select(.value.id==$id) | .key+1' "$MILESTONES" | head -n 1)"
  : "${INDEX:=0}"
  ROUND="$(cat "$ORCH/state/$ARG_MS/round" 2>/dev/null || echo 1)"
  [ -n "$ARG_PHASE" ] || ARG_PHASE="$(phase_for "$ARG_MS")"
  if [ -f "$ORCH/state/$ARG_MS/gates.json" ]; then
    GATES="$(jq -c '.gates // {}' "$ORCH/state/$ARG_MS/gates.json" 2>/dev/null || echo '{}')"
  fi
fi
[ -n "$ARG_PHASE" ] || ARG_PHASE=idle

PARKED='[]'
while IFS= read -r ms; do
  [ -f "$ORCH/state/$ms/parked" ] || continue
  PARKED="$(jq -c --arg ms "$ms" '. + [$ms]' <<<"$PARKED")"
done < <(jq -r '.[].id' "$MILESTONES")

if [ -z "$ARG_REASON" ] && [ -n "$ARG_MS" ] && [ -f "$ORCH/state/$ARG_MS/reason" ]; then
  ARG_REASON="$(cat "$ORCH/state/$ARG_MS/reason")"
fi

NEEDS_HUMAN="${STATUS_NEEDS_HUMAN:-false}"
if [ "$ARG_PHASE" = parked ] || { [ -n "$ARG_REASON" ] && [ -f "$ORCH/state/${ARG_MS:-_}/parked" ]; }; then
  NEEDS_HUMAN=true
fi
case "$NEEDS_HUMAN" in true|false) ;; *) NEEDS_HUMAN=false ;; esac
case "$ARG_EXIT" in null|'') EXIT_JSON=null ;; *[!0-9-]*) EXIT_JSON=null ;; *) EXIT_JSON="$ARG_EXIT" ;; esac

LAST_EVENTS='[]'
if [ -f "$ORCH/logs/orchestrate.log" ]; then
  LAST_EVENTS="$(tail -n 5 "$ORCH/logs/orchestrate.log" | jq -Rsc 'split("\n") | map(select(length>0))')"
fi

TS="$(date --iso-8601=seconds)"
SUMMARY_TMP="$ORCH/state/.summary.json.tmp.$$"
jq -n \
  --arg project "$PROJECT" \
  --arg ts "$TS" \
  --arg ms "$ARG_MS" \
  --argjson index "$INDEX" \
  --argjson total "$TOTAL" \
  --arg phase "$ARG_PHASE" \
  --argjson round "$ROUND" \
  --argjson needs_human "$NEEDS_HUMAN" \
  --arg reason "$ARG_REASON" \
  --argjson gates "$GATES" \
  --argjson parked "$PARKED" \
  --argjson last_events "$LAST_EVENTS" \
  --argjson exit "$EXIT_JSON" \
  --arg role_guards "${ROLE_GUARDS:-on}" \
  '{contract:1,project:$project,ts:$ts,milestone:{id:$ms,index:$index,total:$total},phase:$phase,round:$round,needs_human:$needs_human,reason:$reason,gates:$gates,parked:$parked,last_events:$last_events,exit:$exit,role_guards:$role_guards}' \
  > "$SUMMARY_TMP"
mv "$SUMMARY_TMP" "$ORCH/state/summary.json"

DONE_N=0
ROWS=""
BAR=""
while IFS=$'\t' read -r id title; do
  st="$ORCH/state/$id"
  if [ -f "$st/8-done.done" ]; then
    icon="✅"; BAR="${BAR}▓"; DONE_N=$((DONE_N+1)); detail="fertig"
  elif [ -f "$st/parked" ]; then
    icon="⛔"; BAR="${BAR}✖"; detail="PARKED: $(head -c 160 "$st/parked")"
  elif [ "$id" = "$ARG_MS" ]; then
    icon="🔨"; BAR="${BAR}▒"; detail="Phase $ARG_PHASE · Runde $ROUND"
  else
    icon="⬜"; BAR="${BAR}░"; detail="offen"
  fi
  title="${title//|/\\|}"
  detail="${detail//|/\\|}"
  ROWS="${ROWS}| $id | $title | $icon | $detail |"$'\n'
done < <(jq -r '.[] | [.id,.title] | @tsv' "$MILESTONES")

{
  echo "# STATUS — $PROJECT"
  echo
  echo "Stand: $TS · Fortschritt: **$DONE_N/$TOTAL fertig**"
  echo
  echo "\`$BAR\`  (▓ fertig · ▒ in Arbeit · ░ offen · ✖ geparkt)"
  echo
  echo "| Paket | Inhalt | Status | Detail |"
  echo "|---|---|---|---|"
  printf '%s' "$ROWS"
  echo
  if [ "$(jq 'length' <<<"$PARKED")" -gt 0 ]; then
    echo "Geparkt: \`$(jq -r 'join(", ")' <<<"$PARKED")\`"
    echo
  fi
  echo "_Automatisch aus \`orchestrator/state/\` erzeugt; Maschinenvertrag: \`orchestrator/state/summary.json\`._"
} > "$REPO_ROOT/STATUS.md"

echo "status: contract=1 project=$PROJECT phase=$ARG_PHASE milestone=${ARG_MS:-none} progress=$DONE_N/$TOTAL"
