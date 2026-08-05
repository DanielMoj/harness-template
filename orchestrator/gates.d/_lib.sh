#!/usr/bin/env bash
# Gemeinsame Funktionen für ausgewählte Gate-Beispiele.

gate_load_config() {
  if [ -f "$ORCH/config.env" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ORCH/config.env"
    set +a
  fi
}

gate_run_configured() {
  local variable="$1" label="$2" command_value
  command_value="${!variable:-}"
  if [ -z "$command_value" ]; then
    echo "$label: Konfigurationsvariable $variable ist leer" >&2
    return 2
  fi
  local rc
  set +e
  bash -c "$command_value"
  rc=$?
  set -e
  case "$rc" in
    0) echo "$label: Kommando erfolgreich"; return 0 ;;
    1) echo "$label: Kommando meldet fachlichen Fehlschlag"; return 1 ;;
    *) echo "$label: Kommando-/Infrastrukturfehler rc=$rc" >&2; return 2 ;;
  esac
}

gate_changed() {
  git -C "$REPO_ROOT" diff --name-only "$BASE_SHA" -- "$@"
}
