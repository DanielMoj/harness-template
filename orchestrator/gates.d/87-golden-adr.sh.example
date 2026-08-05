#!/usr/bin/env bash
set -euo pipefail
source "$ORCH/gates.d/_lib.sh"
gate_load_config

GOLDEN_PATH_REGEX="${GOLDEN_PATH_REGEX:-^tests/golden/}"
changed="$(git -C "$REPO_ROOT" diff --name-only "$BASE_SHA")"
if ! grep -Eq -- "$GOLDEN_PATH_REGEX|^reference/anchors/" <<<"$changed"; then
  echo "golden-adr: keine Golden-/Ankeränderung"
  exit 0
fi
if grep -q '^docs/decisions/ADR-' <<<"$changed"; then
  echo "golden-adr: Änderung und ADR liegen im selben Meilenstein"
  exit 0
fi
echo "golden-adr: Golden-/Ankeränderung ohne ADR"
exit 1
