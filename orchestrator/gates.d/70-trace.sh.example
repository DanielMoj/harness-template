#!/usr/bin/env bash
set -euo pipefail
source "$ORCH/gates.d/_lib.sh"
gate_load_config

if [ -n "${TRACE_CMD:-}" ]; then
  gate_run_configured TRACE_CMD trace
  exit $?
fi

CRITERIA="$ORCH/handoff/$MILESTONE/CRITERIA.json"
MILESTONES="$ORCH/milestones.json"
[ -f "$CRITERIA" ] || { echo "trace: CRITERIA.json fehlt"; exit 1; }
jq -e '.criteria|type=="array" and length>0 and all(.[]; (.id|type=="string") and (.quote|type=="string" and length>0) and (.source|type=="string" and length>0))' "$CRITERIA" >/dev/null \
  || { echo "trace: CRITERIA.json verletzt das Schema"; exit 1; }

rc=0
while IFS= read -r row; do
  id="$(jq -r '.id' <<<"$row")"
  quote="$(jq -r '.quote' <<<"$row")"
  source_file="$(jq -r '.source' <<<"$row")"
  case "$source_file" in /*|*..*) echo "unsicherer Kriterienpfad: $source_file"; rc=1; continue ;; esac
  [ -f "$REPO_ROOT/$source_file" ] || { echo "Quelle fehlt: $id -> $source_file"; rc=1; continue; }
  grep -Fq -- "$quote" "$REPO_ROOT/$source_file" || { echo "Zitat nicht wörtlich in Quelle: $id"; rc=1; }
  grep -Rqs --exclude-dir=.git -- "$id" "$REPO_ROOT/tests/acceptance" || { echo "kein Abnahmetest referenziert $id"; rc=1; }
done < <(jq -c '.criteria[]' "$CRITERIA")

while IFS= read -r expected; do
  jq -e --arg id "$expected" 'any(.criteria[]; .id==$id)' "$CRITERIA" >/dev/null \
    || { echo "Manifest-Kriterium fehlt in CRITERIA.json: $expected"; rc=1; }
done < <(jq -r --arg id "$MILESTONE" '.[] | select(.id==$id) | .criteriaRef[]' "$MILESTONES")

if [ -d "$REPO_ROOT/tests/acceptance" ]; then
  while IFS= read -r observed; do
    [ -n "$observed" ] || continue
    jq -e --arg id "$observed" 'any(.criteria[]; .id==$id)' "$CRITERIA" >/dev/null \
      || { echo "Abnahmetest referenziert unbekanntes Kriterium: $observed"; rc=1; }
  done < <(grep -RhoE "[A-Z]-${MILESTONE}-[0-9]+" "$REPO_ROOT/tests/acceptance" 2>/dev/null | sort -u || true)
fi

[ "$rc" = 0 ] || { echo "trace: Kriterien/Test-Zuordnung unvollständig"; exit 1; }
echo "trace: alle Kriterien sind wörtlich und beidseitig verknüpft"
