# PROGRESS — Langzeitgedächtnis des Builders

## Nachtrag 1.1.1 — 2026-10-23

Auftrag des Betreibers: Lücke in `verdict()` schließen; das Verdict muss aus
der aktuellen Runde stammen, ein fehlendes oder älteres Verdict ist FATAL mit
klarer Meldung; Testfall in T-7, Suite grün, Commit, Tag `v1.1.1`, Push.

### Änderungen

- `verdict()` in `orchestrator/orchestrate.sh` erhält Runde und Phasenmarker
  und prüft `.round` gegen die laufende Runde: `Verdict fehlt`,
  `Verdict veraltet` (Runde kleiner) oder `Verdict passt nicht zur Runde`
  (andere Runde) enden mit FATAL. Die Meldung nennt Datei, gefundene und
  erwartete Runde sowie den Wiederanlauf.
- `verdict()` lief bisher in einer Befehlsersetzung; die FATAL-Zeile ging
  dadurch in die Variable statt auf die Konsole (nur `orchestrate.log` und
  der Status zeigten sie). Das Ergebnis steht jetzt in `VERDICT_VALUE`, wie
  bei `EXPANDED_ROLE_CMD` und `LAST_GATE_RC`; `fatal` läuft in der Hauptshell.
- Beim Prüfen des Wiederanlaufs gefunden: Phasen- und Parkmarker sind
  versioniert. Ein bloßes `rm` lässt den Arbeitsbaum unsauber, der PREFLIGHT
  bricht ab. Die Verdict-Meldung, der Fortsetzungstext in
  `ESCALATION-<MS>.md` (`park()`), RUNBOOK und README nennen deshalb
  `git rm` und einen Commit.
- Prompts 30 und 50, `orchestrator/handoff/SCHEMA.md` und
  `contracts/PROTOCOLS.md` verlangen `"round": <laufende Runde>`.
- T-7: Die Reviewer-Attrappe gibt in Runde 1 trotz rotem Gate PASS und
  schreibt in Runde 2 kein Verdict → FATAL `Verdict veraltet`; danach
  Wiederanlauf nach der Meldung (`git rm` des Markers, Commit) → frisches
  Verdict der Runde 2, M0 fertig. Zweiter Fall: Plan-Review ohne Verdict →
  FATAL `Verdict fehlt`. T-3 prüft den Fortsetzungstext mit `git rm`.
- Grenze: Innerhalb einer Runde unterscheidet die Prüfung die
  Infrastruktur-Wiederholungen der Gates nicht; zwischen ihnen ändert sich der
  Code nicht, es laufen nur die Gates erneut.

### Belege

Rot-Probe: dasselbe Szenario gegen `orchestrator/orchestrate.sh` aus `HEAD`
(v1.1.0), Attrappe mit der neuen Probe:

```text
alt: rc=0
[20261023-223154] RUN reviewer 50-code-review (M0 r1, Versuch 1)
[20261023-223155] RUN reviewer 50-code-review (M0 r2, Versuch 1)
[20261023-223156] === M0 DONE ===
alt: verdict-code.json M0 = {"round":1,"verdict":"PASS"}
alt: Tag done/M0 = vorhanden
alt: Review-Log r2 = fake-model: role=reviewer phase=50-code-review milestone=M0 round=2 scenario=T2 args=reviewer --fixture-safe
```

Wiederanlauf nach `Verdict veraltet` (neuer Orchestrator):

```text
1) Lauf mit Probe:
rc=2 FATAL: Verdict veraltet: orchestrator/handoff/M0/verdict-code.json stammt aus Runde 1, erwartet R
2) nur rm, Probe aus:
rc=2 FATAL: Arbeitsbaum vor Lauf nicht sauber: orchestrator/state/M0/code-review-r2-infra0.done
3) git rm + Commit:
rc=0 === M0 DONE ===
{"round":2,"verdict":"PASS"}
```

Entparken nach bisherigem RUNBOOK (`rm orchestrator/state/<MS>/parked`):

```text
1) Park:
rc=3
   parked versioniert: orchestrator/state/setup/parked
2) nur rm:
rc=2 FATAL: Arbeitsbaum vor Lauf nicht sauber: orchestrator/state/setup/parked
```

```text
$ bash tests/template/run-all.sh   # Start 2026-10-23 22:33:34 CEST; Auszug: Abschnittsköpfe, Ergebnis- und Belegzeilen
===== test-t1-bootstrap.sh =====
T-1 PASS: bootstrap=2 summary=contract-v1 repo-env=absent mcp-manifest=pinned secrets=isolated tunnel=0
===== test-t2-rework.sh =====
T-2 PASS: milestones=2 gates=2 red=1 rework=1 transport-retry=1 territory-retry=1 done=2 exit=0
===== test-t3-ladder.sh =====
T-3 PASS: rebuild=r4 arbiter=HUMAN arbiter-effort=reviewer-cmd parked=M0 escalation=present,resume=git-rm exit=3
===== test-t4-ops.sh =====
T-4 PASS: notify=DONE,PARKED watchdog=STALE double-start=isolated foreign-lock=FATAL status-precedence=parked watchdog-exit=1
===== ../../orchestrator/mcp/tests/test_allowlist.py =====
test_allowlist: 72/72 OK
===== test-t6-qa-autonomy.sh =====
T-6 PASS: qa=active qa-park=pre-round qa-probe=logged,strict-FATAL autonomy0=8-distinct-phases digit-free-ids=2
===== test-t7-integrity.sh =====
T-7 evidence stale-verdict.log: [20261023-223447] FATAL: Verdict veraltet: orchestrator/handoff/M0/verdict-code.json stammt aus Runde 1, erwartet Runde 2; die Review-Phase hat kein neues Verdict geschrieben. Nach Sichtung des Reviewer-Logs git rm orchestrator/state/M0/code-review-r2-infra0.done, committen und neu starten; die Review-Phase läuft dann erneut.
T-7 evidence missing-verdict.log: [20261023-223454] FATAL: Verdict fehlt: orchestrator/handoff/M0/verdict-plan.json (erwartet: Runde 1). Nach Sichtung des Reviewer-Logs git rm orchestrator/state/M0/plan-r1-reviewed.done, committen und neu starten; die Review-Phase läuft dann erneut.
T-7 PASS: hidden-territory=rollback logs=hash-protected env=allowlisted flags=expanded ban-list=yolo,bypass,auto,resume safe-edit-modes=auto_edit,auto-edit verdict-round=stale,missing=FATAL resume=git-rm guards=explicit preflight=contracts manifest=cycle qa-bound=validated deps=FATAL identity=FATAL preset-hooks=accepted
===== test-t8-gates.sh =====
T-8 PASS: gate-error=2-retries-no-round rc5=fail mutgate=pass,ratchet-fail,error trace=pass golden-adr=fail,pass territory-marker=current
===== test-t9-install.sh =====
T-9 PASS: project-files=untouched merge=gitignore,gitattributes,Rbuildignore quellen=ignored katalog=versioned exec-bits=100755(filemode=false) fresh-clone=executable docs-conflict=reported dry-run=no-change idempotent=yes dirty=FATAL
===== test-t10-r-paket.sh =====
T-10 PASS: install=tools/install-into.sh preset-blocks=config-env,toolchain m0=done gates=deps,lint,tests,trace,territory,mutgate,golden-adr R/=unchanged rbuildignore=complete mutation=muttest,score=83.33,fail@90,pass@65
===== test-t5-behavior.sh =====
T-5B PASS: territory-enforcement flag-ban sandbox-guard lock-orphan qa-park mcp-allowlist executed
===== test-t5-inventory.py =====
T-5 PASS: target=versioned rows=112 static=101 behavior=6 omitted=5 categories=ORCH=12,AGENT=5,D12=64,PATCH=15,D14=7,NEW=9 exact-ids=PASS cross-file=PASS
A6 PASS: T-1 T-2 T-3 T-4 MCP-Allowlist T-5B T-5 T-6 T-7 T-8 T-9 T-10
real	2m0.352s
(Exit 0)
```

## Umbau 1.1.0 — 2026-10-23

Auftrag: `04_Auftrag_Harness_Umbau.md`, Abschnitte A bis H; QA Weg A mit
Ersatz Weg C (H1), Rollenkommandos nach H8. Ausgeführt von Claude Code mit
Claude Opus 5.5 als Betreiber-Werkzeug. Umgebung: WSL2, Ubuntu 26.04, Checkout
auf `/mnt/c` mit `core.filemode=false`.

### Gelieferte Artefakte und Verträge

- A: Verbotslisten in `orchestrator/orchestrate.sh` erweitert. Neu gesperrt:
  `--approval-mode=yolo`, `--approval-mode yolo`, alles mit
  `dangerously-bypass` (auch `--dangerously-bypass-approvals-and-sandbox`),
  `--approval-mode auto` (H1), dazu beim Abgleich mit den echten `--help`
  gefunden `--allow-dangerously-skip-permissions` (Claude Code; der alte
  Ausdruck verlangte `--` direkt vor `dangerously`), `--permission-mode auto`
  (Claude Code, Klassifikator), `--approve-for-me` (Codex, automatische
  Prüfung), `--session-file` (Gemini, lädt eine Sitzung) und die
  Unterkommandos `resume`/`fork` (`codex exec resume --last`). `auto_edit` und
  `auto-edit` bleiben erlaubt. FATAL nennt das gefundene Muster. T-7: zehn
  Negativfälle nach dem Muster der `EXTRA_FLAGS`-Prüfung (Flag wörtlich im
  Kommando, damit die Sperrliste erreicht wird) und zwei Positivfälle
  (`--approval-mode auto_edit`, `--approval-mode auto-edit`) samt strikter
  Routenprobe.
- H1: Die strikte QA-Routenprobe schreibt die CLI-Ausgabe nach
  `orchestrator/logs/qa-probe-<ts>-<n>.log`; Log-Zeilen nennen den Pfad.
  T-6: simulierte Vertrauens-Rückstufung endet mit FATAL, Meldung im
  Probe-Log. `${QA_MODEL:-}` verhindert einen Abbruch unter `set -u`, wenn
  `QA_MODEL` fehlt.
- B: `projektierung/presets/r-paket/PRESET.md`; Gate-Kommandos im
  Betreiber-Territorium: `orchestrator/lib/r-deps.R`, `r-tests.R`,
  `r-check.sh`, `r-mutation.R`.
- C/H4/H5/H7: `tools/install-into.sh`; T-9.
- D/H1/H2/H3/H8: auskommentierter Drei-Anbieter-Block in
  `config.env.example`, `orchestrator/policies/qa-gemini.toml`; README
  Abschnitt 6 und 8, RUNBOOK.
- E: muttest-Adapter `orchestrator/lib/r-mutation.R`; muttest 0.3.0 schreibt
  bereits das Stryker-Schema, der Adapter reicht den Bericht unverändert durch.
- F: Fixture-Paket `tests/template/fixtures/r-paket/` (eine Funktion
  `clamp_add`, ein Abnahmetest), Szenario T-10 mit Skip-Exit 77 ohne R;
  `run-all.sh` wertet 77 nur bei T-10 als übersprungen und sagt das in der
  Schlusszeile.
- H8: T-3 belegt, dass der Schiedsrichter über `REVIEWER_CMD` dieselben
  Flags (`--effort max`) erhält; der Orchestrator braucht dafür keine Änderung.
- Testinfrastruktur: `materialize_tree` übernimmt die Dateimodi aus dem
  Git-Index statt aus dem Arbeitsbaum (auf `/mnt/c` sind fast alle Dateien
  lokal ausführbar); die Test-Repos entsprechen damit einem frischen Klon.
- G: README (Abschnitte 3 bis 8, 10 bis 12, 15, 16), RUNBOOK, AGENTS.md
  Regel 8, `orchestrator/gates.d/README.md`, STATUS.md über
  `orchestrator/status.sh`, Version 1.1.0 in `CITATION.cff` (Konzept-DOI bis
  zur Archivierung) und `.zenodo.json`.

### Belege an den echten Werkzeugen (23.10.2026)

Versionen: `codex-cli 0.164.0`, Gemini CLI `0.65.0`, `2.1.309 (Claude Code)`,
Qwen Code `0.26.0` (nur für `--help` und Quelltext, isoliert per
`npm install --ignore-scripts` ins Arbeitsverzeichnis der Sitzung, nicht
global), R 4.6.1, testthat 3.3.2, pkgload 1.5.3, muttest 0.3.0, pkgdown
2.2.1, bubblewrap 0.11.1, ripgrep 15.1.0.

- `--help`: Codex `-m/--model`, `-c/--config` („If it fails to parse as TOML,
  the raw string is used as a literal“), `-s/--sandbox` (read-only,
  workspace-write, danger-full-access), `--dangerously-bypass-approvals-and-sandbox`,
  `--approve-for-me`. Claude Code `--effort <level>` (low, medium, high, xhigh,
  max), `--permission-mode` (acceptEdits, auto, bypassPermissions, manual,
  dontAsk, plan), `--allowedTools`, `--allow-dangerously-skip-permissions`.
  Gemini `--approval-mode` (default, auto_edit, yolo, plan), `--policy`,
  `--allowed-tools` als veraltet markiert. Qwen Code `--approval-mode` (plan,
  default, auto-edit, auto, yolo), `--auth-type` (darunter openai),
  `--allowed-tools`.
- `codex debug models`: `gpt-6-astra` mit low, medium, high, xhigh, max,
  ultra. `codex models` ist kein Befehl; die CLI reicht ihn als Prompt an die
  interaktive Oberfläche weiter: `Error: stdin is not a terminal`.
- Modell-ID Gemini 4 Argon: ai.google.dev, Modellseite „Stable:
  gemini-4-argon“; geminicli.com/docs/cli/model: „Gemini CLI has not been
  optimized for Gemini 4 Argon“. Die eingebaute Modellliste der Gemini CLI
  0.65.0 enthält keine Gemini-4-Kennung.
- Gemini CLI 0.65.0, Quelltext des Pakets: `--policy` lädt im Nutzer-Tier
  (4 + priority/1000) und ersetzt `~/.gemini/policies`; Standardregel im
  Headless-Modus: `run_shell_command` → deny (Tier 1.010); verkettete
  Kommandos werden zerlegt und einzeln geprüft. Ordner-Vertrauen ist
  vorgegeben an (`folderTrust?.enabled ?? true`), `~/.gemini/.env` wird nur
  bei vertrautem Ordner gelesen; Meldung wörtlich:
  `Approval mode overridden to "default" because the current folder is not trusted.`
- Qwen Code 0.26.0, Quelltext: `--allowed-tools` landet in
  `permissions.allow`; eine Regel ohne `*` wie `run_shell_command(Rscript)`
  passt auf `Rscript` und `Rscript …`. Ordner-Vertrauen ist vorgegeben aus
  (`?? false`), dieselbe Rückstufungsmeldung; `~/.qwen/.env` ist als
  Nutzerdatei immer lesbar; ohne `--approval-mode` gilt `auto`.
- Gemini-Policy, Headless, `--approval-mode auto_edit`, Modell
  `gemini-3.8-flash` (die Policy ist modellunabhängig): mit
  `--policy qa-gemini.toml` liefen `Rscript -e 'cat(6*7)'` → `42`,
  `python3 -c …` und `Rscript … && python3 …` → `Tool execution denied by
  policy.`; ohne `--policy` alle drei verweigert.
- Claude Code, `-p --permission-mode acceptEdits`, Modell `claude-haiku-5-5`:
  mit `--allowedTools "Bash(Rscript:*)"` lief `Rscript` (`42`),
  `python3 -c …` und die Verkettung standen in `permission_denials`; ohne die
  Regel alle drei verweigert. Reine Lesebefehle wie `whoami` lässt Claude Code
  auch ohne Regel zu.
- Codex-Sandbox ohne Modellaufruf, `codex sandbox -c
  sandbox_mode=workspace-write -- curl … https://example.com`:
  `curl: (6) Could not resolve host: example.com`; dieselbe Abfrage ohne
  Sandbox: `http=200`. Schreiben im Arbeitsverzeichnis und unter `/tmp` ist in
  der Sandbox erlaubt.
- `claude -p --output-format json`: Ergebnisobjekt mit `modelUsage` (je
  antwortendem Modell), `permission_denials`, `safety_stops`.
- pkgdown 2.2.1: `build_site_github_pages()` setzt
  `override = list(destination = dest_dir)` (Vorgabe `"docs"`);
  `clean_site()` bricht auf einem nicht von pkgdown gebauten, nicht leeren
  Ziel mit „is non-empty and not built by pkgdown“ ab.
- muttest 0.3.0: `JSONMutationReporter` schreibt `$schema` des
  Stryker-Mutation-Testing-Report-Schemas, `files` → `mutants` mit `id`,
  `mutatorName`, `replacement`, `location.start.line`, `status` (Killed,
  Survived, NoCoverage, RuntimeError). Probe am Fixture: 6 Mutanten, 5 Killed,
  1 Survived (`> → >=`, Zeile mit `if (total > upper)`); die jq-Logik von
  86-mutgate ergibt 83.33.

Echter PREFLIGHT mit dem Beispielblock (Weg A), Template-Kopie,
`orchestrator/STOP` gesetzt, `setsid -w … < /dev/null` aus einer Shell ohne
Terminal (`tty`: „not a tty“):

```text
orchestrate.sh rc=2
[20261023-203352] CONFIG: AUTONOMY=2 PLAN<=2 REWORK<=8 REBUILD@r4 ARBITER+2 TIMEOUT=3600 RETRY=2x/120s GATE_ERROR_RETRIES=2 MAX_MS=4 QA=1(ab nie) ROLE_GUARDS=on NOTIFY=aus BUILDER=codex REVIEWER=claude
[20261023-203356] QA-Routenprobe bestanden (gemini-4-argon); Ausgabe: orchestrator/logs/qa-probe-20261023-203352-1.log
[20261023-203356] === M0 start ===
[20261023-203356] FATAL: STOP-Datei gefunden — vor der nächsten Phase angehalten.
--- Probe-Log ---
Warning: 256-color support not detected. Using a terminal with at least 256-color support is recommended for a better visual experience.
OK
```

Damit bestanden: `--help` aller drei CLIs mit den Pflicht-Flags
(`--sandbox --model --config`, `--permission-mode --model --effort
--allowedTools`, `--approval-mode --policy --model`), die sicheren Modi, die
Verbotslisten und die QA-Routenprobe ohne Terminal. FATAL folgt erst durch die
STOP-Datei vor der ersten Modellphase.

Builder- und Reviewer-Kommando je einmal wie in `run_model`
(`env -i PROMPT_FILE PATH HOME LANG bash -c "$CMD"`), Prompt „Antworte nur:
OK“: Builder rc=0, `OK`, 7 s; Reviewer rc=0, `OK`, 9 s. Codex-Sitzungsdatei:
`"model":"gpt-6-astra","effort":"max","sandbox":{"type":"workspace-write","network_access":false,…},"approval":"never"`.
Claude-Code-Transkript: `"model":"claude-opus-5-5"`, `"effort":"max"`.
Weg C wurde nicht ausgeführt (kein OpenRouter-Schlüssel, Qwen Code nicht
installiert); Flags und Shell-Regel sind über `--help` und den Quelltext von
0.26.0 belegt.

Rot-Probe: die neuen T-7-Sperrfälle gegen `orchestrator/orchestrate.sh` aus
`HEAD` (vor dem Umbau), je eine Modellphase:

```text
alt: --approval-mode=yolo                             rc=0 (kein FATAL, PREFLIGHT bestanden)
alt: --approval-mode yolo                             rc=0 (kein FATAL, PREFLIGHT bestanden)
alt: --dangerously-bypass-approvals-and-sandbox       rc=0 (kein FATAL, PREFLIGHT bestanden)
alt: --approval-mode auto                             rc=0 (kein FATAL, PREFLIGHT bestanden)
alt: --allow-dangerously-skip-permissions             rc=0 (kein FATAL, PREFLIGHT bestanden)
alt: resume --last                                    rc=0 (kein FATAL, PREFLIGHT bestanden)
```

### Messung H4: Mehraufwand je Modellaufruf

Je Lauf ein Orchestrator-Aufruf mit `AUTONOMY_LEVEL=0`, also genau eine
Modellphase (10-acceptance, Attrappe), danach Rücksetzen auf den
Ausgangscommit; ignorierte Quellen bleiben liegen. Median aus drei Läufen.
Textspiegel: `quellen/text` ohne `_ocr` (174 Quellen laut `INDEX.tsv`, 303
Dateien, 39 MB); Rohdaten synthetisch (`/dev/urandom`, 900 MB und 400 MB).

```text
/mnt/c (Windows-Temp, 9p)
ohne Quellen                       3.70 s  (Läufe: 3.69 3.70 3.70)
Textspiegel: 303 Dateien, 39M
mit Textspiegel                    24.20 s  (Läufe: 23.97 24.20 24.23)
Rohdaten (synthetisch): 1.3G
mit Textspiegel + 1,3 GB Rohdaten  56.50 s  (Läufe: 56.90 55.31 56.50)

WSL-Dateisystem (ext4, ~/.cache)
ohne Quellen                       0.40 s  (Läufe: 0.40 0.41 0.40)
Textspiegel: 303 Dateien, 39M
mit Textspiegel                    3.96 s  (Läufe: 3.98 3.96 3.93)
```

Mehraufwand auf `/mnt/c`: rund 20 s je Aufruf für den Textspiegel, rund 32 s
zusätzlich für 1,3 GB Rohdaten. Er wächst vor allem mit der Dateizahl (je
Datei mehrere Prozessstarts in `snapshot_worktree` und `ownership_check`).
Messordner wurden danach gelöscht. Messskript (Kern):

```bash
prepare_orchestrator_case T2 "$REPO"   # tests/template/lib.sh
sed -i 's/^AUTONOMY_LEVEL=3$/AUTONOMY_LEVEL=0/; s/^ACCEPTANCE_TERRITORY_PROBE=1$/ACCEPTANCE_TERRITORY_PROBE=0/; s/^ACCEPTANCE_TRANSPORT_PROBE=1$/ACCEPTANCE_TRANSPORT_PROBE=0/' "$REPO/orchestrator/config.env"
# je Lauf: git reset --hard <start>; Tags löschen; git clean -qfd -e config.env -e toolchain.json;
# orchestrator/state/M0, handoff/M0 und Logs entfernen; dann Wanduhrzeit von
# bash orchestrator/orchestrate.sh (genau eine Phase) messen
```

### Ausgeführte Befehle und echter Output

```text
$ bash -n orchestrator/orchestrate.sh orchestrator/lib/r-check.sh tools/install-into.sh tests/template/*.sh
$ Rscript -e "invisible(parse('<datei>'))"   # für orchestrator/lib/*.R
(keine Ausgabe; Exit 0)

$ bash tests/template/run-all.sh   # Start 2026-10-23 20:56:25 CEST; Auszug: Abschnittsköpfe, Ergebnis- und Belegzeilen
===== test-t1-bootstrap.sh =====
T-1 PASS: bootstrap=2 summary=contract-v1 repo-env=absent mcp-manifest=pinned secrets=isolated tunnel=0
===== test-t2-rework.sh =====
T-2 PASS: milestones=2 gates=2 red=1 rework=1 transport-retry=1 territory-retry=1 done=2 exit=0
===== test-t3-ladder.sh =====
T-3 PASS: rebuild=r4 arbiter=HUMAN arbiter-effort=reviewer-cmd parked=M0 escalation=present exit=3
===== test-t4-ops.sh =====
T-4 PASS: notify=DONE,PARKED watchdog=STALE double-start=isolated foreign-lock=FATAL status-precedence=parked watchdog-exit=1
===== ../../orchestrator/mcp/tests/test_allowlist.py =====
test_allowlist: 72/72 OK
===== test-t6-qa-autonomy.sh =====
T-6 evidence probe: Approval mode overridden to "default" because the current folder is not trusted.
T-6 PASS: qa=active qa-park=pre-round qa-probe=logged,strict-FATAL autonomy0=8-distinct-phases digit-free-ids=2
===== test-t7-integrity.sh =====
T-7 evidence ban-gemini-yolo-eq.log: [20261023-205722] FATAL: gefährlicher Bypass-/Full-Access-/Auto-Freigabe-Modus in Rollenkommando gefunden: --approval-mode=yolo
T-7 evidence ban-gemini-yolo-space.log: [20261023-205723] FATAL: gefährlicher Bypass-/Full-Access-/Auto-Freigabe-Modus in Rollenkommando gefunden: --approval-mode yolo
T-7 evidence ban-codex-bypass.log: [20261023-205724] FATAL: gefährlicher Bypass-/Full-Access-/Auto-Freigabe-Modus in Rollenkommando gefunden: dangerously-bypass-approvals-and-sandbox
T-7 evidence ban-codex-bypass-generic.log: [20261023-205725] FATAL: gefährlicher Bypass-/Full-Access-/Auto-Freigabe-Modus in Rollenkommando gefunden: dangerously-bypass-hook-trust
T-7 evidence ban-qwen-auto.log: [20261023-205726] FATAL: gefährlicher Bypass-/Full-Access-/Auto-Freigabe-Modus in Rollenkommando gefunden: --approval-mode auto
T-7 evidence ban-claude-allow-skip.log: [20261023-205727] FATAL: gefährlicher Bypass-/Full-Access-/Auto-Freigabe-Modus in Rollenkommando gefunden: dangerously-skip-permissions
T-7 evidence ban-claude-auto.log: [20261023-205728] FATAL: gefährlicher Bypass-/Full-Access-/Auto-Freigabe-Modus in Rollenkommando gefunden: --permission-mode auto
T-7 evidence ban-codex-approve-for-me.log: [20261023-205729] FATAL: gefährlicher Bypass-/Full-Access-/Auto-Freigabe-Modus in Rollenkommando gefunden: --approve-for-me
T-7 evidence ban-codex-resume.log: [20261023-205730] FATAL: Resume-/Session-Flags sind verboten; jede Phase ist eine frische Session: resume
T-7 evidence ban-gemini-session-file.log: [20261023-205731] FATAL: Resume-/Session-Flags sind verboten; jede Phase ist eine frische Session: --session-file
T-7 evidence allow-gemini-auto-edit.log: [20261023-205733] QA-Routenprobe bestanden (fake-qa); Ausgabe: orchestrator/logs/qa-probe-20261023-205732-1.log
T-7 evidence allow-qwen-auto-edit.log: [20261023-205734] QA-Routenprobe bestanden (fake-qa); Ausgabe: orchestrator/logs/qa-probe-20261023-205734-1.log
T-7 PASS: hidden-territory=rollback logs=hash-protected env=allowlisted flags=expanded ban-list=yolo,bypass,auto,resume safe-edit-modes=auto_edit,auto-edit guards=explicit preflight=contracts manifest=cycle qa-bound=validated deps=FATAL identity=FATAL preset-hooks=accepted
===== test-t8-gates.sh =====
T-8 PASS: gate-error=2-retries-no-round rc5=fail mutgate=pass,ratchet-fail,error trace=pass golden-adr=fail,pass territory-marker=current
===== test-t9-install.sh =====
T-9 evidence install: install-into: neu 89, unverändert 0, Konflikte 1, Ausführungsrechte nachgetragen 0
T-9 evidence modes: 15 executables 100755, control git add -> 100644
T-9 evidence docs: - docs/ ist im Zielrepo ignoriert (.gitignore:2:docs/); Specs und ADRs unter docs/ würden nie versioniert
T-9 PASS: project-files=untouched merge=gitignore,gitattributes,Rbuildignore quellen=ignored katalog=versioned exec-bits=100755(filemode=false) fresh-clone=executable docs-conflict=reported dry-run=no-change idempotent=yes dirty=FATAL
===== test-t10-r-paket.sh =====
T-10 evidence mutation: mutgate: pass (score=83.33 required=65 baseline=83.33 floor=50)
T-10 evidence toolchain: toolchain: runtime R ok — Rscript (R) version 4.6.1 (2026-06-24)
T-10 evidence gates: {"deps":"pass","lint":"pass","tests":"pass","trace":"pass","territory":"pass","mutgate":"pass","golden-adr":"pass"}
T-10 evidence check: r-check: pass — Status: OK
T-10 PASS: install=tools/install-into.sh preset-blocks=config-env,toolchain m0=done gates=deps,lint,tests,trace,territory,mutgate,golden-adr R/=unchanged rbuildignore=complete mutation=muttest,score=83.33,fail@90,pass@65
===== test-t5-behavior.sh =====
T-5B PASS: territory-enforcement flag-ban sandbox-guard lock-orphan qa-park mcp-allowlist executed
===== test-t5-inventory.py =====
T-5 PASS: target=versioned rows=112 static=101 behavior=6 omitted=5 categories=ORCH=12,AGENT=5,D12=64,PATCH=15,D14=7,NEW=9 exact-ids=PASS cross-file=PASS
A6 PASS: T-1 T-2 T-3 T-4 MCP-Allowlist T-5B T-5 T-6 T-7 T-8 T-9 T-10
real	1m50.086s
(Exit 0)
```

Gegenprobe T-10 ohne R (`env -i PATH=<nur dirname und bash>`):
`T-10 übersprungen: R fehlt`, Exit 77.

### Bekannte Schulden und offene Risiken

- QA Weg C ist nur über `--help` und den Quelltext belegt, die Routenprobe
  ist offen; Weg B (Antigravity) ist dokumentiert, nicht konfiguriert.
- Den Wortlaut des Modellwechsel-Hinweises im Textmodus von `claude -p`
  dokumentiert Anthropic nicht; das RUNBOOK nennt geprüfte Nachweise
  (Sitzungsprotokoll, optional `--output-format json`).
- Die Verbotslisten erfassen keine Kurzflags (`-y`, `-c`, `-r`) und keine
  Freigaben in CLI-Einstellungsdateien unter `HOME` (README Abschnitt 8).
- Der Mehraufwand des Textspiegels (rund 20 s je Modellaufruf auf `/mnt/c`)
  entsteht vor allem aus Prozessstarts je Datei; gebündeltes Hashen könnte ihn
  senken, ohne die Prüfung abzuschwächen. Nicht Teil dieses Auftrags.
- Beobachtung außerhalb des Auftrags: `verdict()` prüft das Feld `round`
  nicht gegen die laufende Runde; schreibt ein Reviewer-Lauf kein neues
  Verdict, liest der Orchestrator das der Vorrunde. Behoben in 1.1.1.
- Zenodo vergibt die DOI für 1.1.0 erst mit der Archivierung (GitHub-Release);
  danach `CITATION.cff` und README Abschnitt 16 nachtragen.
- Die Probeaufrufe der echten CLIs liegen als gewöhnliche Sitzungsdaten unter
  `~/.codex/sessions`, `~/.claude/projects` und `~/.gemini/tmp`.

### Nächster klarer Einstiegspunkt

Schritt 5 der Startanleitung: `tools/install-into.sh` im Zielrepo, offene
Punkte nach dem Bericht lösen (docs/ und pkgdown), danach das Preset
`r-paket`, Abschnitt „Einsetzen in ein bestehendes Paket“.

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
