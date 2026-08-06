#!/usr/bin/env bash
# T2: einmal rot und nach Rework gruen. T3: dauerhaft rot.
set -uo pipefail

case "${ACCEPTANCE_SCENARIO:-}" in
  T2)
    if [ "$MILESTONE" != M0 ] || [ -s "$REPO_ROOT/src/rework-ok" ]; then
      echo "behavior: $MILESTONE passed"
      exit 0
    fi
    echo "behavior: M0 intentionally red before rework"
    exit 1
    ;;
  T3)
    echo "behavior: intentional permanent failure in round $ROUND"
    exit 1
    ;;
  T6)
    echo "behavior: $MILESTONE passed with digit-free id"
    exit 0
    ;;
  TERROR)
    echo "behavior: intentional infrastructure error in round $ROUND" >&2
    exit 2
    ;;
  *)
    echo "behavior: unknown fixture scenario" >&2
    exit 2
    ;;
esac
