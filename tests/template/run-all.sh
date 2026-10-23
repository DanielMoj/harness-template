#!/usr/bin/env bash
# Fuehrt die komplette A6-Abnahme in der vorgeschriebenen Reihenfolge aus.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HARNESS_BEHAVIOR_RESULTS="$(mktemp /tmp/harness-behavior-results.XXXXXX)"
export HARNESS_BEHAVIOR_RESULTS
trap 'rm -f -- "$HARNESS_BEHAVIOR_RESULTS"' EXIT
SKIPPED=""
for test_script in \
  test-t1-bootstrap.sh \
  test-t2-rework.sh \
  test-t3-ladder.sh \
  test-t4-ops.sh \
  ../../orchestrator/mcp/tests/test_allowlist.py \
  test-t6-qa-autonomy.sh \
  test-t7-integrity.sh \
  test-t8-gates.sh \
  test-t9-install.sh \
  test-t10-r-paket.sh \
  test-t5-behavior.sh \
  test-t5-inventory.py; do
  echo
  echo "===== $test_script ====="
  if "$HERE/$test_script"; then
    continue
  else
    rc=$?
  fi
  # Nur das R-Szenario darf mit 77 aussteigen: ohne R ist es übersprungen, nicht bestanden.
  if [ "$rc" = 77 ] && [ "$test_script" = test-t10-r-paket.sh ]; then
    SKIPPED="T-10"
    continue
  fi
  exit "$rc"
done
echo
if [ -n "$SKIPPED" ]; then
  echo 'A6 PASS: T-1 T-2 T-3 T-4 MCP-Allowlist T-5B T-5 T-6 T-7 T-8 T-9 — T-10 übersprungen (R fehlt), nicht bestanden'
else
  echo 'A6 PASS: T-1 T-2 T-3 T-4 MCP-Allowlist T-5B T-5 T-6 T-7 T-8 T-9 T-10'
fi
