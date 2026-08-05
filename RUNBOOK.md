# RUNBOOK — Betreiber-Handgriffe

## PARKED / Exit 3

1. `orchestrator/ESCALATION-<MS>.md`, Handoff, `gates.json` und referenzierte
   Gate-Logs lesen.
2. Nur die benannte Betreiber-/Infrastrukturursache oder echte Spec-Lücke
   beheben; keine Tests, Gates oder Schwellen abschwächen.
3. Bei einer Spec-Entscheidung ein ADR beziehungsweise eine freigegebene
   Spec-Änderung schreiben.
4. Den Parkmarker gezielt entfernen:
   `rm orchestrator/state/<MS>/parked`.
5. `bash start.sh <MS>`; offene `deps` bleiben weiterhin gesperrt.

## Arbiter meldet HUMAN

`ARBITER.md` enthält die konkrete Frage und beide widersprüchlichen
Spec-Stellen. Entscheide nur diese Frage, dokumentiere den Entscheid als ADR
oder Spec-Korrektur und entferne anschließend den Parkmarker. Ein
`RESOLVE`-Verdict ist bereits bindend und benötigt keinen Betreiberentscheid.

## FATAL / Exit 2

Die letzte `FATAL`-Zeile in `orchestrator/logs/orchestrate.log`,
`STATUS.md` und `state/summary.json` lesen. Häufige Ursachen:

- schmutziger Arbeitsbaum vor dem Lauf,
- fehlendes/ungültiges Manifest oder Rollenkommando,
- reale CLI-Flags stimmen nicht mit config.env überein,
- wiederholter Transport- oder Territoriumsfehler,
- Doppelstart/aktiver Lock.

Ein verwaister Lock wird automatisch erkannt. Einen aktiven Lock nie
entfernen; zuerst die dort genannte PID prüfen.

## STOP

`touch orchestrator/STOP` hält den Orchestrator vor der nächsten Phase mit
FATAL/Exit 2. Nach Sichtung die Datei gezielt entfernen und neu starten.

## Tunnel neu starten

```bash
tmux kill-session -t mcp-<slug>
bash bootstrap.sh --non-interactive
```

Quick Tunnel erzeugt eine neue URL. Beim benannten Tunnel bleiben Hostname
und zufälliger MCP-Pfad stabil. Die aktuelle Connector-Adresse steht lokal
in `orchestrator/mcp/connector.url` und wird nie committet.

## Watchdog

Cron-Beispiel (alle 15 Minuten):

```cron
*/15 * * * * cd /pfad/zum/repo && bash orchestrator/watchdog.sh
```

Nur wenn eine Lock-PID lebt und der `summary.json`-Heartbeat älter als 30
Minuten ist, wird STALE gemeldet. Leeres `NOTIFY_URL` deaktiviert Versand.
