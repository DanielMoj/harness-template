#!/usr/bin/env bash
set -euo pipefail
AUDIT="$ORCH/state/$MILESTONE/territory-ok"
[ -f "$AUDIT" ] || { echo "territory: kein erfolgreicher Territoriums-Diff für die letzte Modellphase"; exit 1; }
IFS=$'\t' read -r timestamp role phase audit_round audit_base < "$AUDIT"
[ -n "${timestamp:-}" ] && [ -n "${role:-}" ] && [ -n "${phase:-}" ] \
  && [ -n "${audit_round:-}" ] && [ -n "${audit_base:-}" ] \
  || { echo "territory: Auditdatei ungültig"; exit 2; }
[ "$audit_round" = "$ROUND" ] \
  || { echo "territory: Audit stammt aus Runde $audit_round statt $ROUND"; exit 1; }
expected_base="$(git -C "$REPO_ROOT" rev-parse HEAD^)" \
  || { echo "territory: Basis-SHA der letzten Modellphase nicht bestimmbar"; exit 2; }
[ "$audit_base" = "$expected_base" ] \
  || { echo "territory: Audit-Basis $audit_base passt nicht zur Modellphase $expected_base"; exit 1; }
echo "territory: letzter Diff sauber ($role/$phase, Runde $audit_round, Basis $audit_base, $timestamp)"
