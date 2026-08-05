#!/usr/bin/env bash
# T-1: frischer Checkout, Bootstrap zweimal, Statusvertrag und externe Umgebung.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

CASE_ROOT="$(new_case_root)"
REPO="$CASE_ROOT/repo"
SLUG="acceptance-t1-$$"
SESSION="mcp-$SLUG"
PORT_VALUE="${HARNESS_T1_PORT:-$((20000 + $$ % 20000))}"

cleanup_t1() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  cleanup_case "$CASE_ROOT"
}
trap cleanup_t1 EXIT
materialize_tree "$REPO"
init_fixture_repo "$REPO"

bootstrap_once() {
  local -a env_args
  local -a bootstrap_args
  env_args=("MCP_ENV_DIR=$CASE_ROOT/mcp-venv" "TUNNEL_MODE=quick" \
    "PROJECT_SLUG=$SLUG" "PORT=$PORT_VALUE")
  bootstrap_args=(--non-interactive)
  [ "${HARNESS_T1_WITH_TUNNEL:-0}" = 1 ] || bootstrap_args+=(--no-start)
  if [ -n "${HARNESS_MCP_PYTHON:-}" ]; then
    env_args+=("MCP_PYTHON=$HARNESS_MCP_PYTHON")
  fi
  (
    cd "$REPO"
    env "${env_args[@]}" bash bootstrap.sh "${bootstrap_args[@]}"
  )
}

echo '[T-1] bootstrap run 1'
bootstrap_once
echo '[T-1] bootstrap run 2 (idempotence)'
bootstrap_once

(
  cd "$REPO"
  jq -e --arg project "$SLUG" '.contract==1 and .project==$project and (.ts|length)>0 and .milestone.id=="M0" and (.gates|type)=="object" and (.parked|type)=="array"' \
    orchestrator/state/summary.json
  test -f orchestrator/config.env
  test -f orchestrator/milestones.json
  test -f toolchain.json
  test "$(cat orchestrator/mcp/requirements.txt)" = 'mcp==1.28.1'
  test -z "$(find . -type d \( -name .venv -o -name venv \) -print -quit)"
  grep -Fx "PORT=$PORT_VALUE" orchestrator/config.env
  set -a
  source orchestrator/config.env
  set +a
  mcp_version="$("$MCP_PYTHON" -c 'import importlib.metadata as m; print(m.version("mcp"))')"
  test "$mcp_version" = 1.28.1
  case "$(realpath -m "$MCP_ENV_DIR")" in "$REPO"|"$REPO"/*) exit 1 ;; esac
  echo "mcp-runtime: version=$mcp_version env=external"
  if [ "${HARNESS_T1_WITH_TUNNEL:-0}" = 1 ]; then
    tmux has-session -t "$SESSION"
    grep -Eq '^https://[a-z0-9-]+\.trycloudflare\.com/mcp$' orchestrator/mcp/connector.url
    printf 'connector: %s\n' "$(sed -E 's#https://[^/]+#https://<quick-tunnel>#' orchestrator/mcp/connector.url)"
  fi
  jq -c '{contract,project,milestone,phase,gates,parked,exit}' orchestrator/state/summary.json
)
echo "T-1 PASS: bootstrap=2 summary=contract-v1 repo-env=absent mcp-manifest=pinned tunnel=${HARNESS_T1_WITH_TUNNEL:-0}"
