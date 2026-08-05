#!/usr/bin/env bash
# Fuehrt die komplette A6-Abnahme in der vorgeschriebenen Reihenfolge aus.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
for test_script in \
  test-t1-bootstrap.sh \
  test-t2-rework.sh \
  test-t3-ladder.sh \
  test-t4-ops.sh \
  test-t5-inventory.py; do
  echo
  echo "===== $test_script ====="
  "$HERE/$test_script"
done
echo
echo 'A6 PASS: T-1 T-2 T-3 T-4 T-5'
