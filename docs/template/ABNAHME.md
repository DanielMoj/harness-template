# A6-Abnahme des Templates nach Rework 1

Stand: 2026-08-06. Alle Harness-End-to-End-Tests materialisieren das aktuelle
Template in frische Verzeichnisse unter `/tmp`, initialisieren dort ein eigenes
Git-Repo und räumen es anschließend auf. Fake-Rollen ersetzen ausschließlich
den Modelltransport; Orchestrator, Territoriumsprüfung, Logschutz, Verifier,
Gates, Commits, Tags, Status, Notify und Watchdog sind die echten
Template-Komponenten.

## Vollständiger Suitelauf

Ausgeführt:

```text
$ HARNESS_MCP_PYTHON=<externes-python-mit-mcp-1.28.1> bash tests/template/run-all.sh
T-1 PASS: bootstrap=2 summary=contract-v1 repo-env=absent mcp-manifest=pinned secrets=isolated tunnel=0
T-2 PASS: milestones=2 gates=2 red=1 rework=1 transport-retry=1 territory-retry=1 done=2 exit=0
T-3 PASS: rebuild=r4 arbiter=HUMAN parked=M0 escalation=present exit=3
T-4 PASS: notify=DONE,PARKED watchdog=STALE double-start=isolated foreign-lock=FATAL status-precedence=parked watchdog-exit=1
test_allowlist: 63/63 OK
T-6 PASS: qa=active qa-park=pre-round autonomy0=8-distinct-phases digit-free-ids=2
T-7 PASS: hidden-territory=rollback logs=hash-protected env=allowlisted flags=expanded guards=explicit preflight=contracts manifest=cycle qa-bound=validated deps=FATAL identity=FATAL preset-hooks=accepted
T-8 PASS: gate-error=2-retries-no-round rc5=fail mutgate=pass,ratchet-fail,error trace=pass golden-adr=fail,pass territory-marker=current
T-5B PASS: territory-enforcement flag-ban sandbox-guard lock-orphan qa-park mcp-allowlist executed
T-5 PASS: target=versioned rows=112 static=101 behavior=6 omitted=5 categories=ORCH=12,AGENT=5,D12=64,PATCH=15,D14=7,NEW=9 exact-ids=PASS cross-file=PASS
A6 PASS: T-1 T-2 T-3 T-4 MCP-Allowlist T-5B T-5 T-6 T-7 T-8
```

Zusätzliche Syntax-/Importprüfung:

```text
$ bash -n bootstrap.sh orchestrator/orchestrate.sh orchestrator/mcp/start.sh orchestrator/status.sh orchestrator/verifier.sh orchestrator/gates.d/_lib.sh orchestrator/gates.d/82-territory.sh.example tests/template/*.sh tests/template/fixtures/gates/*.sh
$ python3 -m py_compile orchestrator/mcp/server.py orchestrator/mcp/tests/test_allowlist.py tests/template/test-t5-inventory.py
(keine Ausgabe; Exit 0)
```

## Ausgeführte Negativnachweise

### Geheimnisse und MCP-Allowlist (R1)

T‑1 lief zweimal idempotent. `orchestrator/secrets.env` wurde mit Modus 600
erzeugt; die Assertions bestätigten, dass Attrappenwerte für
`TUNNEL_TOKEN`/`OPENAI_API_KEY` nicht in `config.env` stehen. Der echte
Connector-Test führte die rekursiven grep-Fälle in einer Temp-Fixture aus:

```text
OK    rekursiver grep auf orchestrator-Wurzel gibt config.env nicht heraus
OK    rekursiver grep erzwingt --exclude=*.env
test_allowlist: 63/63 OK
```

Die Modellumgebungsprobe in T‑7 bestätigte nach einem echten Build-Aufruf:

```text
T-7 evidence rollback: lock-stray=absent report-evil=absent model-secrets=absent attempt-logs=2
```

### Territorium, Logs und Lock (R2)

```text
T-7 evidence hidden.log: [20260806-020408] WARN: builder verletzt Territorium: orchestrator/.lock/stray — genau ein Retry mit Hinweis
T-7 evidence tamper.log: [20260806-020416] WARN: builder verletzt Territorium: orchestrator/logs/** (Hash-Manifest) — genau ein Retry mit Hinweis
```

Beide Erstversuche blieben separat als `-a1-...log` erhalten, die zweiten als
`-a2-...log`; Fremdinhalt, Report-Artefakt und Prompt-Fälschung waren nach dem
Rollback nicht vorhanden. Der Betriebsfall Doppelstart ergab:

```text
watchdog: STALE age=1053315200s pid=1
watchdog: STALE age=1053315200s pid=1
T-4 PASS: notify=DONE,PARKED watchdog=STALE double-start=isolated foreign-lock=FATAL status-precedence=parked watchdog-exit=1
```

Der zweite Start lieferte Exit 2, änderte aber weder `summary.json` noch das
Notify-Log. Ein Lock mit `stray` lieferte Exit 2 und den gezielten
Aufräumhinweis.

### Schleife, PREFLIGHT und Promptvertrag (R3/R4)

Die folgenden Zeilen stammen aus den tatsächlich ausgeführten, jeweils
isolierten Fällen in `test-t7-integrity.sh`:

```text
T-7 evidence flag.log: [20260806-020423] FATAL: BUILDER-CMD enthält eine nicht erlaubte $-Referenz; nur $PROMPT_FILE ist zulässig.
T-7 evidence empty-guard.log: [20260806-020423] FATAL: BUILDER-SAFE_MODE_PATTERN ist leer; nur ROLE_GUARDS=off darf Rollenwächter abschalten.
T-7 evidence guards-off.log: [20260806-020423] CONFIG: AUTONOMY=0 PLAN<=2 REWORK<=4 REBUILD@r4 ARBITER+2 TIMEOUT=30 RETRY=1x/0s GATE_ERROR_RETRIES=2 MAX_MS=2 QA=0(ab nie) ROLE_GUARDS=OFF NOTIFY=an BUILDER=bash REVIEWER=bash
T-7 evidence missing-prompt.log: [20260806-020423] FATAL: Vertragspfad fehlt: orchestrator/prompts/10-acceptance.md
T-7 evidence criteria.log: [20260806-020424] FATAL: Meilensteinmanifest verletzt contracts/PROTOCOLS.md §2.
T-7 evidence cycle.log: [20260806-020424] FATAL: Meilensteinmanifest enthält einen deps-Zyklus.
T-7 evidence qa-bound.log: [20260806-020424] FATAL: QA_REQUIRED_FROM ist keine Meilenstein-ID des Manifests: UNKNOWN
T-7 evidence deps.log: [20260806-020424] FATAL: M1 kann nicht gestartet werden; offene Abhängigkeiten: M0
T-7 evidence identity.log: [20260806-020424] FATAL: git user.name fehlt; vor dem Lauf mit 'git config user.name <Name>' setzen.
T-7 evidence bootstrap-identity.log: bootstrap: FATAL: git user.name fehlt; mit 'git config user.name <Name>' setzen
```

Der positive T‑2-Gegenbeleg prüfte zusätzlich eine Commitzahl größer 12 sowie
vorhandene `plan/<MS>`-/`done/<MS>`-Tags und gab unter anderem aus:

```text
orch(M0): gates r1 (rc=1)
orch(M0): builder 60-rework r2
orch(M0): complete milestone
```

### Gate-Semantik und echte Beispiel-Gates (R5/R8)

```text
T-8 evidence gate-error: [20260806-020430] Gate error für M0: Infrastruktur-Wiederholung 1/2 in Runde 1; keine Runde verbraucht
T-8 evidence gate-park: [20260806-020431] PARKED M0: Infrastruktur (Gate error) nach 2 Wiederholungen in Runde 1. — Lauf prüft weitere freie Meilensteine
T-8 evidence rc5: gate rc5: fail — rc5: Kommando meldet fachlichen Fehlschlag rc=5
T-8 evidence territory-stale: territory: Audit stammt aus Runde 2 statt 1
T-8 evidence mut-pass: mutgate: pass (score=100 required=65 baseline=100 floor=50)
T-8 evidence mut-ratchet: mutgate: fail (score=25.00 required=88.00 baseline=90 floor=50)
T-8 evidence mut-error: mutgate: Werkzeug starb vor der Mutation (rc=127, Report fehlt: reports/mutation/mutation.json)
T-8 evidence trace: trace: alle Kriterien sind wörtlich und beidseitig verknüpft
T-8 evidence golden-fail: golden-adr: Golden-/Ankeränderung ohne ADR
T-8 evidence golden-pass: golden-adr: Änderung und ADR liegen im selben Meilenstein
```

Der Dauer-error-Fall endete mit Exit 3, `summary.round==1`, ohne
`round`-Datei, Rework-Marker oder Rebuild-Marker. Die drei Mutgate-Ausgänge
und beide Golden-ADR-Ausgänge stammen aus den echten `.example`-Skripten.

### QA, Autonomiestufe 0 und ziffernlose IDs (R6)

```text
T-6 evidence: [20260806-020358] PARKED setup: QA-Route inaktiv, aber QA ist ab setup Pflicht; keine Rework-Runde wird verbraucht. — Lauf prüft weitere freie Meilensteine
T-6 phases: 10-acceptance,20-plan,30-plan-review,30-plan-approved,40-build,gates,50-code-review,done
T-6 PASS: qa=active qa-park=pre-round autonomy0=8-distinct-phases digit-free-ids=2
```

Der aktive Gegenlauf schrieb für `setup` und `kapitel-eins` je einen
ausführbaren E2E-Zeugen und `QA.md`. Der Parkfall verbrauchte keine
Rework-Runde.

### Presets, Dokumentraum und T‑5 (R7/R8)

```text
T-7 evidence preset-hook: reviewer stilbibel.md accepted
T-5B PASS: territory-enforcement flag-ban sandbox-guard lock-orphan qa-park mcp-allowlist executed
T-5 PASS: target=versioned rows=112 static=101 behavior=6 omitted=5 categories=ORCH=12,AGENT=5,D12=64,PATCH=15,D14=7,NEW=9 exact-ids=PASS cross-file=PASS
```

T‑5 liest die erwartete ID-Menge aus `T5-SOLL.md`, verlangt exakte
Übereinstimmung und akzeptiert für die sechs widerlegten Sicherungen nur
Ergebnis-Schlüssel aus demselben ausgeführten Suitelauf. `cross-file=PASS`
umfasst zusätzlich alle neun Kontextmanifeste, beide Hälften von
T5-PATCH-15, die historische Ankerabweichung und die Migration nach
`docs/template/`.

## Bewusste Grenzen

- Der öffentliche Cloudflare-Tunnel wurde in diesem Rework nicht geöffnet;
  T‑1 lief mit `tunnel=0`. Serverstart/Allowlist/Secret-Trennung wurden lokal
  geprüft.
- B‑14 bleibt gemäß Auftragsregel 4 historisch unverändert.
- R1–R8 und der Push gehören bei der Wartung des Templates zum
  Betreiber-Werkzeug; im laufenden Harness bleiben Phasencommits allein beim
  Orchestrator.
- Eine frische, unbeteiligte Prüfersitzung muss die Repros beider historischen
  Abnahmeberichte erneut ausführen; erst deren Urteil schließt den Rework.
