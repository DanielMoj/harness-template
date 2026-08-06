#!/usr/bin/env bash
# T-5B: require executed evidence for the six adversarially disproved claims.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OWN_RESULTS=0
if [ -z "${HARNESS_BEHAVIOR_RESULTS:-}" ]; then
  HARNESS_BEHAVIOR_RESULTS="$(mktemp /tmp/harness-t5-behavior.XXXXXX)"
  export HARNESS_BEHAVIOR_RESULTS
  OWN_RESULTS=1
  trap 'rm -f -- "$HARNESS_BEHAVIOR_RESULTS"' EXIT
fi
if [ ! -s "$HARNESS_BEHAVIOR_RESULTS" ]; then
  python3 "$HERE/../../orchestrator/mcp/tests/test_allowlist.py"
  bash "$HERE/test-t4-ops.sh"
  bash "$HERE/test-t6-qa-autonomy.sh"
  bash "$HERE/test-t7-integrity.sh"
fi

EXPECTED="$(mktemp /tmp/harness-t5-expected.XXXXXX)"
trap 'rm -f -- "$EXPECTED"; [ "$OWN_RESULTS" = 0 ] || rm -f -- "$HARNESS_BEHAVIOR_RESULTS"' EXIT
printf '%s\n' \
  flag-ban \
  lock-orphan \
  mcp-allowlist \
  qa-park \
  sandbox-guard \
  territory-enforcement > "$EXPECTED"
sort -u "$HARNESS_BEHAVIOR_RESULTS" > "$EXPECTED.actual"
diff -u "$EXPECTED" "$EXPECTED.actual"
rm -f -- "$EXPECTED.actual"

echo 'T-5B PASS: territory-enforcement flag-ban sandbox-guard lock-orphan qa-park mcp-allowlist executed'
