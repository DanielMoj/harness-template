# T‑5 — Vollinventar und Fundstellen

> Template-interne Prüfliste; Zielprojekte dürfen den gesamten Ordner löschen.

Diese Tabelle ist der Nachweisabgleich gegen A9 und die unabhängige Sollliste
`docs/template/T5-SOLL.md`. Die Spalte „Quelle“ benennt nur die
Extraktionsprovenienz; kein Laufzeitcode öffnet oder referenziert ein
Quell-Repo. `tests/template/test-t5-inventory.py` verlangt die exakte
Sollmenge. Statische Belege werden an ihrer Fundstelle validiert; die sechs
adversariell widerlegten Sicherungen benötigen einen ausgeführten
Verhaltensnachweis.

| ID | Quelle / Funktion | Status | Fundstelle | Suchanker oder Begründung |
|---|---|---|---|---|
| T5-ORCH-01 | Aktueller Orchestrator: `TS()` | belegt | `orchestrator/orchestrate.sh` | `TS() {` |
| T5-ORCH-02 | Aktueller Orchestrator: `log()` | belegt | `orchestrator/orchestrate.sh` | `log() {` |
| T5-ORCH-03 | Aktueller Orchestrator: `die()` | belegt | `orchestrator/orchestrate.sh` | `fatal() {` |
| T5-ORCH-04 | Aktueller Orchestrator: `stop_check()` | belegt | `orchestrator/orchestrate.sh` | `stop_check() {` |
| T5-ORCH-05 | Aktueller Orchestrator: `refresh_status()` | belegt | `orchestrator/orchestrate.sh` | `refresh_status() {` |
| T5-ORCH-06 | Aktueller Orchestrator: `render()` | belegt | `orchestrator/orchestrate.sh` | `render_prompt() {` |
| T5-ORCH-07 | Aktueller Orchestrator: `run_model()` | belegt | `orchestrator/orchestrate.sh` | `run_model() {` |
| T5-ORCH-08 | Aktueller Orchestrator: `ownership_check()` | belegt | `orchestrator/orchestrate.sh` | `ownership_check() {` |
| T5-ORCH-09 | Aktueller Orchestrator: `ensure_assets()` | belegt | `orchestrator/orchestrate.sh` | `ensure_project_assets() {` |
| T5-ORCH-10 | Aktueller Orchestrator: `verdict()` | belegt | `orchestrator/orchestrate.sh` | `verdict() {` |
| T5-ORCH-11 | Aktueller Orchestrator: `phase_done()` und `mark()` | belegt | `orchestrator/orchestrate.sh` | `commit_phase() {` |
| T5-ORCH-12 | Aktueller Orchestrator: `escalate()` und Meilensteinschleife | belegt | `orchestrator/orchestrate.sh` | `run_ms() {` |
| T5-AGENT-01 | AGENTS: Pflichtlektüre und bereichsbezogener Kontext | belegt | `AGENTS.md` | `## Pflichtlektüre` |
| T5-AGENT-02 | AGENTS: Rollen, Territorien und Integritätsregeln | belegt | `AGENTS.md` | `## Integrität der Abnahme` |
| T5-AGENT-03 | AGENTS: Handoff- und Arbeitsdisziplin | belegt | `AGENTS.md` | `## Handoff-Disziplin` |
| T5-AGENT-04 | AGENTS: projektspezifischer Stack und Nutzlastlayout | bewusst weggelassen | — | Diese Werte gehören nach A0 und A7 in den freigegebenen Projektblock und das gewählte Preset; eine Demiurg-Stackvorgabe wäre falsche Kopplung. |
| T5-AGENT-05 | AGENTS: projektspezifische Befehle | bewusst weggelassen | — | Konkrete pnpm-, Browser- und Pipeline-Befehle werden aus Projektierung und config.env erzeugt; das Template darf sie nicht erfinden. |
| T5-D12-01 | Konstruktionsprinzip Gewaltenteilung | belegt | `AGENTS.md` | `baut, nimmt nicht ab.` |
| T5-D12-02 | Konstruktionsprinzip deterministische Gates | belegt | `AGENTS.md` | `deterministische Gates entscheiden über grün oder rot.` |
| T5-D12-03 | Konstruktionsprinzip dateibasiertes Protokoll | belegt | `contracts/PROTOCOLS.md` | `# PROTOCOLS — dateibasiertes Rollenprotokoll` |
| T5-D12-04 | Rolle Builder und Schreibterritorium | belegt | `AGENTS.md` | `### Builder` |
| T5-D12-05 | Rolle QA ohne Verdict-Macht | belegt | `AGENTS.md` | `QA hat bewusst keine` |
| T5-D12-06 | Rolle Reviewer und Abnahmetestbesitz | belegt | `AGENTS.md` | `### Reviewer` |
| T5-D12-07 | Betreiberbesitz an Orchestrator und Gates | belegt | `AGENTS.md` | `### Betreiber` |
| T5-D12-08 | Phase PREFLIGHT | belegt | `orchestrator/orchestrate.sh` | `preflight() {` |
| T5-D12-09 | Phase ACCEPTANCE vor Implementierung | belegt | `orchestrator/prompts/10-acceptance.md` | `Rot ist erwartet: Die Tests sind der Vertrag.` |
| T5-D12-10 | Phase PLAN | belegt | `orchestrator/prompts/20-plan.md` | `Schreibe orchestrator/handoff/{{MS}}/PLAN.md` |
| T5-D12-11 | Phase PLAN-REVIEW mit Schema-Verdict | belegt | `orchestrator/prompts/30-plan-review.md` | `verdict-plan.json exakt nach SCHEMA.md` |
| T5-D12-12 | Phase BUILD | belegt | `orchestrator/prompts/40-build.md` | `Implementiere den freigegebenen Plan` |
| T5-D12-13 | Phase GATES | belegt | `orchestrator/orchestrate.sh` | `run_gates() {` |
| T5-D12-14 | Phase QA als reproduzierbare Tests | belegt | `orchestrator/prompts/45-qa.md` | `Jeder echte Befund wird ein reproduzierbarer roter Test` |
| T5-D12-15 | Phase CODE-REVIEW | belegt | `orchestrator/prompts/50-code-review.md` | `Gates sind Fakten.` |
| T5-D12-16 | Phase REWORK | belegt | `orchestrator/prompts/60-rework.md` | `Behebe jeden blocking-Befund` |
| T5-D12-17 | Phase DONE mit PROGRESS-Prüfung und Tag | belegt | `orchestrator/orchestrate.sh` | `PROGRESS.md wurde seit plan/$ms nicht aktualisiert.` |
| T5-D12-18 | Verhandlung: Einwand-IDs und Punktantworten | belegt | `orchestrator/handoff/SCHEMA.md` | `PLAN-UPDATE beantwortet jede Einwand-ID` |
| T5-D12-19 | Verhandlung: Präzedenz Spec vor Reviewer vor Builder | belegt | `contracts/PROTOCOLS.md` | `Präzedenz: Ein deckendes wörtliches Spec-Zitat` |
| T5-D12-20 | Verhandlung: nonblocking nach BACKLOG | belegt | `AGENTS.md` | `nicht in einen Scheinfix.` |
| T5-D12-21 | Verhandlung: einziger Human-Touchpoint | belegt | `AGENTS.md` | `ist der einzige Human-Touchpoint` |
| T5-D12-22 | Gate deps | belegt | `orchestrator/gates.d/10-deps.sh.example` | `gate_run_configured DEPS_CMD deps` |
| T5-D12-23 | Gate lint und Typen | belegt | `orchestrator/gates.d/20-lint.sh.example` | `gate_run_configured LINT_CMD lint` |
| T5-D12-24 | Gate Unit-, Acceptance-, Property- und Golden-Tests | belegt | `orchestrator/gates.d/30-tests.sh.example` | `gate_run_configured TEST_CMD tests` |
| T5-D12-25 | Gate smoke | belegt | `orchestrator/gates.d/40-smoke.sh.example` | `gate_run_configured SMOKE_CMD smoke` |
| T5-D12-26 | Gate graph | belegt | `orchestrator/gates.d/50-graph.sh.example` | `gate_run_configured GRAPH_CMD graph` |
| T5-D12-27 | Gate api | belegt | `orchestrator/gates.d/60-api.sh.example` | `gate_run_configured API_CMD api` |
| T5-D12-28 | Gate trace und Kriterien-Volltext | belegt | `orchestrator/gates.d/70-trace.sh.example` | `alle Kriterien sind wörtlich und beidseitig verknüpft` |
| T5-D12-29 | Gate bench | belegt | `orchestrator/gates.d/80-bench.sh.example` | `gate_run_configured BENCH_CMD bench` |
| T5-D12-30 | Gate e2e | belegt | `orchestrator/gates.d/81-e2e.sh.example` | `gate_run_configured E2E_CMD e2e` |
| T5-D12-31 | Gate territory | verhalten | `tests/template/test-t7-integrity.sh` | `territory-enforcement` |
| T5-D12-32 | Gate assets mit Manifestprüfung | belegt | `orchestrator/gates.d/83-assets.sh.example` | `gate_run_configured ASSETS_CMD assets` |
| T5-D12-33 | Gate shots und sichtbare Artefakte | belegt | `orchestrator/gates.d/84-shots.sh.example` | `gate_run_configured SHOTS_CMD shots` |
| T5-D12-34 | Gate mutgate | belegt | `orchestrator/gates.d/86-mutgate.sh.example` | `Mutation-Ratchet v2` |
| T5-D12-35 | Golden-/Ankeränderung nur mit ADR | belegt | `orchestrator/gates.d/87-golden-adr.sh.example` | `Golden-/Ankeränderung ohne ADR` |
| T5-D12-36 | Gates sind für Modelle read-only | belegt | `contracts/PROTOCOLS.md` | `Modelle lesen, aber schreiben diese Dateien nie.` |
| T5-D12-37 | Lineare Historie und unveränderliche Tags | belegt | `orchestrator/orchestrate.sh` | `Tags werden nie verschoben.` |
| T5-D12-38 | Sauberer Baum vor Lauf | belegt | `orchestrator/orchestrate.sh` | `Arbeitsbaum vor Lauf nicht sauber` |
| T5-D12-39 | reference und Anker sind Builder-read-only | belegt | `AGENTS.md` | `reference/anchors/**` |
| T5-D12-40 | Gefährliche Bypass-Flags verboten | verhalten | `tests/template/test-t7-integrity.sh` | `flag-ban` |
| T5-D12-41 | Reale Sandbox-/Permission-Modi werden geprüft | verhalten | `tests/template/test-t7-integrity.sh` | `sandbox-guard` |
| T5-D12-42 | Phasen-Timeout | belegt | `orchestrator/orchestrate.sh` | `timeout "$PHASE_TIMEOUT"` |
| T5-D12-43 | Runden- und Meilensteinlimits | belegt | `config.env.example` | `MAX_MS_PER_RUN=` |
| T5-D12-44 | STOP zwischen Phasen | belegt | `orchestrator/orchestrate.sh` | `STOP-Datei gefunden` |
| T5-D12-45 | Vollständige Modelllogs und Promptarchiv | belegt | `contracts/PROTOCOLS.md` | `Jeder Modellversuch erzeugt eindeutig` |
| T5-D12-46 | PREFLIGHT prüft echte CLI-Hilfe und Flags | belegt | `orchestrator/orchestrate.sh` | `reales --help-Kommando fehlgeschlagen` |
| T5-D12-47 | Frische Sessions und Resume-Verbot | belegt | `orchestrator/orchestrate.sh` | `Resume-/Session-Flags sind verboten` |
| T5-D12-48 | Gedächtnis liegt in versionierten Dateien | belegt | `contracts/PROTOCOLS.md` | `Jeder Meilenstein läuft in frischen Sessions` |
| T5-D12-49 | Kontextmanifest je Prompt | belegt | `orchestrator/prompts/50-code-review.md` | `Kontextmanifest:` |
| T5-D12-50 | Review liest Diff seit plan-Tag | belegt | `orchestrator/prompts/50-code-review.md` | `den Diff seit plan/{{MS}}` |
| T5-D12-51 | Handoff je Meilenstein isoliert | belegt | `orchestrator/orchestrate.sh` | `mkdir -p "$ORCH/handoff/$ms"` |
| T5-D12-52 | Idempotente Wiederaufnahme per Marker | belegt | `contracts/PROTOCOLS.md` | `Wiederaufnahme idempotent.` |
| T5-D12-53 | STATUS-Board nach Phasen | belegt | `orchestrator/orchestrate.sh` | `refresh_status` |
| T5-D12-54 | Zustand pro Meilenstein | belegt | `contracts/PROTOCOLS.md` | `orchestrator/state/<MS>/*.done` |
| T5-D12-55 | Maschinenstatus Vertrag v1 | belegt | `orchestrator/status.sh` | `{contract:1,project:$project` |
| T5-D12-56 | Ziel-Meilenstein oder gesamter Lauf | belegt | `orchestrator/orchestrate.sh` | `unbekannter Ziel-Meilenstein` |
| T5-D12-57 | Anti-Halluzination: Differentialorakel oder orakelfreie Tests | belegt | `IMPLEMENTATION-RULES.md` | `Existiert ein Original, wird differentiell dagegen getestet.` |
| T5-D12-58 | Anti-Halluzination: Anker statt Modellgedächtnis | belegt | `IMPLEMENTATION-RULES.md` | `Empirische Werte kommen aus` |
| T5-D12-59 | Anti-Halluzination: Kriterien-Traceability | belegt | `orchestrator/gates.d/70-trace.sh.example` | `Zitat nicht wörtlich in Quelle` |
| T5-D12-60 | Anti-Halluzination: unabhängige Mini-Referenz | belegt | `IMPLEMENTATION-RULES.md` | `Mini-Referenzimplementierung.` |
| T5-D12-61 | Anti-Halluzination: Metamorphie, Properties, Erhaltung | belegt | `IMPLEMENTATION-RULES.md` | `metamorphe Relationen, Property-Tests und Erhaltungssätze` |
| T5-D12-62 | Anti-Halluzination: Compiler, frozen deps und smoke | belegt | `IMPLEMENTATION-RULES.md` | `Installationen erfolgen nur im Frozen-/Locked-Modus.` |
| T5-D12-63 | Anti-Halluzination: Provenienz in Gates | belegt | `orchestrator/verifier.sh` | `toolchain:$toolchain` |
| T5-D12-64 | Anti-Halluzination: dritte Red-Team-Rolle | belegt | `AGENTS.md` | `### QA / Red Team` |
| T5-PATCH-01 | Patch v2: Transport-Retry für alle Rollen | belegt | `orchestrator/orchestrate.sh` | `transport_error() {` |
| T5-PATCH-02 | Patch v2: exponentielles Backoff ohne Rundenverbrauch | belegt | `orchestrator/orchestrate.sh` | `keine Runde verbraucht` |
| T5-PATCH-03 | Patch v2: genau ein Territoriums-Retry | belegt | `orchestrator/orchestrate.sh` | `genau ein Retry mit Hinweis` |
| T5-PATCH-04 | Patch v2: Lock und verwaiste Locks | verhalten | `tests/template/test-t4-ops.sh` | `lock-orphan` |
| T5-PATCH-05 | Patch v2: Notify-Ereignisse | belegt | `orchestrator/notify.sh` | `case "$EVENT" in` |
| T5-PATCH-06 | Patch v2: Rebuild ab konfigurierter Runde | belegt | `orchestrator/orchestrate.sh` | `rebuild_reset() {` |
| T5-PATCH-07 | Patch v2: Arbiter mit einmaliger Direktive | belegt | `orchestrator/orchestrate.sh` | `arbiter-granted` |
| T5-PATCH-08 | Patch v2: Park und Continue mit Exit 3 | belegt | `orchestrator/orchestrate.sh` | `Lauf prüft weitere freie Meilensteine` |
| T5-PATCH-09 | Patch v2: Meilenstein-Graph und Vorgänger-Fallback | belegt | `orchestrator/orchestrate.sh` | `deps_met() {` |
| T5-PATCH-10 | Patch v2: inaktive Pflicht-QA parkt ohne Runde | verhalten | `tests/template/test-t6-qa-autonomy.sh` | `qa-park` |
| T5-PATCH-11 | Patch v2: Findings mit ref und INFRA/QA-PENDING | belegt | `orchestrator/handoff/SCHEMA.md` | `[INFRA]` |
| T5-PATCH-12 | Patch v2: Mutgate-Tod vor Mutation ist error | belegt | `orchestrator/gates.d/86-mutgate.sh.example` | `Werkzeug starb vor der Mutation` |
| T5-PATCH-13 | Patch v2: Mutation-Ratchet, Floor und Toleranz | belegt | `orchestrator/gates.d/86-mutgate.sh.example` | `MUT_RATCHET_TOL` |
| T5-PATCH-14 | Patch v2: Äquivalenz nur nach Reviewer-Approval | belegt | `orchestrator/gates.d/86-mutgate.sh.example` | `MUT-EQUIV-APPROVED.json` |
| T5-PATCH-15 | Patch v2: LESSONS-Lesepfad und CONFIG-Provenienz | belegt | `tests/template/test-t5-inventory.py` | `T5-PATCH-15` |
| T5-D14-01 | docs/14 V0: reproduzierbarer Zufall und Replay | belegt | `IMPLEMENTATION-RULES.md` | `Zufall ist injiziert, geseedet und reproduzierbar` |
| T5-D14-02 | docs/14 V1: projektspezifische IDB-Logsenke | bewusst weggelassen | — | Eine Browser-IDB-Senke ist Demiurg-Produktcode, keine Harness-Mechanik; das Projektierungsverfahren muss sie bei entsprechender Spec als Nutzlast einplanen. |
| T5-D14-03 | docs/14 V2: Invarianten und Identitäten | belegt | `IMPLEMENTATION-RULES.md` | `Kerninvarianten scheitern früh` |
| T5-D14-04 | docs/14 V3/V4: Orakel-Korridor und Nullwirkungs-Sweep | belegt | `IMPLEMENTATION-RULES.md` | `metamorphe Relationen, Property-Tests und Erhaltungssätze` |
| T5-D14-05 | docs/14 V5: projektspezifischer Voll-Dump | bewusst weggelassen | — | Snapshot-Felder, Browser-Speicher und Exportbudgets sind Domänenvertrag und werden nicht ohne freigegebene Projektspezifikation in das Harness eingebaut. |
| T5-D14-06 | docs/14 V6/V7: Zwillingslauf und Schatten-Worker | bewusst weggelassen | — | Diese Simulationsfunktionen gehören in Produktcode; das Template stellt dafür Trace-, Bench-, E2E- und Property-Gates sowie Projektierung bereit. |
| T5-D14-07 | docs/14: Anker-, ADR-, Smoke- und Bench-Integrität | belegt | `orchestrator/gates.d/87-golden-adr.sh.example` | `Änderung und ADR liegen im selben Meilenstein` |
| T5-NEW-01 | BAUPLAN neu: Gate-Steckplätze mit Exit 0/1/2 | belegt | `orchestrator/verifier.sh` | `Exit-Code %s (erlaubt: 0/1/2)` |
| T5-NEW-02 | BAUPLAN neu: summary.json Vertrag v1 | belegt | `orchestrator/status.sh` | `SUMMARY_TMP=` |
| T5-NEW-03 | BAUPLAN neu: deklarierte Laufzeiten und Versionen | belegt | `orchestrator/lib/toolchain.sh` | `runtime_ok() {` |
| T5-NEW-04 | BAUPLAN neu: eingefrorene Manifeste | belegt | `orchestrator/lib/toolchain.sh` | `installiere frozen aus` |
| T5-NEW-05 | BAUPLAN neu: idempotenter Update-Pfad | belegt | `bootstrap.sh` | `--update` |
| T5-NEW-06 | BAUPLAN neu: Umgebungen außerhalb des Arbeitsbaums | belegt | `bootstrap.sh` | `MCP_ENV_DIR muss außerhalb des Repos liegen` |
| T5-NEW-07 | BAUPLAN neu: Projektierung fragt Lücken statt zu raten | belegt | `projektierung/PROJEKTIERUNG.md` | `Lücken → gesammelte Rückfragen, STOPP` |
| T5-NEW-08 | BAUPLAN neu: Typ-Presets und echtes Referenzbeispiel | belegt | `projektierung/beispiel/README.md` | `Messlatte` |
| T5-NEW-09 | BAUPLAN neu: generischer MCP-Connector aus Umgebungswerten | verhalten | `orchestrator/mcp/tests/test_allowlist.py` | `mcp-allowlist` |

## Ergebnisregel

T‑5 ist nur bestanden, wenn das Prüfskript alle Soll-IDs exakt wiederfindet,
jeder `belegt`-Anker trägt, jede Weglassung begründet ist und jeder
`verhalten`-Schlüssel aus einem im selben Suitelauf erfolgreich ausgeführten
Test stammt. Die Ausgabe wird mit der übrigen Suite in
`docs/template/ABNAHME.md` festgehalten.
