# A6-Abnahme des Templates

Stand: 2026-08-05. Alle Tests arbeiten in frischen Verzeichnissen unter
`/tmp`, initialisieren dort ein eigenes Git-Repo und entfernen es nach dem
Lauf. Fake-Rollen ersetzen nur den Modelltransport; Orchestrator, Verifier,
Gate-Steckplätze, Commits, Tags, Status, Notify und Watchdog sind die echten
Template-Komponenten.

## Ausgeführte Kommandos und Output

Fresh-venv-Probe ohne vorhandenes MCP-Paket:

```text
$ bash tests/template/test-t1-bootstrap.sh
▶ Erzeuge MCP-venv außerhalb des Repos: /tmp/harness-acceptance.S2S8LF/mcp-venv
▶ Installiere gepinntes MCP-Manifest
Successfully installed annotated-types-0.8.0 anyio-4.14.2 attrs-26.1.0 certifi-2026.7.22 cffi-2.1.1 click-8.4.2 cryptography-50.0.0 h11-0.16.0 httpcore-1.0.9 httpx-0.28.1 httpx-sse-0.4.3 idna-3.18 jsonschema-4.26.0 jsonschema-specifications-2025.9.1 mcp-1.28.1 pycparser-3.0 pydantic-2.13.4 pydantic-core-2.46.4 pydantic-settings-2.14.2 pyjwt-2.13.0 python-dotenv-1.2.2 python-multipart-0.0.32 referencing-0.37.0 rpds-py-2026.6.3 sse-starlette-3.4.8 starlette-1.4.1 typing-extensions-4.16.0 typing-inspection-0.4.2 uvicorn-0.52.1
T-1 PASS: bootstrap=2 summary=contract-v1 repo-env=absent mcp-manifest=pinned
```

Echter MCP-/tmux-/Quick-Tunnel-Pfad; die flüchtige URL ist absichtlich
nicht festgehalten:

```text
$ HARNESS_T1_WITH_TUNNEL=1 HARNESS_MCP_PYTHON=<externes-python> bash tests/template/test-t1-bootstrap.sh
▶ MCP/Tunnel in tmux-Session mcp-acceptance-t1-57514 gestartet
▶ tmux-Session mcp-acceptance-t1-57514 läuft bereits; kein Doppelstart
connector: https://<quick-tunnel>/mcp
T-1 PASS: bootstrap=2 summary=contract-v1 repo-env=absent mcp-manifest=pinned tunnel=1
cleanup: PASS session beendet
```

Zusammenhängender Lauf T‑1 bis T‑5:

```text
$ HARNESS_MCP_PYTHON=<externes-python> bash tests/template/run-all.sh
mcp-runtime: version=1.28.1 env=external
T-1 PASS: bootstrap=2 summary=contract-v1 repo-env=absent mcp-manifest=pinned tunnel=0
[20260805-235742] WARN: Transportfehler builder/20-plan rc=75 — Retry 1/1 in 0s; keine Runde verbraucht
gate behavior: fail — behavior: M0 intentionally red before rework
gate behavior: pass — behavior: M0 passed
[20260805-235744] WARN: reviewer verletzt Territorium: src/reviewer-territory-violation.txt — genau ein Retry mit Hinweis
T-2 PASS: milestones=2 gates=2 red=1 rework=1 transport-retry=1 territory-retry=1 done=2 exit=0
[20260805-235747] REBUILD M0: Builder-Territorium zurück auf plan/M0
[20260805-235748] PARKED M0: Codepfad festgefahren (Gates rc=1, Verdict=REWORK); Arbiter benötigt HUMAN. — Lauf prüft weitere freie Meilensteine
{"contract":1,"project":"acceptance-t3","phase":"parked","round":4,"needs_human":true,"reason":"geparkt: M0","parked":["M0"],"exit":3}
T-3 PASS: rebuild=r4 arbiter=HUMAN parked=M0 escalation=present exit=3
notify: sent event=DONE
notify: sent event=PARKED
watchdog: STALE age=1053315200s pid=2
notify-capture: done,parked,stale
T-4 PASS: notify=DONE,PARKED watchdog=STALE watchdog-exit=1
T-5 PASS: rows=112 mapped=107 omitted=5 categories=ORCH=12,AGENT=5,D12=64,PATCH=15,D14=7,NEW=9 locators=PASS
A6 PASS: T-1 T-2 T-3 T-4 T-5
```

Die vollständige, maschinenprüfbare T‑5-Tabelle steht in
`docs/T5-INVENTAR.md`. Ein erneuter Lauf erzeugt neue Zeitstempel und
temporäre Pfade, muss aber dieselben PASS-Zeilen und Zustandsverträge liefern.
