#!/usr/bin/env bash
# Fuehrt die komplette A6-Abnahme in der vorgeschriebenen Reihenfolge aus.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HARNESS_BEHAVIOR_RESULTS="$(mktemp /tmp/harness-behavior-results.XXXXXX)"
export HARNESS_BEHAVIOR_RESULTS
trap 'rm -f -- "$HARNESS_BEHAVIOR_RESULTS"' EXIT
for test_script in \
  test-t1-bootstrap.sh \
  test-t2-rework.sh \
  test-t3-ladder.sh \
  test-t4-ops.sh \
  ../../orchestrator/mcp/tests/test_allowlist.py \
  test-t6-qa-autonomy.sh \
  test-t7-integrity.sh \
  test-t8-gates.sh \
  test-t5-behavior.sh \
  test-t5-inventory.py; do
  echo
  echo "===== $test_script ====="
  "$HERE/$test_script"
done
echo
echo 'A6 PASS: T-1 T-2 T-3 T-4 MCP-Allowlist T-5B T-5 T-6 T-7 T-8'
