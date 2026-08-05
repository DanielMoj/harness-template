#!/usr/bin/env bash
# Fuehrt den vom Reviewer angelegten Abnahmetest aus.
set -uo pipefail

if bash "$REPO_ROOT/tests/acceptance/$MILESTONE.sh"; then
  echo "product: acceptance test for $MILESTONE passed"
  exit 0
fi
echo "product: acceptance test for $MILESTONE failed"
exit 1
