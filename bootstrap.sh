#!/usr/bin/env bash
# Idempotente Ersteinrichtung: Core-Tools, Toolchain, externes MCP-venv, Status, tmux/Tunnel.
set -euo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$PWD"
ORCH="$REPO_ROOT/orchestrator"
SECRETS="$ORCH/secrets.env"
UPDATE=0
NONINTERACTIVE=0
NO_START=0
EDIT_CONFIG=0

for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=1 ;;
    --non-interactive) NONINTERACTIVE=1 ;;
    --no-start) NO_START=1 ;;
    --edit) EDIT_CONFIG=1 ;;
    *) echo "Aufruf: bash bootstrap.sh [--update] [--non-interactive] [--no-start] [--edit]" >&2; exit 2 ;;
  esac
done

say() { printf '\n▶ %s\n' "$*"; }
fatal() { echo "bootstrap: FATAL: $*" >&2; exit 2; }

[ -d .git ] || fatal "kein Git-Checkout: $REPO_ROOT"
[ -n "$(git config user.name 2>/dev/null || true)" ] \
  || fatal "git user.name fehlt; mit 'git config user.name <Name>' setzen"
[ -n "$(git config user.email 2>/dev/null || true)" ] \
  || fatal "git user.email fehlt; mit 'git config user.email <Adresse>' setzen"

missing_packages=()
for spec in git:git tmux:tmux jq:jq curl:curl python3:python3; do
  command_name="${spec%%:*}"
  package_name="${spec#*:}"
  command -v "$command_name" >/dev/null 2>&1 || missing_packages+=("$package_name")
done
if command -v python3 >/dev/null 2>&1 && ! python3 -m venv --help >/dev/null 2>&1; then
  missing_packages+=(python3-venv)
fi
if [ "${#missing_packages[@]}" -gt 0 ]; then
  allow_install="${BOOTSTRAP_ALLOW_INSTALL:-0}"
  if [ "$NONINTERACTIVE" = 0 ] && [ "$allow_install" != 1 ]; then
    read -r -p "Fehlende Pakete (${missing_packages[*]}) via apt installieren? [y/N] " answer
    [[ "$answer" =~ ^[YyJj]$ ]] && allow_install=1
  fi
  [ "$allow_install" = 1 ] || fatal "Core-Pakete fehlen: ${missing_packages[*]}"
  command -v apt-get >/dev/null 2>&1 || fatal "automatische Installation unterstützt hier nur apt-get"
  say "Installiere Core-Pakete: ${missing_packages[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y -qq "${missing_packages[@]}"
fi

NEW_CONFIG=0
if [ ! -f "$ORCH/config.env" ]; then
  cp config.env.example "$ORCH/config.env"
  chmod 600 "$ORCH/config.env"
  NEW_CONFIG=1
  say "config.env aus Vorlage erzeugt"
fi
if [ ! -f "$SECRETS" ]; then
  : > "$SECRETS"
  chmod 600 "$SECRETS"
  say "secrets.env für Tunnel-Token und API-Keys erzeugt"
fi
chmod 600 "$SECRETS"
[ -f toolchain.json ] || { cp toolchain.json.example toolchain.json; say "toolchain.json aus Vorlage erzeugt"; }
[ -f "$ORCH/milestones.json" ] || { cp "$ORCH/milestones.json.example" "$ORCH/milestones.json"; say "milestones.json aus Vorlage erzeugt"; }

set_config() {
  local key="$1" value="$2" tmp line found=0
  [[ "$key" =~ (API_KEY|TOKEN|SECRET|PASSWORD|PRIVATE_KEY) ]] \
    && fatal "$key ist ein Geheimnis und gehört in orchestrator/secrets.env"
  tmp="$ORCH/.config.env.tmp.$$"
  : > "$tmp"
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == "$key="* ]]; then
      printf '%s=%q\n' "$key" "$value" >> "$tmp"
      found=1
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$ORCH/config.env"
  [ "$found" = 1 ] || printf '%s=%q\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$ORCH/config.env"
  chmod 600 "$ORCH/config.env"
}

set_secret() {
  local key="$1" value="$2" tmp line found=0
  tmp="$ORCH/.secrets.env.tmp.$$"
  : > "$tmp"
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == "$key="* ]]; then
      printf '%s=%q\n' "$key" "$value" >> "$tmp"
      found=1
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$SECRETS"
  [ "$found" = 1 ] || printf '%s=%q\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$SECRETS"
  chmod 600 "$SECRETS"
}

remove_config_key() {
  local key="$1" tmp="$ORCH/.config.env.tmp.$$" line
  : > "$tmp"
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" == "$key="* ]] || printf '%s\n' "$line" >> "$tmp"
  done < "$ORCH/config.env"
  mv "$tmp" "$ORCH/config.env"
  chmod 600 "$ORCH/config.env"
}

REQUESTED_TUNNEL_MODE="${TUNNEL_MODE:-}"
REQUESTED_TUNNEL_HOSTNAME="${TUNNEL_HOSTNAME:-}"
REQUESTED_TUNNEL_NAME="${TUNNEL_NAME:-}"
REQUESTED_TUNNEL_TOKEN="${TUNNEL_TOKEN:-}"
REQUESTED_PROJECT_SLUG="${PROJECT_SLUG:-}"
REQUESTED_PORT="${PORT:-}"
REQUESTED_MCP_ENV_DIR="${MCP_ENV_DIR:-}"
REQUESTED_MCP_PYTHON="${MCP_PYTHON:-}"
REQUESTED_CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-}"
SECRET_KEYS="TUNNEL_TOKEN OPENAI_API_KEY ANTHROPIC_API_KEY OPENROUTER_API_KEY QA_API_KEY ${HARNESS_SECRET_KEYS:-}"
declare -A REQUESTED_SECRET_VALUES=()
declare -A CONFIG_SECRET_VALUES=()
for secret_name in $SECRET_KEYS; do
  [[ "$secret_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fatal "ungültiger Geheimnisname: $secret_name"
  REQUESTED_SECRET_VALUES["$secret_name"]="${!secret_name:-}"
done
# shellcheck disable=SC1091
source "$ORCH/config.env"
for secret_name in $SECRET_KEYS; do
  CONFIG_SECRET_VALUES["$secret_name"]="${!secret_name:-}"
done
# shellcheck disable=SC1091
source "$SECRETS"
for secret_name in $SECRET_KEYS; do
  secret_value="${REQUESTED_SECRET_VALUES[$secret_name]:-${!secret_name:-${CONFIG_SECRET_VALUES[$secret_name]:-}}}"
  [ -z "$secret_value" ] || set_secret "$secret_name" "$secret_value"
  remove_config_key "$secret_name"
done

SLUG="${REQUESTED_PROJECT_SLUG:-${PROJECT_SLUG:-}}"
[ -n "$SLUG" ] && [ "$SLUG" != harness-project ] \
  || SLUG="$(basename "$REPO_ROOT" | tr -cs 'A-Za-z0-9_-' '-' | sed 's/-$//')"
set_config PROJECT_SLUG "$SLUG"
set_config REPO_PATH "$REPO_ROOT"

PORT_VALUE="${REQUESTED_PORT:-${PORT:-8765}}"
case "$PORT_VALUE" in ''|*[!0-9]*) fatal "PORT muss eine Ganzzahl sein" ;; esac
[ "$PORT_VALUE" -ge 1 ] && [ "$PORT_VALUE" -le 65535 ] \
  || fatal "PORT muss zwischen 1 und 65535 liegen"
set_config PORT "$PORT_VALUE"

MODE="${REQUESTED_TUNNEL_MODE:-${TUNNEL_MODE:-}}"
if [ -z "$MODE" ]; then
  if [ "$NONINTERACTIVE" = 1 ]; then
    MODE=quick
  else
    read -r -p "Tunnelmodus quick oder named [quick]: " MODE
    MODE="${MODE:-quick}"
  fi
fi
case "$MODE" in quick|named) ;; *) fatal "TUNNEL_MODE muss quick oder named sein" ;; esac
set_config TUNNEL_MODE "$MODE"

if [ "$MODE" = named ]; then
  HOSTNAME_VALUE="${REQUESTED_TUNNEL_HOSTNAME:-${TUNNEL_HOSTNAME:-}}"
  NAME_VALUE="${REQUESTED_TUNNEL_NAME:-${TUNNEL_NAME:-}}"
  TOKEN_VALUE="${REQUESTED_TUNNEL_TOKEN:-${TUNNEL_TOKEN:-}}"
  if [ "$NONINTERACTIVE" = 0 ]; then
    [ -n "$HOSTNAME_VALUE" ] || read -r -p "Stabiler Tunnel-Hostname (z. B. mcp.example.org): " HOSTNAME_VALUE
    if [ -z "$TOKEN_VALUE" ] && [ -z "$NAME_VALUE" ]; then
      read -r -p "Tunnelname (leer, wenn TUNNEL_TOKEN per Umgebung gesetzt): " NAME_VALUE
    fi
  fi
  [ -n "$HOSTNAME_VALUE" ] || fatal "named-Tunnel benötigt TUNNEL_HOSTNAME"
  grep -Eq '^([A-Za-z0-9-]+\.)+[A-Za-z0-9-]+$' <<<"$HOSTNAME_VALUE" \
    || fatal "TUNNEL_HOSTNAME muss ein Hostname ohne Schema/Pfad sein"
  [ -n "$TOKEN_VALUE" ] || [ -n "$NAME_VALUE" ] || fatal "named-Tunnel benötigt TUNNEL_TOKEN oder TUNNEL_NAME"
  set_config TUNNEL_HOSTNAME "$HOSTNAME_VALUE"
  set_config TUNNEL_NAME "$NAME_VALUE"
  set_secret TUNNEL_TOKEN "$TOKEN_VALUE"
  EXISTING_PATH="${MCP_PATH:-}"
  if ! grep -Eq '^/mcp-[a-f0-9]{16,64}$' <<<"$EXISTING_PATH"; then
    RANDOM_SUFFIX="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
    EXISTING_PATH="/mcp-$RANDOM_SUFFIX"
  fi
  set_config MCP_PATH "$EXISTING_PATH"
else
  set_config MCP_PATH /mcp
fi

if [ "$NEW_CONFIG" = 1 ] || [ "$EDIT_CONFIG" = 1 ]; then
  if [ "$NONINTERACTIVE" = 0 ]; then
    EDITOR_BIN="${EDITOR:-vi}"
    command -v "$EDITOR_BIN" >/dev/null 2>&1 || fatal "Editor fehlt: $EDITOR_BIN"
    "$EDITOR_BIN" "$ORCH/config.env"
  else
    say "Nichtinteraktiv: Rollen/Kommandos in orchestrator/config.env anschließend prüfen"
  fi
fi

say "Installiere/verifiziere deklarierte Projekt-Toolchain"
if [ "$UPDATE" = 1 ]; then
  bash "$ORCH/lib/toolchain.sh" update
else
  bash "$ORCH/lib/toolchain.sh" install
fi

HARNESS_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/harness-template/$SLUG"
MCP_ENV_VALUE="${REQUESTED_MCP_ENV_DIR:-${MCP_ENV_DIR:-$HARNESS_DATA_HOME/mcp-venv}}"
case "$(realpath -m "$MCP_ENV_VALUE")" in "$REPO_ROOT"|"$REPO_ROOT"/*) fatal "MCP_ENV_DIR muss außerhalb des Repos liegen" ;; esac
mkdir -p "$(dirname "$MCP_ENV_VALUE")"

MCP_PYTHON_VALUE="${REQUESTED_MCP_PYTHON:-${MCP_PYTHON:-}}"
if [ -z "$MCP_PYTHON_VALUE" ]; then
  if [ ! -x "$MCP_ENV_VALUE/bin/python" ]; then
    say "Erzeuge MCP-venv außerhalb des Repos: $MCP_ENV_VALUE"
    python3 -m venv "$MCP_ENV_VALUE" || fatal "venv-Anlage fehlgeschlagen (python3-venv installieren)"
  fi
  MCP_PYTHON_VALUE="$MCP_ENV_VALUE/bin/python"
fi

if [ "$UPDATE" = 1 ] || ! "$MCP_PYTHON_VALUE" -c 'import importlib.metadata as m; raise SystemExit(0 if m.version("mcp")=="1.28.1" else 1)' >/dev/null 2>&1; then
  say "Installiere gepinntes MCP-Manifest"
  "$MCP_PYTHON_VALUE" -m pip install --requirement "$ORCH/mcp/requirements.txt"
fi
set_config MCP_ENV_DIR "$MCP_ENV_VALUE"
set_config MCP_PYTHON "$MCP_PYTHON_VALUE"

CLOUDFLARED_VALUE="${REQUESTED_CLOUDFLARED_BIN:-${CLOUDFLARED_BIN:-$(command -v cloudflared || true)}}"
if [ "$NO_START" = 0 ] && [ -z "$CLOUDFLARED_VALUE" ]; then
  allow_install="${BOOTSTRAP_ALLOW_INSTALL:-0}"
  if [ "$NONINTERACTIVE" = 0 ] && [ "$allow_install" != 1 ]; then
    read -r -p "cloudflared in $HARNESS_DATA_HOME/bin installieren? [y/N] " answer
    [[ "$answer" =~ ^[YyJj]$ ]] && allow_install=1
  fi
  [ "$allow_install" = 1 ] || fatal "cloudflared fehlt"
  case "$(uname -m)" in x86_64) cf_arch=amd64 ;; aarch64|arm64) cf_arch=arm64 ;; *) fatal "nicht unterstützte cloudflared-Architektur" ;; esac
  mkdir -p "$HARNESS_DATA_HOME/bin"
  CLOUDFLARED_VALUE="$HARNESS_DATA_HOME/bin/cloudflared"
  curl -fL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cf_arch" -o "$CLOUDFLARED_VALUE"
  chmod +x "$CLOUDFLARED_VALUE"
fi
[ -z "$CLOUDFLARED_VALUE" ] || set_config CLOUDFLARED_BIN "$CLOUDFLARED_VALUE"

say "MCP-Guards und Statusvertrag prüfen"
env -i PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" HOME="${HOME:-/tmp}" LANG="${LANG:-C.UTF-8}" \
  REPO_PATH="$REPO_ROOT" "$MCP_PYTHON_VALUE" "$ORCH/mcp/server.py" --selftest
bash "$ORCH/status.sh"
jq -e '.contract==1 and (.project|length>0) and (.ts|length>0) and (.milestone|type=="object") and (.gates|type=="object") and (.parked|type=="array")' "$ORCH/state/summary.json" >/dev/null
echo "bootstrap: summary.json contract v1 gültig"

if [ "$NO_START" = 1 ]; then
  echo "bootstrap: --no-start; MCP/Tunnel nicht gestartet"
  exit 0
fi

SESSION="mcp-$(tr -cs 'A-Za-z0-9_-' '-' <<<"$SLUG" | sed 's/-$//')"
if tmux has-session -t "$SESSION" 2>/dev/null; then
  say "tmux-Session $SESSION läuft bereits; kein Doppelstart"
else
  rm -f "$ORCH/mcp/connector.url"
  printf -v TMUX_COMMAND 'cd %q && exec bash %q' "$REPO_ROOT" "$ORCH/mcp/start.sh"
  tmux new-session -d -s "$SESSION" "$TMUX_COMMAND"
  say "MCP/Tunnel in tmux-Session $SESSION gestartet"
fi

CONNECTOR_URL=""
for _ in $(seq 1 60); do
  CONNECTOR_URL="$(cat "$ORCH/mcp/connector.url" 2>/dev/null || true)"
  [ -n "$CONNECTOR_URL" ] && break
  tmux has-session -t "$SESSION" 2>/dev/null || { tail -n 40 "$ORCH/mcp/server.log" "$ORCH/mcp/tunnel.log" 2>/dev/null || true; fatal "MCP-tmux-Session wurde beendet"; }
  sleep 1
done
[ -n "$CONNECTOR_URL" ] || fatal "Connector-URL nach 60s nicht verfügbar"

echo
echo "Connector-URL: $CONNECTOR_URL"
echo "Im Leitstand/Connector eintragen und wie ein Geheimnis behandeln."
echo "Status: tmux attach -t $SESSION"
