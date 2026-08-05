#!/usr/bin/env bash
# Der eine Befehl nach abgeschlossener Projektierung und bootstrap.sh.
set -euo pipefail
cd "$(dirname "$0")"

for tool in git jq curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FATAL: $tool fehlt; bash bootstrap.sh ausführen." >&2; exit 2; }
done
[ -f orchestrator/config.env ] || { echo "FATAL: orchestrator/config.env fehlt; bash bootstrap.sh ausführen." >&2; exit 2; }
[ -f orchestrator/milestones.json ] || { echo "FATAL: orchestrator/milestones.json fehlt; Projektierung abschließen." >&2; exit 2; }

if [ -z "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
  echo "Hinweis: Für lange Läufe empfiehlt sich tmux; der Orchestrator-Lock verhindert Doppelstarts."
fi
echo "Starte Harness (Not-Aus: touch orchestrator/STOP · Board: STATUS.md)"
exec bash orchestrator/orchestrate.sh "$@"
