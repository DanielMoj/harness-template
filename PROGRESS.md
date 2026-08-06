# PROGRESS — Langzeitgedächtnis des Builders

## Rework 1 — 2026-08-06

### Gelieferte Artefakte und Verträge

- R1: `orchestrator/secrets.env` wird unversioniert mit Modus 600 angelegt;
  Bootstrap migriert Tunnel-/API-Geheimnisse. Modellphasen laufen mit
  `env -i` und rollenbezogener Allowlist. Rekursives MCP-`grep` ist auf vier
  Verzeichniswurzeln beschränkt und erzwingt `--exclude=*.env`.
- R2: `changed_paths()` prüft ungetrackte Pfade ohne
  `--exclude-standard`, filtert nur die versionierte
  `artifact-paths.allowlist` und schützt jedes vorherige Modelllog/Prompt per
  Hash-Snapshot. Lock-Anlage ist atomar; Doppelstarts verändern den laufenden
  Heartbeat nicht.
- R3/R4: Git-Identität, Vertragspfade, Kriterienformat, deps-Zyklen,
  Ziel-deps, Prompt-Rendering und expandierte Rollenkommandos scheitern
  benannt. Git-Commit/Tag/PROGRESS-Fehler werden explizit geprüft.
  `ROLE_GUARDS=off` ist der einzige Abschalter und erscheint in Log/Summary.
- R5: Reine Gate-Infrastrukturfehler werden zweimal in derselben Runde
  wiederholt und danach als Infrastruktur geparkt. rc 126/127 sind
  standardmäßig `error`, sonstige rc>0 `fail`; `GATE_ERROR_CODES` ist
  konfigurierbar. Territory-Marker binden Runde und Phasen-Basis-SHA.
- R6: Manifestindex-basierte QA-Pflicht, aktive Fake-QA, QA-Park und
  rundenbezogene Marker ermöglichen ziffernlose IDs und acht eindeutige
  Autonomiestufe-0-Fortschritte.
- R7: Reviewer-/QA-Territoriumshooks, fertige Preset-Zeilen und
  `docs/template/` als löschbarer interner Dokumentraum.
- R8: eindeutige Versuchszähler in Logs, versioniertes `T5-SOLL.md`, sechs
  ausgeführte T‑5-Verhaltensbelege, synthetische Mutgate-/Trace-/Golden-
  Fixtures, aktualisierte Prompt-/Ankerhinweise sowie
  `REWORK-1-NACHWEIS.md`.

### Ausgeführte Befehle und echter Output

```text
$ bash -n bootstrap.sh orchestrator/orchestrate.sh orchestrator/mcp/start.sh orchestrator/status.sh orchestrator/verifier.sh orchestrator/gates.d/_lib.sh orchestrator/gates.d/82-territory.sh.example tests/template/*.sh tests/template/fixtures/gates/*.sh
$ python3 -m py_compile orchestrator/mcp/server.py orchestrator/mcp/tests/test_allowlist.py tests/template/test-t5-inventory.py
(keine Ausgabe; Exit 0)

$ python3 orchestrator/mcp/tests/test_allowlist.py
test_allowlist: 63/63 OK

$ bash tests/template/test-t6-qa-autonomy.sh
T-6 PASS: qa=active qa-park=pre-round autonomy0=8-distinct-phases digit-free-ids=2

$ bash tests/template/test-t7-integrity.sh
T-7 PASS: hidden-territory=rollback logs=hash-protected env=allowlisted flags=expanded guards=explicit preflight=contracts manifest=cycle qa-bound=validated deps=FATAL identity=FATAL preset-hooks=accepted

$ bash tests/template/test-t8-gates.sh
T-8 PASS: gate-error=2-retries-no-round rc5=fail mutgate=pass,ratchet-fail,error trace=pass golden-adr=fail,pass territory-marker=current

$ HARNESS_MCP_PYTHON=<externes-python-mit-mcp-1.28.1> bash tests/template/run-all.sh
A6 PASS: T-1 T-2 T-3 T-4 MCP-Allowlist T-5B T-5 T-6 T-7 T-8
```

Die vollständigen Negativausgaben stehen in
`docs/template/ABNAHME.md`; die Zuordnung jedes historischen Befunds in
`docs/template/REWORK-1-NACHWEIS.md`.

### Bekannte Schulden und offene Risiken

- Der echte Cloudflare-Tunnelpfad blieb bewusst ungeöffnet (`tunnel=0`).
- B‑14 wird gemäß Auftrag nicht rückwirkend verändert.
- R1–R8 und der Push gehören in diesem Template-Wartungslauf zum
  Betreiber-Werkzeug; die Abschlusskontrolle vergleicht lokalen und
  entfernten Hash und verlangt einen leeren Arbeitsbaum.
- Die geforderte frische, unbeteiligte Repro-Prüfung beider historischer
  Abnahmeberichte steht noch aus.

### Nächster klarer Einstiegspunkt

Nach den atomaren R1–R8-Paketcommits und dem Push startet eine frische
Prüfersitzung, die ausschließlich die Repro-Kommandos aus
`docs/template/abnahme/abnahme-lauf1.md` und `abnahme-lauf2.md` nachfährt.
