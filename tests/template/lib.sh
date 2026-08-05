#!/usr/bin/env bash
# Gemeinsame Hilfen fuer die reproduzierbare Template-Abnahme.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

new_case_root() {
  mktemp -d /tmp/harness-acceptance.XXXXXX
}

cleanup_case() {
  local case_root="$1"
  if [ "${HARNESS_ACCEPTANCE_KEEP:-0}" = 1 ]; then
    echo "acceptance: temporaerer Fall bleibt unter $case_root"
  else
    rm -rf -- "$case_root"
  fi
}

materialize_tree() {
  local destination="$1"
  mkdir -p "$destination"
  (
    cd "$REPO_ROOT"
    git ls-files -z | tar --null -T - -cf -
  ) | tar -xf - -C "$destination"

  # Beim ersten Lauf ist dieses Arbeitspaket noch nicht committed. Die
  # explizite Kopie macht denselben Test vor und nach seinem Commit moeglich.
  mkdir -p "$destination/tests"
  cp -a "$TEST_DIR" "$destination/tests/template"
}

init_fixture_repo() {
  local repo="$1"
  (
    cd "$repo"
    git init -q -b main
    git config user.name Harness-Acceptance
    git config user.email harness-acceptance@test.invalid
    git add -A
    git commit -qm "fixture: initial state"
    test -z "$(git status --porcelain --untracked-files=all)"
  )
}

prepare_orchestrator_case() {
  local scenario="$1" destination="$2" config_fixture milestones_fixture
  case "$scenario" in
    T2)
      config_fixture=config-t2.env
      milestones_fixture=milestones-t2.json
      ;;
    T3)
      config_fixture=config-t3.env
      milestones_fixture=milestones-t3.json
      ;;
    *) echo "acceptance: unbekanntes Szenario $scenario" >&2; return 2 ;;
  esac

  materialize_tree "$destination"
  cp "$TEST_DIR/fixtures/$config_fixture" "$destination/orchestrator/config.env"
  cp "$TEST_DIR/fixtures/$milestones_fixture" "$destination/orchestrator/milestones.json"
  cp "$TEST_DIR/fixtures/99-acceptance-fixture.md" "$destination/docs/99-acceptance-fixture.md"
  cp "$destination/toolchain.json.example" "$destination/toolchain.json"
  cp "$TEST_DIR/fixtures/gates/10-product.sh" "$destination/orchestrator/gates.d/10-product.sh"
  cp "$TEST_DIR/fixtures/gates/20-behavior.sh" "$destination/orchestrator/gates.d/20-behavior.sh"
  chmod +x "$destination/orchestrator/gates.d/10-product.sh" \
    "$destination/orchestrator/gates.d/20-behavior.sh"
  init_fixture_repo "$destination"
}

require_file() {
  local path="$1"
  [ -f "$path" ] || { echo "acceptance: Datei fehlt: $path" >&2; return 1; }
}
