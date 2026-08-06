# Wiederabnahme — Befund-Nachprüfung nach REWORK-AUFTRAG 1

Prüfstand: `/tmp/harness-wiederabnahme.X3JaX1/repo`, HEAD `07ea75c`
(„test(evidence): make T-5 source-backed and behavioral"), Linux
6.6.87.2-microsoft-standard-WSL2, bash 5.3.9(1), jq 1.8.1, git 2.53.0,
Python 3.14.4.

Die Prüfung selbst lief vollständig lesend: Nach Abschluss aller Kommandos war
`git status --porcelain --untracked-files=all` leer, HEAD unverändert bei
`07ea75c`, `git worktree list` zeigte nur das Hauptverzeichnis. Einzige
nachträgliche Änderung am Repo ist diese Berichtsdatei, auf ausdrückliche
Anweisung des Betreibers hier abgelegt.

Hinweis zu den Pfaden: Die im Auftrag genannten `docs/abnahme/…` und
`docs/ABNAHME.md` liegen nach E7 unter `docs/template/…`. Alle Repros wurden
gegen die verschobenen Pfade gefahren.

---

## 1. Gesamturteil: **PASS MIT BEFUNDEN**

Der Rework ist belastbar abgeschlossen. Alle 24 Befunde aus Lauf 1 und alle 5
aus Lauf 2 sind behoben — nachgewiesen durch eigene, neu gebaute Repro-Fälle,
nicht durch Nachfahren der mitgelieferten Suite. Zu jedem Befund existiert ein
benannter Negativtest, und die Rot-Probe belegt an sechs Testpaketen, dass
diese Tests gegen den Vor-Rework-Stand `865840e` tatsächlich rot sind.

Zwei Einschränkungen halten das Urteil von einem glatten PASS ab:

- **N-1 (MITTEL–HOCH, neu):** Der MCP-Connector gibt `orchestrator/secrets.env`
  und `orchestrator/config.env` weiterhin heraus — über `tail -n N <symlink>`.
  Der in R1 verlangte `pruefe_pfad()`-Durchlauf wurde nur für `grep`
  implementiert; `tail`, `wc -l` und `git diff` prüfen ihr Pfadargument nur als
  Zeichenkette. Das ist exakt die Fehlerklasse von L2-B-01, an einem anderen
  Allowlist-Eintrag. Der Buchstabe von R1 ist erfüllt, das Schutzziel von E8
  („Geheimnisse verlassen die Maschine nicht") nicht.
- **N-2 (NIEDRIG, neu):** Eine Teil-Assertion in `test-t4-ops.sh` unterscheidet
  Alt- und Neustand nicht.

Beide sind Restlücken, keine Regressionen: N-1 existierte im Altstand ebenso.

---

## 2. Befund-für-Befund

Legende: BEHOBEN = altes Fehlverhalten nachweislich weg und Verhalten
entspricht E1–E8. Alle Kommandos in eigenen `/tmp`-Fällen, materialisiert mit
einem selbst geschriebenen `mkcase.sh` (`git ls-files` des Templates +
Fixture-Config/Manifest/Gates + eigenes Git-Repo).

| ID | Urteil | Ausgeführtes Kommando | Kernauszug | Exit | Negativtest |
|---|---|---|---|---|---|
| **B-01** | BEHOBEN | Fall ohne git-Identität, `GIT_CONFIG_GLOBAL=/dev/null … orchestrate.sh M0` | `FATAL: git user.name fehlt; vor dem Lauf mit 'git config user.name <Name>' setzen.` · 0 Commits, 0 Tags, kein `state/M0` | **2** | `test-t7-integrity.sh` (IDENT_REPO, BOOTSTRAP_REPO) |
| B-01b | BEHOBEN | `env -i … bootstrap.sh --non-interactive --no-start` ohne Identität | `bootstrap: FATAL: git user.name fehlt` | **2** | dito |
| B-01c | BEHOBEN | `-e`-Suppression: `.git/hooks/pre-commit` → `exit 1`, dann `orchestrate.sh M0` | `FATAL: Phasen-Commit fehlgeschlagen: orch(M0): reviewer 10-acceptance r1`; kein `8-done.done` | **2** | `test-t2-rework.sh` |
| B-01d | BEHOBEN | Positivfall `orchestrate.sh` | 20 Commits, Tags `done/M0 done/M1 plan/M0 plan/M1` | **0** | `test-t2-rework.sh` |
| **B-02** | BEHOBEN | Eigener Builder schreibt `reports/ dist/ artifacts/ coverage/`, `orchestrator/logs/M0-40-build-r1-TAMPERED.log`, `orchestrator/.lock/stray` und fälscht das Promptarchiv | `WARN: builder verletzt Territorium: orchestrator/logs/** (Hash-Manifest) — genau ein Retry`; dann `FATAL: … wiederholt: orchestrator/.lock/stray`; alle sechs Dateien entfernt, keine Fälschung überlebt | **2** | `test-t7-integrity.sh` (HIDDEN_REPO, TAMPER_REPO) |
| **B-03** | BEHOBEN | `rm orchestrator/prompts/10-acceptance.md && git commit -qam …; orchestrate.sh` | `FATAL: Vertragspfad fehlt: orchestrator/prompts/10-acceptance.md`; kein `8-done.done` | **2** | `test-t7-integrity.sh` (MISSING_REPO) |
| **B-04** | BEHOBEN | `AUTONOMY_LEVEL=0`, 7 aufeinanderfolgende `orchestrate.sh` | `10-acceptance · 20-plan · 30-plan-review · 30-plan-approved · 40-build · gates · 50-code-review` — 7 Aufrufe, 7 verschiedene Phasen; Marker `plan-r1-planned.done`, `plan-r1-reviewed.done` | 7× **0** | `test-t6-qa-autonomy.sh` (LEVEL0_REPO, 8 Aufrufe) |
| **B-05** | BEHOBEN | Eigenes Gate `exit 2` dauerhaft + Reviewer-Verdict PASS | `Infrastruktur-Wiederholung 1/2 … 2/2 in Runde 1; keine Runde verbraucht` → `PARKED M0: Infrastruktur (Gate error) nach 2 Wiederholungen in Runde 1.` · keine `round`-Datei, keine `rework-r*`/`rebuild`-Marker, `{"phase":"parked","round":1,"exit":3,"needs_human":true}` | **3** | `test-t8-gates.sh` (ERROR_REPO) |
| **B-06** | BEHOBEN | Zyklus-Manifest M0↔M1, `orchestrate.sh` | `FATAL: Meilensteinmanifest enthält einen deps-Zyklus.` · summary `phase=fatal exit=2 needs_human=true` · notify `fatal` | **2** | `test-t7-integrity.sh` (CYCLE_REPO) |
| **B-07** | BEHOBEN | `orchestrate.sh M1` bei offenem M0 | `M1 wartet auf: M0` → `FATAL: M1 kann nicht gestartet werden; offene Abhängigkeiten: M0` · notify `fatal` | **2** | `test-t7-integrity.sh` (DEPS_REPO) |
| **B-08** | BEHOBEN | `TUNNEL_TOKEN`/`ANTHROPIC_API_KEY`/`NOTIFY_TOKEN` in `config.env`, Geheimnisse in `secrets.env`, zusätzlich in der Elternumgebung; Modell gibt `env` aus | Modellumgebung vollständig: `ACCEPTANCE_* HOME LANG PATH PROMPT_FILE PWD SHLVL _` — kein Geheimnistreffer, auch nicht in den Logs | **0** | `test-t7-integrity.sh` (`ACCEPTANCE_ENV_CAPTURE`), `test-t1-bootstrap.sh` (`secrets=isolated`) |
| B-08b | BEHOBEN | `BUILDER_ENV_ALLOWLIST='… TUNNEL_TOKEN'` | `FATAL: builder-ENV_ALLOWLIST darf keine Geheimnisvariable enthalten: TUNNEL_TOKEN` | **2** | dito |
| **B-09** | BEHOBEN | Reviewer legt `stilbibel.md` an — (a) ohne Hook, (b) mit `REVIEWER_EXTRA_PATHS_REGEX` | (a) `FATAL: reviewer verletzt Territorium wiederholt: stilbibel.md` · (b) keine Meldung, Datei vorhanden und committet | (a) **2** (b) **0** | `test-t7-integrity.sh` (PRESET_REPO) |
| **B-10** | BEHOBEN | `python3 tests/template/test-t5-inventory.py` + drei Rot-Proben | Sollliste liegt versioniert in `docs/template/T5-SOLL.md`; Prüfskript vergleicht exakt. Rot-Proben: fehlender Verhaltensschlüssel → `FAIL T5-D12-31: Verhalten nicht erfolgreich ausgeführt`; erweiterter Soll-Bereich → `FAIL Soll-IDs fehlen: T5-D12-65…70`; verfälschter Anker → `FAIL T5-ORCH-01: Suchanker fehlt` | **0** / 3× **1** | `test-t5-behavior.sh`, `test-t5-inventory.py` |
| **B-11** | BEHOBEN | `qa_required` gegen 5 ID-Formen × 3 Grenzen (`setup`, `kapitel-eins`, `M3`, `M08`, `MV1`) | 15/15 sauber rc 0/1, kein `integer expected`; Reihenfolge folgt dem Manifest-Index | **0** | `test-t6-qa-autonomy.sh`, `test-t7-integrity.sh` (QA_BOUND_REPO) |
| **B-12** | BEHOBEN | Territoriums- und Transport-Retry im B-02-Fall | `M0-40-build-r1-a1-*.log` **und** `-a2-*.log`; `M0-20-plan-r1-a1/-a2` — beide Versuche erhalten | **2** | `test-t7-integrity.sh` (`attempt-logs=2`), `test-t2-rework.sh` |
| **B-13** | BEHOBEN | `diff` aller PASS-Zeilen aus `docs/template/ABNAHME.md` gegen den heutigen Suitelauf | identisch, inkl. `T-1 PASS: … secrets=isolated tunnel=0` (früher fehlte `tunnel=`) | **0** | `run-all.sh`; Output in `docs/template/ABNAHME.md` |
| **B-14** | NICHT GEPRÜFT (Auftrag Regel 4) | `git log --oneline --all` | `865840e` unverändert vorhanden, Historie nicht umgeschrieben; Begründung steht in `REWORK-1-NACHWEIS.md:25` | **0** | — (bewusst keiner) |
| **B-15** | BEHOBEN | leeres `BUILDER_SAFE_MODE_PATTERN`; leeres `BUILDER_REQUIRED_FLAGS` | `FATAL: BUILDER-SAFE_MODE_PATTERN ist leer; nur ROLE_GUARDS=off darf Rollenwächter abschalten.` / analog `REQUIRED_FLAGS` | je **2** | `test-t7-integrity.sh` (EMPTY_GUARD_REPO, GUARDS_OFF_REPO) |
| **B-16** | BEHOBEN | `82-territory.sh.example` mit (a) gültigem Marker (b) falscher Runde (c) falscher Basis-SHA (d) veraltetem Marker nach weiterer Phase | (a) `territory: letzter Diff sauber` (b) `Audit stammt aus Runde 2 statt 1` (c)+(d) `Audit-Basis … passt nicht zur Modellphase` | (a) **0**, (b–d) **1** | `test-t8-gates.sh` (TERRITORY_REPO) |
| **B-17** | BEHOBEN | (a) `mkdir orchestrator/.lock; orchestrate.sh M0` (b) Lock mit Fremdinhalt (c) **6 gleichzeitige Starts** | (a) atomar übernommen (b) `FATAL: verwaister Lock enthält Fremdinhalt: … Aufräumen: PID prüfen, dann gezielt … entfernen.` (c) genau 1× Exit 0, 5× `FATAL: Orchestrator läuft bereits (PID …)`, keine Doppelarbeit | (a) **0** (b) **2** (c) **0/2×5** | `test-t4-ops.sh` (foreign-lock), `test-t7-integrity.sh` |
| **B-18** | BEHOBEN | `criteriaRef` mit `\|`, mit `&`, mit `#` (dem heutigen sed-Delimiter) | je `FATAL: Meilensteinmanifest verletzt contracts/PROTOCOLS.md §2.` — kein leerer Prompt, kein sed-Fehler | je **2** | `test-t7-integrity.sh` (CRITERIA_REPO) |
| **B-19** | BEHOBEN | `grep -n 'tolerance\|source_url\|retrieved\|harvested' projektierung/beispiel/README.md` | „…`harvested`, einen Repo-Pfad als `source_url` und kein `tolerance`. Neue Anker … mit `retrieved`, echter Quellen-URL und Toleranz" | **0** | `test-t5-inventory.py` (`cross-file=PASS`) |
| **B-20** | BEHOBEN | `status.sh '' parked` und `status.sh '' done` | `{"ms":"","phase":"parked","needs_human":true}` / `…"done","needs_human":false}`; `status.sh:85` geklammert als `[ A ] \|\| { [ B ] && [ C ]; }` | **0** | `test-t4-ops.sh` (`status-precedence=parked`) |
| **B-21** | BEHOBEN | `ls docs/`, Existenzprobe alter Pfade, `grep dependency-cruiser orchestrate.sh` | `docs/` enthält nur `00-vision.md.template`, `decisions`, `template`; alte drei Pfade weg; README:38 „Zielprojekte dürfen diesen gesamten Ordner löschen"; `.dependency-cruiser` nicht mehr in `orchestrate.sh`, stattdessen `REVIEWER_EXTRA_PATHS_REGEX` im Preset `software-ts` | **0** | `test-t5-inventory.py`, `test-t7-integrity.sh` |
| **B-22** | BEHOBEN | Mitgelieferte Beispiel-Gates selbst gefahren: `86-mutgate` (pass/ratchet-fail/error), `70-trace` (+ eigene Gegenprobe mit verfälschtem Zitat), `87-golden-adr` (ohne/mit ADR) | `mutgate: pass (score=100 …)` rc 0 · `mutgate: fail (score=25.00 required=88.00 …)` rc 1 · `Werkzeug starb vor der Mutation (rc=127 …)` rc 2 · `trace: alle Kriterien … verknüpft` rc 0 / `Kriterien/Test-Zuordnung unvollständig` rc 1 · `golden-adr: … ohne ADR` rc 1 / `… im selben Meilenstein` rc 0 | s. Auszug | `test-t8-gates.sh` |
| **B-23** | BEHOBEN | T6-Fall mit aktiver QA, IDs `setup`/`kapitel` | beide MS: `5b-qa.done`, `qa-r1.done`, ausführbares `tests/e2e/<ms>-qa.sh`, gefüllte `handoff/<ms>/QA.md`, `8-done.done` | **0** | `test-t6-qa-autonomy.sh` (ACTIVE_REPO) |
| **B-24** | BEHOBEN | Gate `exit 5` / `exit 127` / `exit 5` mit `GATE_ERROR_CODES='5'` | `gate rc5: fail — … fachlicher Fehlschlag rc=5`, `{"result":"fail"}` · rc 127 → `{"result":"error"}` · überschriebene Codes → `{"result":"error"}` | **1** / **2** / **2** | `test-t8-gates.sh` (RC5_REPO) |
| **L2-B-01** | BEHOBEN (Restlücke → N-1) | 10 Connector-Proben gegen Fixture mit Attrappen-Key, u. a. `befehl('grep -rn API orchestrator')` | `abgelehnt: rekursiver grep-Pfad nicht in der Verzeichnis-Allowlist`; `grep -rn API .` → `kein Allowlist-Treffer`; `lies`/`git diff`/`tail` auf `config.env` abgelehnt; **0 Leaks** | **0** | `orchestrator/mcp/tests/test_allowlist.py` (2 neue Fälle, 63/63) |
| **L2-B-02** | BEHOBEN | Eigener Builder schreibt ausschließlich `orchestrator/.lock/stray` | `WARN: builder verletzt Territorium: orchestrator/.lock/stray — genau ein Retry`; Datei entfernt; Lauf erreicht DONE; **Folgestart läuft normal** (`Alle Meilensteine … abgeschlossen`) | **0**, Folgestart **0** | `test-t7-integrity.sh` (HIDDEN_REPO) |
| **L2-B-03** | BEHOBEN | `BUILDER_CMD='… $BUILDER_EXTRA_FLAGS'` mit `BUILDER_EXTRA_FLAGS=--dangerously-skip-permissions`; Gegenprobe mit literalem Flag | `FATAL: BUILDER-CMD enthält eine nicht erlaubte $-Referenz; nur $PROMPT_FILE ist zulässig.` — `argv.log` leer, Rolle nie gestartet · literal: `FATAL: gefährlicher Bypass-/Full-Access-Modus …` | je **2** | `test-t7-integrity.sh` (FLAG_REPO) |
| **L2-B-04** | BEHOBEN | Hängender Lauf (lebender PID im Lock, Heartbeat 2000-01-01), Watchdog → Doppelstart → Watchdog | A) `watchdog: STALE age=1053315200s` rc 1 · B) `FATAL: Orchestrator läuft bereits (PID …)` rc 2, `summary.json` **byte-identisch**, Notify unverändert (`stale`) · C) `watchdog: STALE …` rc 1 | **1 / 2 / 1** | `test-t4-ops.sh` (`double-start=isolated`) |
| **L2-B-05** | BEHOBEN | Eigenes Manifest mit IDs `setup`/`kapitel`, `QA_ENABLED=0`, `QA_REQUIRED_FROM=setup` | `PARKED setup: QA-Route inaktiv, aber QA ist ab setup Pflicht; keine Rework-Runde wird verbraucht.` · kein `round`, kein `rework-r*`, kein `8-done.done`, **0×** `integer expected` | **3** | `test-t6-qa-autonomy.sh` (PARK_REPO) |
| **L2-N-01** | BEHOBEN | `grep -c Kontextmanifest` über alle 9 Prompts | 9×1 (vorher `70-arbiter.md` = 0) | **0** | `test-t5-inventory.py` (`validate_cross_file_rework`) |
| **L2-N-02** | BEHOBEN | `test-t5-inventory.py::validate_patch_15` gelesen und ausgeführt | prüft beide Hälften: `CONFIG: AUTONOMY=` in `orchestrate.sh` **und** `orchestrator/LESSONS.md` in allen sechs Prompts (je 1 Treffer bestätigt) | **0** | `test-t5-inventory.py` |

### Zusätzlich geprüfte E-Entscheidungen

- **E1 Gegenprobe:** Gate-Menge mit einem `fail` **und** einem `error` →
  `{"result":"fail","gates":{"product":"fail","behavior":"error"}}`, verifier
  Exit 1. „`error` zusammen mit `fail` verhält sich wie bisher fail" ist erfüllt.
- **E8 Gegenprobe:** Modell überschreibt `orchestrator/secrets.env` →
  `WARN … verletzt Territorium: orchestrator/secrets.env` → `FATAL … wiederholt`,
  Exit 2, Originalinhalt wiederhergestellt. `secrets.env` wird nirgends in
  `run_model` gesourct (`grep` findet es nur in `rollback_attempt` und
  `snapshot_worktree`); `bootstrap.sh` setzt `chmod 600` und lehnt Geheimnisse
  in `config.env` ab (`… gehört in orchestrator/secrets.env`).

---

## 3. Rot-Probe gegen `865840e`

`git worktree add /tmp/altstand 865840e` → detached HEAD `865840e`
(`orchestrate.sh` 792 statt 1121 Zeilen, `server.py` 479 statt 515). In den
Altstand kopiert wurden ausschließlich **Testinfrastruktur** (das neue
`tests/template/`, das neue `test_allowlist.py`, `artifact-paths.allowlist`,
`docs/template/`) — keine Korrekturen an `orchestrate.sh`, `server.py`,
`status.sh`, `verifier.sh`, `bootstrap.sh` oder `_lib.sh`.

### 3a. Neue Tests gegen den Altstand — alle rot

| Test | Altstand | Neustand | Erste scheiternde Assertion im Altstand |
|---|---|---|---|
| `orchestrator/mcp/tests/test_allowlist.py` (L2-B-01) | **1** — `test_allowlist: 61/63 OK` | 0 — 63/63 | `FAIL rekursiver grep auf orchestrator-Wurzel gibt config.env nicht heraus` · `FAIL rekursiver grep erzwingt --exclude=*.env` |
| `tests/template/test-t7-integrity.sh` (L2-B-02, L2-B-03, B-02/03/06/07/08/12/15/18) | **1** | 0 | `+ '[' 2 = 0 ']'` |
| `tests/template/test-t4-ops.sh` (L2-B-04, B-17, B-20) | **1** | 0 | `+ cmp -s summary-before-double-start.json orchestrator/state/summary.json` |
| `tests/template/test-t6-qa-autonomy.sh` (L2-B-05, B-04, B-11, B-23) | **1** | 0 | `+ test -f orchestrator/state/setup/qa-r1.done` |
| `tests/template/test-t8-gates.sh` (B-05, B-16, B-22, B-24) | **1** | 0 | `+ grep -F 'Infrastruktur (Gate error)' orchestrator/state/M0/parked` |
| `tests/template/test-t5-behavior.sh` | **1** | 0 | scheitert über `test_allowlist` |
| `tests/template/test-t5-inventory.py` (B-10, B-19, B-21, L2-N-01/02) | **1** — `failures=16` | 0 | `FAIL B-21: alter Template-Dokumentpfad existiert weiter: docs/BAUPLAN.md` |
| `tests/template/test-t1-bootstrap.sh` | **1** | 0 | — |
| `tests/template/test-t2-rework.sh` | **1** | 0 | — |
| `tests/template/test-t3-ladder.sh` | **0** | 0 | *kein neuer Negativtest* — `git diff 865840e..HEAD -- tests/template/test-t3-ladder.sh` ist leer; T-3 ist der unveränderte Alt-Regressionstest für Leiter/Arbiter und soll auf beiden Ständen grün sein. |

### 3b. Direkte Reproduktion des alten Fehlverhaltens im Altstand

Weil T-7 im Altstand schon an `[ "$LAST_RC" = 0 ]` stirbt (das alte
`.gitignore` kennt `orchestrator/secrets.env` nicht → „Arbeitsbaum nicht
sauber"), habe ich den Fall dort zusätzlich von Hand gefahren, mit
committeter `secrets.env`. Ergebnis Exit **0** — und die inhaltlichen
T-7-Assertions sind sämtlich verletzt:

```
grep 'builder verletzt Territorium: orchestrator/.lock/stray'  0 Treffer (Soll: >=1)
test ! -e orchestrator/.lock/stray                             VERLETZT
test ! -e reports/evil.txt                                     VERLETZT
! grep -Eq 'TUNNEL_TOKEN|OPENAI_API_KEY' src/model-env.txt     VERLETZT
zwei Versuchslogs M0-40-build-r1-a*                            0 (Soll: 2)
   src/model-env.txt enthält: OPENAI_API_KEY=sk-parent-fixture-LEAK
                              TUNNEL_TOKEN=parent-fixture-LEAK
```

**L2-B-01 am alten `server.py`:**

```
--- befehl('grep -rn API orchestrator')
    Exit-Code: 0 | orchestrator/config.env:1:OPENROUTER_API_KEY=sk-or-v1-DEADBEEFsecret123
    LEAK=True
```
(die drei anderen Wege werden auch dort abgelehnt — genau das Bild aus Lauf 2)

**L2-B-02 am alten `orchestrate.sh`** (eigener Builder, nur `.lock/stray`):

```
RUN1_EXIT=0     Territoriumsmeldungen zu .lock: 0
stray ueberlebt? JA — "model wrote operator territory"
git status --porcelain --untracked-files=all:  M orchestrator/state/summary.json
RUN2_EXIT=2     FATAL: verwaister Lock ist nicht leer: …/orchestrator/.lock
RUN3_EXIT=2     FATAL: verwaister Lock ist nicht leer: …/orchestrator/.lock   (heilt nicht)
```

**L2-B-03 am alten `orchestrate.sh`:**

```
ORCH_EXIT=0
ARGV: builder --fixture-safe --dangerously-skip-permissions
```

**L2-B-05 am alten `orchestrate.sh`:**

```
orchestrator/orchestrate.sh: line 492: [: setup: integer expected
=== setup DONE ===
orchestrator/orchestrate.sh: line 492: [: kapitel-eins: integer expected
=== kapitel-eins DONE ===
ORCH_EXIT=0     geparkt? NEIN
```

**B-05 am alten `orchestrate.sh`:**

```
RUN builder 60-rework (M0 r2) … r3 … REBUILD M0 … 62-rebuild (M0 r4)
PARKED M0: Codepfad festgefahren (Gates rc=2, Verdict=PASS); Arbiter benötigt HUMAN.
Runde: 4     ORCH_EXIT=3
```

**L2-B-04 am alten `orchestrate.sh`:** Doppelstart Exit 2, `summary.json`
überschrieben auf `{"phase":"fatal","needs_human":true,"exit":2,"ts":"2026-08-06T10:40:40+02:00"}`,
Notify `stale,fatal`.

Danach `git worktree remove --force /tmp/altstand` → `git worktree list` zeigt
nur noch das Hauptverzeichnis.

---

## 4. Geheimnis-Historie (Schritt 4)

```
$ git log --all --full-history -- orchestrator/secrets.env
(leer)                                                        Exit 0

$ git log --all --name-only --pretty=format:'%h %s' -- '*.env'
bcf2278 …   tests/template/fixtures/config-t2.env, config-t3.env   (Löschung)
865840e …   tests/template/fixtures/config-t2.env, config-t3.env   (Anlage)
```

Beide sind Testfixtures ohne echte Schlüssel; der einzige URL-artige Wert ist
`NOTIFY_URL=https://notify.invalid/acceptance`. `config.env.example` ist die
einzige weitere je committete env-artige Datei.

Zusätzliche Gegenprobe über **alle 282 Objekte der gesamten Historie**
(`git cat-file --batch-all-objects` + Regex auf `sk-…`, `sk-or-v1-`, `ghp_`,
`AKIA…`) — vier Treffer, alle nachweislich Attrappen:

- `sk-fixture-MUST-NOT-LEAK` → `test_allowlist.py` (Fixture)
- `sk-parent-fixture-LEAK` → `test-t7-integrity.sh` (Fixture)
- `GEHEIM-TUNNEL-TOKEN-123 / sk-GEHEIM-API-KEY-456` → Zitat in `abnahme-lauf1.md`
- `sk-or-v1-DEADBEEFsecret123` → Zitat in `abnahme-lauf2.md`

**Ergebnis: zu keinem Zeitpunkt wurde ein Geheimnis committet.**

---

## 5. Klarstellungs-Commit (Schritt 5)

`git show --stat 8a33684` → `docs(policy): clarify template-maintenance git
scope`, `AGENTS.md | 4 ++++`. Der Abschnitt existiert (`AGENTS.md:9-11`) und
trifft die Unterscheidung tatsächlich:

> Die Git-Verbote dieses Dokuments gelten für **Modellrollen im laufenden
> Harness-Betrieb einer Projektinstanz**. Beim **Bau und bei der Wartung des
> Harness-Templates selbst** handelt das ausführende Werkzeug als
> Betreiber-Werkzeug; dafür gelten die Vorgaben des jeweiligen Betreiber- oder
> Rework-Auftrags einschließlich ausdrücklich verlangter Commits und Pushes.

Er steht vor der Pflichtlektüre, kollidiert nicht mit „Modelle führen keine
eigenen Git-Kommandos aus" (`AGENTS.md:106`) und deckt genau den Fall ab, den
`REWORK-1-NACHWEIS.md` in seiner Kopfzeile beansprucht. **Erfüllt.**

---

## 6. Neue Befunde

### N-1 · MCP-Connector gibt `secrets.env` und `config.env` über `tail -n N <symlink>` heraus — MITTEL bis HOCH

*Verletzte Anforderung:* E8 („Geheimnisse verlassen `config.env`" — Schutzziel);
R1 („`grep`-Pfadargumente vor Ausführung durch `pruefe_pfad()`" — nach Buchstaben
erfüllt, nach Zweck nicht); L2-B-01-Korrekturempfehlung („Den Guard von der
Zeichenkette auf das Ergebnis verlagern").

*Datei/Zeile:* `orchestrator/mcp/server.py:158` (`grep_argv` ruft als einzige
Stelle `pruefe_pfad`), `:75-81` (Allowlist: `git diff … {PFAD}`, `wc -l {PFAD}`,
`tail -n N {PFAD}` nehmen ein Pfadargument), `:298-312` (`befehl()` reicht alles
außer `grep` unverändert an `bash -c`), `:142-144` (`.env`-Filter prüft nur den
Befehlsstring).

`pruefe_pfad()` löst den realpath auf und lehnt ab, wenn `.env` darin vorkommt.
`grep_argv()` nutzt das. `tail`, `wc -l` und `git diff` durchlaufen es nicht —
sie sehen nur die Zeichenkette. Ein Symlink, dessen **Name** kein `.env`
enthält, hebelt den Guard damit aus.

*Reproduzierendes Kommando* (Fixture-Repo, `REPO_PATH` gesetzt):

```text
$ ln -sfn ../orchestrator/secrets.env src/notiz
$ ln -sfn ../orchestrator/config.env  src/konfig
$ ln -sfn /etc/passwd                 src/aussen

--- befehl('tail -n 40 src/notiz')
    Exit-Code: 0 | OPENROUTER_API_KEY=sk-or-v1-SECRETSENV999      GEHEIMNIS_SICHTBAR=True
--- befehl('tail -n 40 src/konfig')
    Exit-Code: 0 | AUTONOMY_LEVEL=3 | ACCEPTANCE_SCENARIO=T2 …    GEHEIMNIS_SICHTBAR=True
--- befehl('tail -n 5 src/aussen')
    Exit-Code: 0 | systemd-resolve:x:989:989:… | _chrony:x:988:988:…   (ausserhalb des Repos)

--- befehl('grep -n API src/notiz')     abgelehnt: Pfad ausserhalb des konfigurierten Repos
--- lies('src/notiz')                   abgelehnt: Pfad ausserhalb des konfigurierten Repos
```

Drei Wege halten, der vierte liefert den Klartext — dasselbe Muster wie L2-B-01.

*Wer kann den Symlink legen?* Der Builder, ohne jede Territoriumsverletzung.
`src/**` ist Builder-Territorium (`path_allowed`, `orchestrate.sh:487`).
Ausgeführter Nachweis mit einem Builder, der in `40-build` genau diesen Symlink
anlegt:

```text
EXITCODE=0
Territoriumsmeldungen: 0
$ git ls-files -s src/notiz  →  120000 dd087ad… 0  src/notiz
$ tail -n 2 src/notiz        →  OPENROUTER_API_KEY=sk-or-v1-SYMTEST
```

*Expositionslage* unverändert wie in L2-B-01: `server.py` läuft ohne
Authentifizierung hinter einem Cloudflare-Quick-Tunnel mit öffentlicher URL.

*Kein Regress:* Der alte `server.py` (865840e) hatte weder `grep_argv` noch
einen Pfadcheck für `tail`; die Lücke bestand schon vorher und wurde vom Rework
nur nicht mit geschlossen, weil R1 den Auftrag ausdrücklich auf `grep`
beschränkt hat.

*Minimale Korrektur:* Alle Allowlist-Regeln mit `{PFAD}`-Gruppe (`git diff`,
`wc -l`, `tail -n`) vor der Ausführung durch `pruefe_pfad()` schicken —
analog zu `grep_argv` —, oder `pruefe_pfad` in `befehl()` zentral auf jedes
extrahierte Pfad-Token anwenden. Zusätzlich in `test_allowlist.py` je einen
Symlink-Fall für `tail`/`wc`/`git diff` aufnehmen.

*Offene Frage an den Betreiber:* War R1 („`grep`-Pfadargumente") als
abschließende Aufzählung gemeint oder als Beispiel für „alle Pfadargumente"?
Davon hängt ab, ob N-1 ein Nacharbeitspunkt aus Rework 1 oder ein neues Paket ist.

### N-2 · Nicht unterscheidende Teil-Assertion in `test-t4-ops.sh` — NIEDRIG

*Datei/Zeile:* `tests/template/test-t4-ops.sh:38-42`.

Nach dem abgewiesenen Doppelstart prüft der Test
`WATCHDOG_NOW_EPOCH=2000000000 bash orchestrator/watchdog.sh` → rc 1. Mit dieser
weit in der Zukunft liegenden Festuhr (2033-05-18) ist der Heartbeat auch nach
einem *Überschreiben* auf „jetzt" (2026) rund 6,8 Jahre alt. Ausgeführt gegen
den Altstand:

```text
summary unveraendert? NEIN — ueberschrieben
{"phase":"fatal","needs_human":true,"exit":2,"ts":"2026-08-06T10:40:40+02:00"}
watchdog: STALE age=213994360s pid=855379      WATCHDOG_EXIT=1
```

Der Altstand besteht diese eine Assertion also ebenfalls. **Der Test als Ganzes
bleibt rot**, weil `cmp -s` auf `summary.json` und der Notify-Zeilenvergleich
(`:36-37`) korrekt greifen — dort ist er abgesichert. Es ist eine
Beweislücke innerhalb eines sonst tragenden Tests, kein falsches Grün.

*Korrektur:* Die Uhr relativ zum Heartbeat setzen (z. B.
`WATCHDOG_NOW_EPOCH=$(( $(date -d "$(jq -r .ts …)" +%s) + 60 ))`), damit die
Assertion „Heartbeat wurde nicht verjüngt" wirklich diskriminiert.

### N-3 · Hinweis, kein Befund: Artefaktpfade sind bewusst territoriumsfrei

`orchestrator/artifact-paths.allowlist` nimmt `reports/`, `dist/`, `coverage/`,
`artifacts/`, `node_modules/`, `.pnpm-store/`, `.venv/` u. a. aus der
Territoriumsprüfung heraus (`changed_paths`, `orchestrate.sh:362-369`). Eine
Modellrolle kann dort ohne Verletzungsmeldung schreiben. Das ist genau die in
R2 vorgeschriebene Konstruktion („gefiltert gegen eine explizite, versionierte
Artefakt-Allowlist (node_modules, dist, reports, coverage, .pnpm-store,
Umgebungen)") und damit **kein Defekt**, sondern eine Betreiber-Entscheidung.
Ich nenne sie, weil `abnahme-lauf1.md` B-02 `reports/evil.txt` noch als
Verletzung geführt hat und der Unterschied sonst als stille Abweichung
erscheinen könnte. Diese Feststellung stammt aus dem Quelltext und aus dem
B-02-Lauf (in dem die Dateien nur wegen einer *anderen* Verletzung
zurückgerollt wurden); ich habe den Fall „ausschließlich `reports/evil.txt`"
nicht isoliert gefahren.

---

## 7. Vollständige Liste der ausgeführten Kommandos

| # | Kommando (gekürzt) | Exit |
|---|---|---|
| 1 | `git log --oneline -12`, `git status --short`, `git rev-parse HEAD` | 0 |
| 2 | `find . -path ./.git -prune -o -type f -print` (121 Dateien) | 0 |
| 3 | **`bash tests/template/run-all.sh`** (Basislinie) | **0** — `A6 PASS: T-1 T-2 T-3 T-4 MCP-Allowlist T-5B T-5 T-6 T-7 T-8`, stderr leer |
| 4 | `git log --all --full-history -- orchestrator/secrets.env` | 0 — leer |
| 5 | `git log --all -p -- '*.env'`, `--name-only` | 0 — nur Fixtures |
| 6 | `git cat-file --batch-all-objects \| grep -E 'sk-…\|ghp_\|AKIA'` über 282 Objekte | 0 — 4 Attrappen |
| 7 | B-01: Lauf ohne git-Identität | **2** |
| 8 | B-01b: `bootstrap.sh --non-interactive --no-start` ohne Identität | **2** |
| 9 | B-01c: `pre-commit`-Hook `exit 1`, `orchestrate.sh M0` | **2** |
| 10 | B-01d: Positivlauf, `git log \| wc -l`, `git tag --list` | **0** — 20 Commits, 4 Tags |
| 11 | B-02: eigener Builder, ignorierte Pfade + Log-/Promptfälschung | **2** |
| 12 | L2-B-02 isoliert: nur `orchestrator/.lock/stray` | **0**, Folgestart **0** |
| 13 | B-12: `ls orchestrator/logs/ \| grep 'M0-40-build-r1'` und `M0-20-plan-r1` | 0 — je `-a1` und `-a2` |
| 14 | B-03: `rm prompts/10-acceptance.md; orchestrate.sh` | **2** |
| 15–17 | B-18: `criteriaRef` mit `\|` / `&` / `#` | je **2** |
| 18–19 | B-15: leeres `SAFE_MODE_PATTERN` / `REQUIRED_FLAGS` | je **2** |
| 20 | L2-B-03: `$BUILDER_EXTRA_FLAGS`-Umgehung + `argspy` | **2**, argv leer |
| 21 | L2-B-03 Gegenprobe: literales `--dangerously-skip-permissions` | **2** |
| 22 | B-04: `AUTONOMY_LEVEL=0`, 7 Läufe | 7× **0**, 7 Phasen |
| 23 | B-06: Zyklus-Manifest | **2** |
| 24 | B-07: `orchestrate.sh M1` bei offenem M0 | **2** |
| 25 | B-05: eigenes Dauer-`error`-Gate + PASS-Verdict | **3** |
| 26–28 | B-24: `verifier.sh` mit rc 5 / 127 / `GATE_ERROR_CODES=5` | **1 / 2 / 2** |
| 29–32 | B-16: `82-territory.sh.example`, 4 Marker-Varianten | **0 / 1 / 1 / 1** |
| 33 | B-08: LEAK-Probe der Modellumgebung | **0** — 0 Treffer |
| 34 | B-08b: Geheimnisvariable in `ENV_ALLOWLIST` | **2** |
| 35 | L2-B-01: 10 Connector-Proben | **0** — 0 Leaks |
| 36 | L2-B-01 Gegenproben: 8 Umgehungsversuche (`..`, Symlinks, `.ENV`, `.env.bak`) | 0 — **N-1 gefunden** |
| 37 | N-1: `tail`/`wc`/`git diff`/`grep`/`lies` über 3 Symlinks | 0 — `tail` leakt |
| 38 | N-1 e2e: Builder legt `src/notiz` → `secrets.env` an | **0**, 0 Verletzungen |
| 39–40 | B-09: Reviewer `stilbibel.md` ohne / mit `REVIEWER_EXTRA_PATHS_REGEX` | **2 / 0** |
| 41 | B-09/B-21: `grep EXTRA_PATHS_REGEX` in `config.env.example` und den 3 Presets | 0 |
| 42–44 | B-17: leerer Lock / Fremdinhalt / **6 gleichzeitige Starts** | **0 / 2 / 1×0+5×2** |
| 45 | `git check-ignore -v --no-index orchestrator/.lock{,/pid,/stray} Cargo.lock` | 0 |
| 46–48 | L2-B-04: Watchdog → Doppelstart → Watchdog | **1 / 2 / 1** |
| 49–50 | B-20: `status.sh '' parked` / `'' done` | je 0 |
| 51 | L2-B-05: ziffernlose IDs, QA-Pflicht, QA aus | **3** |
| 52 | B-23: aktive QA, beide MS | **0** |
| 53 | B-11: `qa_required` 5 IDs × 3 Grenzen | 0 — 15/15 |
| 54 | B-10 Rot-Probe: fehlender Verhaltensschlüssel | **1** |
| 55 | B-10: vollständige Schlüsselliste | **0** |
| 56 | B-10 Gegenprobe: `T5-SOLL` D12 auf `01-70` erweitert | **1** — `Soll-IDs fehlen: T5-D12-65…70` |
| 57 | B-10 Gegenprobe: Suchanker in `T5-INVENTAR` verfälscht | **1** |
| 58 | B-13: `diff` PASS-Zeilen `ABNAHME.md` ↔ heutiger Lauf | 0 — identisch |
| 59 | B-19/B-21/L2-N-01/L2-N-02: Dokument- und Promptproben | 0 |
| 60–65 | B-22: mutgate ×3, trace ×2, golden-adr ×2 | **0/1/2 · 0/1 · 1/0** |
| 66 | E1-Gegenprobe: `fail` + `error` gemischt | **1** — `result=fail` |
| 67 | E8-Gegenprobe: Modell überschreibt `secrets.env` | **2** |
| 68 | `git worktree add /tmp/altstand 865840e` | 0 |
| 69–77 | Rot-Probe: 9 Tests gegen den Altstand | 8× **1**, `test-t3-ladder` **0** (Alttest) |
| 78–81 | `bash -x` auf t7/t6/t8/t4 im Altstand (Fehlerstelle) | je 1 |
| 82–86 | Altstand-Direktrepros L2-B-01/-02/-03/-05, B-05, L2-B-04 | 0/0+2+2/0/0/3/1+2+1 |
| 87 | `git diff --stat 865840e..HEAD -- tests/ orchestrator/mcp/tests/` | 0 — 23 Dateien, +986/−79 |
| 88 | `git diff --quiet 865840e..HEAD -- tests/template/test-t3-ladder.sh` | 0 — unverändert |
| 89 | `git worktree remove --force /tmp/altstand`, `git worktree list` | 0 |
| 90 | `git show --stat 8a33684`, Diff auf `AGENTS.md` | 0 |
| 91 | Endkontrolle: `git status --porcelain -uall`, `git rev-parse HEAD` | 0 — leer, `07ea75c8…` |

Alle temporären Fälle unter `/tmp/wa-*` und `/tmp/altstand` wurden entfernt.

---

## 8. Restunsicherheiten

1. **Tunnelpfad weiterhin ungeprüft.** `HARNESS_T1_WITH_TUNNEL=1` habe ich
   nicht gefahren — es öffnete einen öffentlichen Cloudflare-Tunnel auf ein
   Repo, eine nach außen wirkende Handlung ohne Freigabe. Die Expositionslage
   von N-1 stützt sich damit auf `bootstrap.sh` und `server.py`, nicht auf
   einen laufenden Tunnel. Wie schon in beiden Vorläufen.
2. **Keine echten Rollen-CLIs.** `codex`/`claude` sind nicht installiert. Alle
   Rollenprüfungen liefen gegen `fake-model.sh`. `validate_role_cli` gegen echte
   `--help`-Ausgaben und reale Sandbox-Flags bleiben ungeprüft; die
   `$`-Referenz-Sperre habe ich dafür an einem echten `argspy`-Wrapper belegt.
3. **T5-SOLL bleibt eine Setzung.** E6 verlangt eine „einmalig aus den Quellen
   abgeleitete" Sollliste, und genau das ist `T5-SOLL.md`: die
   ID-Bereiche (`D12 01-64`, `PATCH 01-15`, …) sind versioniert und werden vom
   Prüfskript exakt erzwungen — aber kein ausführbarer Schritt leitet sie aus
   `docs/12`/`docs/14`/Patch-v2 her. Ich habe die Zahl 64 nicht gegen
   `sources/demiurg/docs/12-*.md` nachgezählt; das wäre eine Neuabnahme von E6
   und nicht Gegenstand dieser Nachprüfung. **Gegenprobe stattdessen:** dass die
   Liste überhaupt beißt, habe ich mit drei Rot-Proben belegt (#54, #56, #57).
   Der substantielle Teil von E6 — sechs ausführende Verhaltensnachweise statt
   Suchanker — ist umgesetzt und erzwungen.
4. **Suite-Idempotenz.** `run-all.sh` lief einmal komplett (Exit 0). Einen
   zweiten Vollauf habe ich nicht gefahren; die Einzeltests T-4/T-6/T-7/T-8 und
   `test_allowlist.py` liefen im Rahmen der Rot-Probe mehrfach ohne
   Reihenfolgeeffekte.
5. **N-3 nicht isoliert gefahren.** Der Fall „Modell schreibt ausschließlich in
   einen Artefaktpfad" ist aus `changed_paths`/`artifact-paths.allowlist`
   gelesen, nicht als eigener Lauf belegt.
6. **Schwere-Einstufung von N-1** ist mein Vorschlag. Die Reproduktion ist der
   belastbare Teil; ob „MITTEL" oder „HOCH" hängt davon ab, ob der Connector im
   Betrieb wirklich hinter einem öffentlichen Quick-Tunnel läuft.

### Ausdrücklich unternommene Gegenproben (statt „sieht gut aus")

- Jeder Positivbefund hat eine **Negativkontrolle**: B-09 ohne Hook → FATAL;
  B-16 mit vier Marker-Varianten; B-18 mit drei Sonderzeichen inkl. dem
  aktuellen sed-Delimiter `#`; B-24 mit rc 5 / 127 / überschriebenen Codes;
  B-22-trace mit verfälschtem Zitat; E1 mit gemischten `fail`+`error`-Gates;
  B-08 mit Geheimnis in der `ENV_ALLOWLIST`; E8 mit einem Modell, das
  `secrets.env` überschreibt.
- **Alle Repro-Fälle habe ich selbst gebaut** (eigenes `mkcase.sh`, eigene
  adversarielle Builder/Reviewer, eigene Gates). Die mitgelieferten
  Probe-Schalter `ACCEPTANCE_*` habe ich nur dort genutzt, wo sie den Fall
  nicht bewerten (Env-Capture).
- **B-17 als echtes Wettrennen** gefahren (6 parallele Orchestratoren), nicht
  nur als Lock-Fenster.
- **Vollständigkeitsprobe der Rot-Probe:** alle neun Testskripte gegen den
  Altstand gefahren, um einen Test zu finden, der dort ebenfalls grün wäre.
  Genau einer ist es — `test-t3-ladder.sh` — und der ist seit `865840e`
  unverändert, also kein neuer Negativtest.
- **Gezielte Umgehungsversuche am MCP-Connector** (`..`, absolute Pfade,
  `.ENV`-Großschreibung, `.env.bak`, Symlink auf Datei, Symlink auf
  Verzeichnis, Symlink nach außerhalb des Repos) — dabei entstand N-1.
