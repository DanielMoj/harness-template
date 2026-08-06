# Rework 1 — Befund, Paket/Commit und ausführbarer Nachweis

Stand: 2026-08-06. Die Spalte „Commit“ nennt das atomare Paket und den
vorgesehenen Betreff. Im laufenden Harness erzeugt ausschließlich der
Orchestrator die Phasencommits; bei der Wartung des Templates erstellt das
Betreiber-Werkzeug die hier geforderten Paketcommits und den Push. Die
Paketbezeichnung bleibt stabil; bei R2 und R8 wird der jeweils zweite
vorbereitete Betreff als Commit-Body desselben Paketcommits geführt.

| Befund | Commit | Ausführbarer Nachweis |
|---|---|---|
| B-01 | R3 — `fix(loop): make git and completion failures fatal [B-01 B-06 B-07]` | `test-t7-integrity.sh` (fehlende Identität), `test-t2-rework.sh` (Phasencommits und Tags) |
| B-02 | R2 — `fix(territory): check ignored paths and phase logs [B-02 L2-B-02]` | `test-t7-integrity.sh` (Lock-/Report-Schreibversuch, Log-Fälschung, Rollback) |
| B-03 | R4 — `fix(preflight): validate contracts prompts and expanded commands [B-03 B-18 B-15 L2-B-03]` | `test-t7-integrity.sh` (fehlender Prompt) |
| B-04 | R6 — `fix(phases): persist round markers and manifest-index QA [B-04 B-11 B-23]` | `test-t6-qa-autonomy.sh` (acht Aufrufe, acht Phasen) |
| B-05 | R5 — `fix(gates): separate infrastructure errors from failures [B-05 B-24 B-16]` | `test-t8-gates.sh` (zwei Wiederholungen, Runde 1, kein Rework/Rebuild) |
| B-06 | R3 | `test-t7-integrity.sh` (deps-Zyklus → FATAL/Notify) |
| B-07 | R3 | `test-t7-integrity.sh` (`M1` mit offenem `M0` → FATAL) |
| B-08 | R1 — `fix(security): isolate secrets and constrain connector grep [L2-B-01 B-08]` | `test-t1-bootstrap.sh`, `test-t7-integrity.sh` (LEAK-Umgebungsprobe) |
| B-09 | R7 — `feat(presets): add reviewer and QA territory hooks [B-09 B-21]` | `test-t7-integrity.sh` (`stilbibel.md` im Text-Preset akzeptiert) |
| B-10 | R8 — `test(evidence): make T-5 source-backed and behavioral [B-10 B-12 B-13 B-19 B-20 B-22]` | `test-t5-behavior.sh`, `test-t5-inventory.py` |
| B-11 | R6 | `test-t6-qa-autonomy.sh` (IDs `setup`, `kapitel-eins`) |
| B-12 | R8 | `test-t2-rework.sh`, `test-t7-integrity.sh` (`-a1` und `-a2` bleiben beide erhalten) |
| B-13 | R8 | `run-all.sh`; echter Output in `docs/template/ABNAHME.md` |
| B-14 | bewusst nicht bearbeitet | Regel 4 des Auftrags: Historie und damaliger nicht lauffähiger Zwischenstand werden nicht rückwirkend umgeschrieben. |
| B-15 | R4 | `test-t7-integrity.sh` (leeres Pattern → FATAL; `ROLE_GUARDS=off` laut in Log und Summary) |
| B-16 | R5 | `test-t8-gates.sh` (Runde und Basis-SHA des Territory-Markers) |
| B-17 | R2 — `fix(lock): acquire atomically and preserve live heartbeat [B-17 L2-B-04]` | `test-t4-ops.sh`, `test-t7-integrity.sh` |
| B-18 | R4 | `test-t7-integrity.sh` (`criteriaRef` mit `|` → Manifest-FATAL) |
| B-19 | R8 | `test-t5-inventory.py` (`cross-file=PASS`) |
| B-20 | R8 | `test-t4-ops.sh` (`status-precedence=parked`) |
| B-21 | R7 | `test-t5-inventory.py` (alte Pfade fehlen, Löschhinweis), `test-t7-integrity.sh` (Preset-Hook) |
| B-22 | R8 | `test-t8-gates.sh` (mutgate pass/ratchet-fail/error, trace, golden-adr) |
| B-23 | R6 | `test-t6-qa-autonomy.sh` (aktive QA und QA-Park) |
| B-24 | R5 | `test-t8-gates.sh` (`rc=5` → `fail`) |
| L2-B-01 | R1 | `orchestrator/mcp/tests/test_allowlist.py` (Attrappen-Key, rekursiver grep) |
| L2-B-02 | R2 | `test-t7-integrity.sh` (unsichtbarer Lock-Pfad erkannt und verworfen) |
| L2-B-03 | R4 | `test-t7-integrity.sh` (`$EXTRA_FLAGS` → PREFLIGHT-FATAL) |
| L2-B-04 | R2 | `test-t4-ops.sh` (Doppelstart verändert weder Heartbeat noch Notify; Watchdog bleibt STALE) |
| L2-B-05 | R6 | `test-t6-qa-autonomy.sh` (ziffernlose IDs end-to-end) |
| L2-N-01 | R8 — `docs(prompts): complete context and evidence metadata [L2-N-01 L2-N-02]` | `test-t5-inventory.py` prüft alle neun Prompt-Kontextmanifeste. |
| L2-N-02 | R8 | `test-t5-inventory.py` prüft für T5-PATCH-15 sowohl LESSONS in sechs Prompts als auch die CONFIG-Provenienz. |

## Ausgeführte Suite

```text
$ HARNESS_MCP_PYTHON=<externes-python> bash tests/template/run-all.sh
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

Die acht Paketcommits und der Push sind bei der Wartung des Templates Aufgabe
des Betreiber-Werkzeugs. Eine frische, unbeteiligte Prüfersitzung muss danach
weiterhin die ursprünglichen Repro-Kommandos nachfahren; erst dieses Urteil
schließt den Rework fachlich ab.
