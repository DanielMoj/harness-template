# Abnahmebericht harness-template — Lauf 2

> Historischer Lauf; Pfadangaben dokumentieren den damaligen Stand.

**Unabhängige Gegenprüfung, frische Sitzung.** Auftrag: gezielt ein Gegenbeispiel
suchen, das eine bestehende A9- oder A6-PASS-Behauptung widerlegt. Schwerpunkte
Testlücken, Shell-Fehler, Seiteneffekte, Pfadgrenzen, Race Conditions und nur
dokumentierte statt tatsächlich implementierter Funktionalität. Jeder Befund mit
Reproduktion, Kommandoausgabe und Exitcode. Am Repo wurde nichts geändert.

- Prüfstand: `/tmp/harness-opus-audit.u1UCQV/repo`, HEAD `865840e` („Add executable template acceptance")
- Umgebung: Linux 6.6.87.2-microsoft-standard-WSL2, GNU bash 5.3.9(1), jq-1.8.1, git 2.53.0, Python 3.14.4
- Zustand nach Abschluss: `git status --porcelain --untracked-files=all` → leer, HEAD unverändert `865840e`
- Reproduktionsfälle liegen unter `…/scratchpad/{mcpcase,lockcase,flagcase,wdcase,qacase}`

---

## 1. Gesamturteil: **FAIL**

Die vorgeschriebene Abnahme reproduziert vollständig. Ich habe sie selbst gefahren,
und alle fünf Tests sind grün (Abschnitt 2). Die PASS-Zeilen in `docs/ABNAHME.md`
sind nicht erfunden.

Widerlegt wird die daraus gezogene Schlussfolgerung. „A9 belegt" plus „A6 grün"
heißt nach diesem Lauf **nicht**, dass die Mechanik trägt. Fünf Gegenbeispiele
zeigen zugesagte Sicherungen, die im Realbetrieb nicht greifen — davon drei
kritisch:

| ID | Befund | Schwere | Status ggü. Lauf 1 |
|---|---|---|---|
| L2-B-01 | MCP-Connector gibt `orchestrator/config.env` samt API-Key über die Allowlist heraus | **KRITISCH** | **neu** — widerspricht einem PASS aus Lauf 1 |
| L2-B-02 | Modellrolle schreibt unentdeckt ins Betreiber-Territorium und legt den Orchestrator dauerhaft still | **KRITISCH** | Ursache = L1-B-02; die Eskalation zum permanenten Stillstand ist **neu** |
| L2-B-03 | Verbotsliste gefährlicher Flags ist mit dem dokumentierten `$VAR`-Idiom umgehbar | **KRITISCH** | **neu** (anderer Mechanismus als L1-B-15) |
| L2-B-04 | Abgewiesener Doppelstart setzt den Heartbeat zurück und blendet den Watchdog | **HOCH** | **neu** — in Lauf 1 kein Treffer zu „watchdog"/„heartbeat" |
| L2-B-05 | `qa_required()` bricht bei ziffernlosen Meilenstein-IDs, Pflicht-QA fällt still aus | **HOCH** | **bestätigt** L1-B-11 / L1-B-23, hier end-to-end nachgefahren |

Betroffene A9-Blöcke: „Rollen (§1)", „Sicherheitsschienen (§5)", „Betrieb (§6)",
„Autonomie (Patch v2)". Betroffene T-5-Zeilen, die alle den Status `belegt`
tragen: T5-D12-31, T5-D12-40, T5-D12-41, T5-PATCH-04, T5-PATCH-10, T5-NEW-09.

---

## 2. Reproduzierte A6-Basislinie

```text
$ bash tests/template/run-all.sh
T-1 PASS: bootstrap=2 summary=contract-v1 repo-env=absent mcp-manifest=pinned tunnel=0
T-2 PASS: milestones=2 gates=2 red=1 rework=1 transport-retry=1 territory-retry=1 done=2 exit=0
T-3 PASS: rebuild=r4 arbiter=HUMAN parked=M0 escalation=present exit=3
T-4 PASS: notify=DONE,PARKED watchdog=STALE watchdog-exit=1
T-5 PASS: rows=112 mapped=107 omitted=5 categories=ORCH=12,AGENT=5,D12=64,PATCH=15,D14=7,NEW=9 locators=PASS
A6 PASS: T-1 T-2 T-3 T-4 T-5

RUNALL_EXIT=0
real    0m11.541s
```

Alle Einzeltests wurden zusätzlich isoliert gefahren (T-1 Exit 0, T-2 Exit 0,
T-3 Exit 0, T-4 Exit 0, T-5 Exit 0). Der T-1-Lauf ohne Tunnel entspricht der
Angabe `tunnel=0`; die in `docs/ABNAHME.md` festgehaltene Variante mit
`HARNESS_T1_WITH_TUNNEL=1` habe ich nicht nachgefahren (siehe Abschnitt 9).

**Damit ist die Basislinie bestätigt und der Rest dieses Berichts betrifft
ausschließlich das, was die grüne Suite nicht prüft.**

---

## 3. Befunde

### KRITISCH

---

**L2-B-01 · Der MCP-Connector gibt `orchestrator/config.env` samt API-Key über die eigene Allowlist heraus**

*Verletzte Anforderung:* die ausdrückliche Zusicherung im eigenen Abnahmetest —
`orchestrator/mcp/tests/test_allowlist.py:64`:

```python
"git diff orchestrator/config.env",     # .env-Filter: schuetzt den OpenRouter-Key
```

dazu der Härtungsanspruch im Modulkopf `orchestrator/mcp/server.py:10-13`
(„exakte read-only Befehls-Allowlist, Pfad-Guards") und A9/A2 („MCP-Server
generalisieren … befehl-Allowlist"), T5-NEW-09 (`belegt`).

*Datei/Zeile:* `orchestrator/mcp/server.py:142-145` (`pruefe_befehl` filtert `..`
und `.env` **nur im Befehlsstring**), `:75` (Allowlist-Regel
`^grep -(n|rn) {MUSTER} {PFAD}$`), `:252-290` (`befehl()` führt aus).

Der `.env`-Guard prüft die Zeichenkette des Befehls, nicht die Dateien, die der
Befehl liest. `grep -rn` steigt rekursiv ab und liest damit genau die Datei, die
alle drei anderen Wege verweigern.

*Reproduktion* (Fixture-Repo mit Attrappen-Key, `REPO_PATH` gesetzt):

```text
$ python3 -c "import server; …"

--- lies('orchestrator/config.env')
abgelehnt: '.env' im Pfad

--- befehl('git diff orchestrator/config.env')
abgelehnt: '.env' im Befehl

--- befehl('tail -n 40 orchestrator/config.env')
abgelehnt: '.env' im Befehl

--- befehl('grep -rn API orchestrator')
Exit-Code: 0
orchestrator/config.env:1:OPENROUTER_API_KEY=sk-or-v1-DEADBEEFsecret123

PY_EXIT=0
```

Drei Guards halten, der vierte Weg liefert den Klartext. Betroffen sind neben
`OPENROUTER_API_KEY` auch `TUNNEL_TOKEN`, `NOTIFY_URL` und jeder weitere Wert in
`config.env` — die Datei, die `bootstrap.sh:53` eigens auf `chmod 600` setzt.

*Expositionslage.* Der Server läuft nach `bootstrap.sh:205-222` in einer
tmux-Session hinter einem Cloudflare-Tunnel, im Quick-Modus mit öffentlicher
`trycloudflare.com`-URL. `server.py:461-465` setzt
`enable_dns_rebinding_protection=False` und `stateless_http=True`; eine
Authentifizierung existiert nicht. Der Schutz ist laut Kommentar `:456-459`
ausdrücklich an Allowlist und Pfad-Guards delegiert — genau die Schicht, die hier
versagt. Wer die URL hat, hat die Schlüssel.

*Testlücke.* `test_allowlist.py` ist **nicht Teil von A6**: `run-all.sh:6-11`
fährt ausschließlich `test-t1-bootstrap.sh` bis `test-t5-inventory.py`. T-1 ruft
nur `server.py --selftest` (`bootstrap.sh:195`), und dessen 20 Fälle
(`server.py:372-446`) enthalten keinen einzigen Lesevorgang über `grep -rn`.
Die Testliste `MUESSEN_MATCHEN` führt `grep -rn ESCALATE orchestrator/logs`
sogar als gewünschtes Verhalten (`test_allowlist.py:39`) — der Pfad ist geprüft,
nur nie gegen ein Geheimnis gerichtet worden.

*Korrektur:* Den Guard von der Zeichenkette auf das Ergebnis verlagern —
`grep`-Pfade vor der Ausführung durch `pruefe_pfad()` schicken und rekursive
Läufe auf eine Verzeichnis-Allowlist beschränken (`orchestrator/logs`,
`orchestrator/state`, `orchestrator/handoff`), oder `--exclude=*.env` erzwingen.
Zusätzlich Geheimnisse aus `config.env` in eine separate Datei außerhalb des
Repos ziehen.

---

**L2-B-02 · Modellrollen schreiben unentdeckt ins Betreiber-Territorium und legen den Orchestrator dauerhaft still**

*Verletzte Anforderung:* `AGENTS.md` §Betreiber — „Keine Modellrolle darf
Orchestrator-Zustand oder `gates.json` schreiben. Der Orchestrator erzwingt die
Territorien nach jeder Modellphase per Git-Diff und verwirft einen verletzenden
Versuch"; `RUNBOOK.md:33` — „Ein verwaister Lock wird automatisch erkannt";
A9 §1 („Erzwingung per git-diff je Phase"); T5-D12-31 und T5-PATCH-04, beide
`belegt`.

*Datei/Zeile:* `orchestrator/orchestrate.sh:270-272` (`changed_paths()`),
`:286-292` (nachgereichte Pfade), `:315-338` (`path_allowed`), `:91-102`
(`release_lock`), `:105-122` (`acquire_lock`), `.gitignore:22` (`*.lock`).

`changed_paths()` bildet den Territoriums-Diff aus
`git diff --name-only -z HEAD` plus `git ls-files --others --exclude-standard -z`.
`--exclude-standard` blendet alles aus, was `.gitignore` trifft. Nachgereicht
werden genau zwei Pfade (`:286-292`): `orchestrator/config.env` und
`toolchain.json`. Alles andere Ignorierte ist für die Prüfung unsichtbar — und
`*.lock` trifft das Lock-Verzeichnis des Betreibers.

*Vorprobe:*

```text
$ git check-ignore -v --no-index <pfad>
orchestrator/.lock                       IGNORIERT  (.gitignore:22:*.lock)
orchestrator/.lock/pid                   IGNORIERT  (.gitignore:22:*.lock)
orchestrator/.lock/stray                 IGNORIERT  (.gitignore:22:*.lock)
orchestrator/state/M0/gates.json         sichtbar
reports/x                                IGNORIERT  (.gitignore:17:reports/)
dist/y                                   IGNORIERT  (.gitignore:14:dist/)
Cargo.lock                               IGNORIERT  (.gitignore:22:*.lock)
```

*Reproduktion.* T-2-Fall, die Builder-Attrappe legt in Phase `40-build`
zusätzlich `orchestrator/.lock/stray` an — ein Pfad im Betreiber-Territorium:

```text
$ bash orchestrator/orchestrate.sh                        # Lauf 1
RUN1_EXIT=0

$ grep -n 'verletzt Territorium' run1.log
21:[20260806-005931] WARN: reviewer verletzt Territorium: src/reviewer-territory-violation.txt — genau ein Retry mit Hinweis
```

Die einzige Meldung ist die im Fixture eingebaute Sonde in M1. Der
Builder-Schreibzugriff auf `orchestrator/**` wird nie gemeldet, nie
zurückgerollt, nie committet:

```text
$ ls -la orchestrator/.lock/ ; cat orchestrator/.lock/stray
-rw-r--r-- 1 user user  31 Aug  6 00:59 stray
model wrote operator territory

$ git status --porcelain --untracked-files=all
 M orchestrator/state/summary.json          ← git sieht die Fremddatei nicht
```

`release_lock` (`:97-99`) entfernt am Laufende nur `pid` und ruft
`rmdir … 2>/dev/null || true`; das Verzeichnis bleibt wegen `stray` bestehen.
Jeder Folgestart läuft in `acquire_lock:116-119` und stirbt:

```text
$ bash orchestrator/orchestrate.sh                        # Lauf 2
[20260806-010011] WARN: verwaister Lock (PID unbekannt) — wird übernommen
[20260806-010011] FATAL: verwaister Lock ist nicht leer: …/orchestrator/.lock
RUN2_EXIT=2

$ bash orchestrator/orchestrate.sh                        # Lauf 3 — unverändert
[20260806-010520] WARN: verwaister Lock (PID unbekannt) — wird übernommen
[20260806-010520] FATAL: verwaister Lock ist nicht leer: …/orchestrator/.lock
RUN3_EXIT=2
```

Der Zustand heilt nicht von selbst. Es gibt keinen Automatismus und keinen
RUNBOOK-Handgriff dafür — `RUNBOOK.md:33` sagt das Gegenteil zu. Eine Modellrolle
kann das Harness damit in einer einzigen Phase, ohne Spur in der Git-Historie,
dauerhaft ausschalten.

*Testlücke.* Die einzige Territoriumssonde in A6 ist
`tests/template/fake-model.sh:38-45` und schreibt
`src/reviewer-territory-violation.txt` — einen **git-sichtbaren** Pfad.
`test-t2-rework.sh:35` prüft dessen Rücknahme. Die unsichtbare Hälfte der
Prüfung ist konstruktionsbedingt unerreichbar; `territory-retry=1` in der
T-2-PASS-Zeile belegt nur den sichtbaren Fall.

*Abgrenzung zu Lauf 1.* Die Ursache (Blindheit gegenüber `.gitignore`) ist als
L1-B-02 bekannt und dort auf Fälschung der Beweisspur bezogen. L1-B-17 betrifft
ein anderes Lock-Problem (Rennfenster zwischen `mkdir` und `pid`, vom Betreiber
ausgelöst). Neu ist hier, dass dieselbe Blindheit einer **Modellrolle** einen
permanenten, nicht selbstheilenden Ausfall des Orchestrators erlaubt.

*Korrektur:* `changed_paths()` um `--no-standard-filter`-Semantik erweitern
(`git ls-files --others` ohne `--exclude-standard`, gefiltert gegen eine
explizite Artefakt-Allowlist), mindestens aber `orchestrator/**` unabhängig von
`.gitignore` fingerprinten. Zusätzlich `.lock` aus dem Wirkbereich von `*.lock`
nehmen (`!orchestrator/.lock` in `.gitignore`) und in `acquire_lock` ein
Fremdinhalt-Erkennen mit benanntem Aufräumhinweis ergänzen.

---

**L2-B-03 · Die Verbotsliste gefährlicher Flags ist mit dem dokumentierten `$VAR`-Idiom umgehbar**

*Verletzte Anforderung:* `AGENTS.md` Integritätsregel 8 — „Verboten sind
`--dangerously-skip-permissions`, `bypassPermissions`, Yolo- und
Full-Access-Modi in jeder Rolle"; A9 „Sicherheitsschienen (§5) … verbotene
Flags; Sandbox-/Permission-Modus je Rolle"; T5-D12-40 und T5-D12-41, beide
`belegt`.

*Datei/Zeile:* `orchestrator/orchestrate.sh:179-185` (PREFLIGHT greppt den
**Literalstring**), `:150-164` (`validate_role_cli`, gleiche Schwäche beim
`SAFE_MODE_PATTERN`), `:400` (`run_model` expandiert denselben String erneut per
`bash -c "$cmd"`).

PREFLIGHT prüft `${BUILDER_CMD} ${REVIEWER_CMD} ${QA_CMD}` als Zeichenkette.
`run_model` reicht dieselbe Zeichenkette später an `bash -c` weiter, das sie ein
zweites Mal expandiert. Variablenreferenzen im Rollenkommando sind dabei kein
Missbrauch, sondern die **vorgegebene Schreibweise** — `config.env.example:5-7`:

```sh
# Modelle. Der Prompt liegt quoting-sicher in $PROMPT_FILE.
BUILDER_CMD='codex exec --sandbox workspace-write < "$PROMPT_FILE"'
```

*Reproduktion.* T-2-Fall, `config.env` nach demselben Muster, plus ein Wrapper,
der die real übergebenen Argumente protokolliert:

```sh
BUILDER_EXTRA_FLAGS='--dangerously-skip-permissions'
BUILDER_CMD='bash tests/template/argspy.sh builder $BUILDER_EXTRA_FLAGS'
```

```text
$ bash orchestrator/orchestrate.sh
[20260806-010220] CONFIG: AUTONOMY=3 PLAN<=2 REWORK<=4 REBUILD@r4 ARBITER+2 TIMEOUT=30 RETRY=1x/0s MAX_MS=2 QA=0(ab M99) NOTIFY=an BUILDER=bash REVIEWER=bash
[20260806-010220] === M0 start ===
[20260806-010223] === M0 DONE ===
ORCH_EXIT=0                                   ← kein FATAL, kein WARN

$ sort -u argv.log
ARGV: builder --dangerously-skip-permissions  ← Flag erreicht die Rolle
```

PREFLIGHT meldet nichts, der Lauf endet mit Exit 0, und die Rolle läuft mit dem
verbotenen Flag. Dieselbe Indirektion hebelt `BUILDER_SAFE_MODE_PATTERN` aus:
der Pattern-Match greift auf `--sandbox workspace-write` im Literal, der
wirksame Modus entsteht erst bei der Expansion und kann ihn überschreiben.

*Testlücke.* A6 prüft die Verbotsliste an keiner Stelle — weder positiv (ein
Lauf mit verbotenem Flag muss FATAL geben) noch negativ. Beide Fixtures setzen
`BUILDER_REQUIRED_FLAGS=` und `BUILDER_SAFE_MODE_PATTERN=` leer
(`config-t2.env:10,16`), womit `validate_role_cli` ohnehin nur den `--help`-Lauf
macht.

*Abgrenzung zu Lauf 1.* L1-B-15 betrifft die **leere** Variable als Abschalter.
Neu ist hier der aktive Umgehungsweg über die Laufzeit-Expansion, der auch bei
korrekt gesetztem `SAFE_MODE_PATTERN` funktioniert.

*Korrektur:* Die Prüfung auf den tatsächlich ausgeführten Befehl verlagern —
`printf '%s' "$cmd" | envsubst`-äquivalente Vorexpansion vor dem Grep, oder
`run_model` das Kommando über ein Array statt über `bash -c` starten und die
Verbotsliste gegen `argv` prüfen. Mindestens: PREFLIGHT muss `$`-Referenzen in
Rollenkommandos außer `$PROMPT_FILE` ablehnen.

---

### HOCH

---

**L2-B-04 · Ein abgewiesener Doppelstart setzt den Heartbeat zurück und blendet den Watchdog**

*Verletzte Anforderung:* A6 T-4 (`watchdog=STALE watchdog-exit=1`); A3.4
(„`watchdog.sh` läuft per cron alle 15 min: Orchestrator-Prozess vorhanden, aber
summary-`ts` älter als 30 min → STALE-Meldung"); A3.1 („eine Datei, eine
Wahrheit"); T5-PATCH-04/-05 (`belegt`).

*Datei/Zeile:* `orchestrator/orchestrate.sh:82-89` (`fatal()` ruft
`refresh_status` und `notify_event FATAL`), `:113-114` (Aufruf aus
`acquire_lock`), `:75-80` (`refresh_status` → `status.sh`),
`orchestrator/status.sh:96,114` (`ts` neu gesetzt, `summary.json` ersetzt),
`orchestrator/watchdog.sh:29-41`.

`acquire_lock` weist einen Zweitstart korrekt ab — ruft dafür aber `fatal()`,
und das schreibt in den Zustand **des laufenden** Orchestrators.

*Reproduktion.* Ein hängender Lauf hält den Lock (lebender PID, Heartbeat eine
Stunde alt, Grenze 1800 s):

```text
Heartbeat: 2026-08-06T00:01:08+02:00   (jetzt: 2026-08-06T01:01:08+02:00)

=== A) Watchdog vor dem Timer-Tick ===
$ bash orchestrator/watchdog.sh
watchdog: STALE age=3600s pid=114677
WATCHDOG_EXIT=1

=== B) cron-Tick: orchestrate.sh wird vom Lock korrekt abgewiesen ===
$ bash orchestrator/orchestrate.sh
[20260806-010108] FATAL: Orchestrator läuft bereits (PID 114677).
ORCHESTRATE_EXIT=2
Heartbeat danach: 2026-08-06T01:01:08+02:00
summary.json:  {"phase":"fatal","needs_human":true,"exit":2,"reason":"Orchestrator läuft bereits (PID 114677)."}
Notify:        fatal

=== C) Watchdog nach dem Timer-Tick, hängender Lauf läuft weiter ===
$ bash orchestrator/watchdog.sh
watchdog: fresh age=0s pid=114677
WATCHDOG_EXIT=0
```

Zwei Folgen:

1. **Der Watchdog erblindet.** Genau die von BAUPLAN A2 empfohlene Kombination —
   `AUTONOMY_LEVEL=3`, „Nachtlauf per Timer (der Lock macht ihn gefahrlos)" —
   plus A3.4 („watchdog.sh läuft per cron alle 15 min") hebt die STALE-Erkennung
   auf: jeder Timer-Tick verjüngt den Heartbeat, bevor die 30-Minuten-Grenze
   erreicht wird. Ein hängender Lauf wird nie gemeldet. Die Zusicherung
   „der Lock macht ihn gefahrlos" trifft für den Lauf zu, aber nicht für die
   Überwachung.
2. **Falschalarm und falscher Leitstand im Normalfall.** Ein versehentlicher
   Doppelstart bei gesundem Lauf setzt `phase=fatal`, `needs_human=true`,
   `exit=2` und schickt ein `FATAL`-Notify. `STATUS.md` zeigt dem Menschen
   denselben Stand:
   `Stand: 2026-08-06T01:01:08+02:00 · Fortschritt: **0/2 fertig**`.
   Der laufende Orchestrator überschreibt das erst bei seiner nächsten Phase.

*Testlücke.* `test-t4-ops.sh:18-27` setzt den Lock von Hand und ruft nur den
Watchdog. Lock-Abweisung und Watchdog werden in keinem Test zusammen gefahren;
`notify.sh` wird ausschließlich mit `DONE` und `PARKED` aufgerufen (`:16-17`),
nie durch einen echten `fatal()`-Pfad.

*Korrektur:* `acquire_lock` darf bei fremdem, lebendem Lock nicht über `fatal()`
gehen — eigene Ausstiegsroutine ohne `refresh_status` und ohne `notify_event`,
Exit 2 mit Meldung auf stderr. Alternativ `refresh_status` in `fatal()` an
`LOCK_HELD = 1` binden.

---

**L2-B-05 · `qa_required()` bricht bei ziffernlosen Meilenstein-IDs; die Pflicht-QA parkt nicht, sondern läuft durch**

*Verletzte Anforderung:* A9 „Autonomie (Patch v2) … QA-Park"; T5-PATCH-10
(„Patch v2: inaktive Pflicht-QA parkt ohne Runde", `belegt`, Anker
`keine Rework-Runde wird verbraucht`); A2.1 Punkt 1 („Patch-Fassung gewinnt —
parkt vor Rundenverbrauch").

*Datei/Zeile:* `orchestrator/orchestrate.sh:484-486` (`milestone_number`),
`:488-493` (`qa_required`, Fehler in `:492`), `:664-667` (Park-Zweig),
`:138` (Manifestvertrag erlaubt die ID-Form ausdrücklich).

`milestone_number()` zieht per `sed -E 's/^[^0-9]*([0-9]+).*$/\1/'` eine Zahl aus
der ID. Enthält die ID keine Ziffer, gibt `sed` die Eingabe unverändert zurück
und `[ "$current" -ge "$required" ]` bricht ab. Die Manifestvalidierung
(`:138`) lässt solche IDs ausdrücklich zu: `^[A-Za-z][A-Za-z0-9_-]*$`. Für die
Presets `text` und `daten` ist das der Normalfall.

*Einheitsprobe:*

```text
id=M3             number=3        qa_required-rc=0
id=M4             number=4        qa_required-rc=0
id=M10            number=10       qa_required-rc=0
id=M08            number=08       qa_required-rc=0
id=M09            number=09       qa_required-rc=0
id=setup          number=setup    qa_required-rc=2  [: setup: integer expected
id=kapitel-eins   number=kapitel-eins qa_required-rc=2  [: kapitel-eins: integer expected
```

(Meine Ausgangsvermutung, führende Nullen wie `M08` würden oktal brechen, hat
diese Probe widerlegt — `[` rechnet Basis 10. Nur ziffernlose IDs brechen.)

*Reproduktion end-to-end.* Textprojekt-Meilensteine, QA ausgeschaltet und laut
Konfiguration ab dem ersten Meilenstein Pflicht:

```sh
milestones.json: ids "setup", "kapitel"
config.env:      QA_ENABLED=0     QA_REQUIRED_FROM=setup
```

```text
$ bash orchestrator/orchestrate.sh
orchestrator/orchestrate.sh: line 492: [: setup: integer expected
[20260806-010358] === setup DONE ===
orchestrator/orchestrate.sh: line 492: [: kapitel: integer expected
[20260806-010400] === kapitel DONE ===
[20260806-010400] Lauf beendet.
ORCH_EXIT=0

geparkt?   NEIN - kein einziger Meilenstein geparkt
QA-Marker? NEIN - QA lief nie
fertig:    orchestrator/state/kapitel/8-done.done orchestrator/state/setup/8-done.done
```

`qa_required` liefert rc 2, das wird in der `&&`-Kette als „false" gelesen, der
Park-Zweig läuft nie. Beide Meilensteine werden als `DONE` getaggt, obwohl die
als Pflicht konfigurierte QA nie stattgefunden hat. Der Shell-Fehler geht nach
stderr und erscheint weder in `orchestrate.log` noch in `summary.json`.

*Testlücke.* Der gesamte QA-Zweig ist in A6 toter Code: beide Fixtures setzen
`QA_ENABLED=0` **und** `QA_REQUIRED_FROM=M99` (`config-t2.env:19-20`), und die
Attrappe bricht bei `45-qa` mit „QA ist in diesen Szenarien deaktiviert" ab
(`fake-model.sh:139-142`).

*Bestätigung.* Deckt sich mit L1-B-11 und L1-B-23. Unabhängig reproduziert, hier
zusätzlich mit dem Nachweis, dass die Meilensteine tatsächlich bis `8-done.done`
und Exit 0 durchlaufen.

*Korrektur:* `qa_required` auf Indexvergleich im Manifest umstellen (Position von
`$ms` gegen Position von `$QA_REQUIRED_FROM` in `milestones.json`) statt auf
Ziffernextraktion; ist `QA_REQUIRED_FROM` keine gültige Manifest-ID, in PREFLIGHT
mit `fatal` abbrechen.

---

### NOTIZEN (kein Befundrang)

**L2-N-01 · `70-arbiter.md` ist der einzige Prompt ohne bezeichnetes Kontextmanifest**

A3.7 verlangt „Jeder Prompt trägt sein Kontextmanifest — die exakte Leseliste";
T5-D12-49 ankert dafür nur auf `50-code-review.md`.

```text
$ for f in orchestrator/prompts/*.md; do printf '%-40s %s\n' "$f" "$(grep -c Kontextmanifest "$f")"; done
orchestrator/prompts/10-acceptance.md    1
orchestrator/prompts/20-plan.md          1
orchestrator/prompts/30-plan-review.md   1
orchestrator/prompts/40-build.md         1
orchestrator/prompts/45-qa.md            1
orchestrator/prompts/50-code-review.md   1
orchestrator/prompts/60-rework.md        1
orchestrator/prompts/62-rebuild.md       1
orchestrator/prompts/70-arbiter.md       0
```

Inhaltlich trägt `70-arbiter.md:3` eine Leseliste („Lies ausschließlich
ARBITER-REQUEST.md, das aktuelle Verdict …"), nur ohne die Bezeichnung. Das ist
Kosmetik, kein Defekt — aber es zeigt, dass der T-5-Anker die Aussage „jeder
Prompt" nicht prüfen kann.

**L2-N-02 · T5-PATCH-15 belegt nur die Hälfte seiner eigenen Behauptung**

Die Zeile behauptet „LESSONS-Lesepfad **und** CONFIG-Provenienz", der Anker
`CONFIG: AUTONOMY=` deckt nur die zweite Hälfte:

```text
$ grep -c LESSONS orchestrator/orchestrate.sh
0
```

Die Behauptung selbst stimmt — der Lesepfad steht in allen sechs von BAUPLAN A2
geforderten Prompts (20/30/40/50/60/62, je ein Treffer). Nur belegt der Anker
sie nicht. Positivkontrolle, kein Befund.

---

## 4. Warum A6 grün bleibt: die Prüfmethodik von T-5

Alle fünf Befunde liegen hinter grünen T-5-Ankern. Die Ursache steht in einer
Zeile — `tests/template/test-t5-inventory.py:51`:

```python
if evidence not in path.read_text(encoding="utf-8"):
```

Das ist ein Substring-Test. Er beweist, dass ein Bezeichner in einer Datei
**vorkommt**, nie dass die dahinterliegende Mechanik trägt. Konkret:

| T-5-Zeile | Anker vorhanden | Mechanik trägt | Befund |
|---|---|---|---|
| T5-D12-31 Gate territory | ✓ | ✗ | L2-B-02 |
| T5-D12-40 Bypass-Flags verboten | ✓ | ✗ | L2-B-03 |
| T5-D12-41 Sandbox-/Permission-Modi geprüft | ✓ | ✗ | L2-B-03 |
| T5-PATCH-04 Lock und verwaiste Locks | ✓ | ✗ | L2-B-02, L2-B-04 |
| T5-PATCH-10 Pflicht-QA parkt ohne Runde | ✓ | ✗ | L2-B-05 |
| T5-NEW-09 generischer MCP-Connector | ✓ | ✗ | L2-B-01 |
| T5-PATCH-15 LESSONS + CONFIG | ✓ (halb) | ✓ | L2-N-02 |

Die Ergebnisregel in `docs/T5-INVENTAR.md:126-129` — „T-5 ist nur bestanden, wenn
das Prüfskript alle Tabellenzeilen parst, jeder `belegt`-Anker in der genannten
Datei vorkommt …" — beschreibt damit genau, was der Test kann, und der Test
erfüllt sie. Was A6/T-5 nicht leisten kann, ist die Aussage aus BAUPLAN A6:
„die Frage ‚sind alle Features drin?' wird damit zum Gate statt zum Gefühl."
Sie wird zum Gate über Zeichenketten, nicht über Verhalten.

---

## 5. Abgleich mit Lauf 1

| Lauf-2-Befund | Verhältnis zu Lauf 1 |
|---|---|
| L2-B-01 MCP-Exfiltration | **Neu und widersprechend.** Lauf 1 bewertet „Lernen und Spur" mit **PASS** und beruft sich dabei auf „MCP-Selbsttest 20/20"; die Entkopplungsprüfung nennt den MCP-Server „sauber generalisiert". Beides bleibt sachlich richtig — der Selbsttest läuft 20/20, die Generalisierung stimmt. Nur deckt keine der beiden Aussagen den Lesepfad `grep -rn` ab. |
| L2-B-02 Lock-Territorium | **Bekannte Ursache, neue Eskalation.** L1-B-02 beschreibt die `.gitignore`-Blindheit für die Beweisspur (`orchestrator/logs/**`). Dass dieselbe Blindheit über `orchestrator/.lock/` einen permanenten, von einer Modellrolle auslösbaren Ausfall erlaubt, ist neu. L1-B-17 betrifft ein anderes Lock-Problem. |
| L2-B-03 Flag-Umgehung | **Neu.** L1-B-15 betrifft die leere `SAFE_MODE_PATTERN`-Variable als Abschalter, L1-B-08 den Export von `config.env` in die Modellumgebung. Die Laufzeit-Reexpansion durch `bash -c` ist in Lauf 1 nicht adressiert. |
| L2-B-04 Watchdog | **Neu.** In `abnahme-lauf1.md` kein einziger Treffer auf „watchdog" oder „heartbeat". |
| L2-B-05 Pflicht-QA | **Bestätigt.** Deckt sich mit L1-B-11 (`qa_required` bricht bei ziffernlosen IDs) und L1-B-23 (QA-Rolle vollständig ungetestet). Unabhängig reproduziert. |

Nicht nachgeprüft habe ich die übrigen Lauf-1-Befunde (L1-B-01, -03 bis -10,
-12 bis -22, -24). Ihr Fortbestehen ist von diesem Bericht weder bestätigt noch
widerlegt.

---

## 6. A9-Abdeckung aus Sicht dieses Laufs

Nur Blöcke, zu denen dieser Lauf eigene Belege hat. Blöcke ohne eigene Prüfung
sind als solche gekennzeichnet.

| A9-Block | Urteil Lauf 2 | Beleg |
|---|---|---|
| Rollen (§1), Territorienkarte, Erzwingung per git-diff | **FAIL** | L2-B-02: Schreibzugriff auf `orchestrator/**` unentdeckt, Lauf endet Exit 0. Positivkontrolle: sichtbarer Pfad wird korrekt erkannt und zurückgerollt (T-2, `WARN: reviewer verletzt Territorium … genau ein Retry`) |
| Sicherheitsschienen (§5): verbotene Flags, Sandbox-/Permission-Modus | **FAIL** | L2-B-03: `ARGV: builder --dangerously-skip-permissions` bei Exit 0 und ohne PREFLIGHT-Meldung |
| Betrieb (§6): STATUS-Board, `state/<MS>`, `summary.json` | **FAIL** | L2-B-04: `summary.json` eines gesunden Laufs wird von einem Fremdprozess auf `phase=fatal`/`needs_human=true`/`exit=2` gesetzt |
| Autonomie (Patch v2): Lock, Notify, QA-Park | **FAIL** | L2-B-02 (Lock nicht selbstheilend, Exit 2 dauerhaft), L2-B-04 (Notify FATAL ohne Anlass), L2-B-05 (QA-Park fällt aus, Exit 0) |
| Phasen (§2) | **teilweise belegt** | Ablauf PREFLIGHT→…→DONE in T-2/T-3 real gefahren; QA-Phase in A6 nie ausgeführt (L2-B-05) |
| Verhandlung (§3) | **belegt** | T-3: `verdict-arbiter.json` HUMAN → `ESCALATION-M0.md` + `ESCALATION.md` → Exit 3, `verdict()`-Schema erzwingt `ref`-Pflicht |
| Toolchain (A3.9) | **belegt** | T-1 Exit 0: `mcp-runtime: version=1.28.1 env=external`, `mcp==1.28.1` gepinnt, keine `.venv` im Baum, `MCP_ENV_DIR` außerhalb des Repos, bootstrap zweimal idempotent |
| Kontexthygiene (§5b) | **teilweise belegt** | Resume-Verbot in `:180-182` vorhanden; Kontextmanifest in 8 von 9 Prompts bezeichnet (L2-N-01) |
| Konstruktionsprinzipien, Anti-Halluzination (§7a), Gates (§4), Lernen und Spur | **in diesem Lauf nicht eigenständig geprüft** | — |
| **A6/T-5 selbst** | **FAIL** | Abschnitt 4: Substring-Prüfung kann keine der sechs betroffenen Zeilen tragen |

---

## 7. Ausgeführte Prüfkommandos

| # | Kommando (gekürzt) | Exit / Ergebnis |
|---|---|---|
| 1 | `bash tests/template/run-all.sh` | **0** — `A6 PASS: T-1 T-2 T-3 T-4 T-5`, 11,5 s |
| 2 | `bash tests/template/test-t1-bootstrap.sh` | **0** — `T-1 PASS … tunnel=0` |
| 3 | `bash tests/template/test-t2-rework.sh` | **0** — `T-2 PASS … exit=0` |
| 4 | `bash tests/template/test-t3-ladder.sh` | **0** — `T-3 PASS … exit=3` |
| 5 | `bash tests/template/test-t4-ops.sh` | **0** — `T-4 PASS … watchdog-exit=1` |
| 6 | `python3 tests/template/test-t5-inventory.py` | **0** — `T-5 PASS: rows=112 …` |
| 7 | `git check-ignore -v --no-index orchestrator/.lock/{,pid,stray}` | **0** je Pfad — `.gitignore:22:*.lock` (L2-B-02) |
| 8 | Fixture-Lauf, Builder schreibt `orchestrator/.lock/stray` | **0** — keine Territoriumsmeldung, Datei überlebt (L2-B-02) |
| 9 | Folgestart auf demselben Repo | **2** — `FATAL: verwaister Lock ist nicht leer` (L2-B-02) |
| 10 | Dritter Start, unverändert | **2** — Zustand heilt nicht (L2-B-02) |
| 11 | Fixture-Lauf mit `BUILDER_CMD='… $BUILDER_EXTRA_FLAGS'` | **0** — `ARGV: builder --dangerously-skip-permissions` (L2-B-03) |
| 12 | `watchdog.sh` bei altem Heartbeat | **1** — `watchdog: STALE age=3600s` (L2-B-04) |
| 13 | `orchestrate.sh` bei gehaltenem Lock | **2** — `FATAL: Orchestrator läuft bereits`, Heartbeat neu, Notify `fatal` (L2-B-04) |
| 14 | `watchdog.sh` erneut, Lauf hängt weiter | **0** — `watchdog: fresh age=0s` (L2-B-04) |
| 15 | `qa_required` gegen 7 vertragsgültige IDs | 5× **0**, 2× **2** + `[: setup: integer expected` (L2-B-05) |
| 16 | Fixture-Lauf mit IDs `setup`/`kapitel`, `QA_ENABLED=0` | **0** — beide DONE, kein Park, QA nie gelaufen (L2-B-05) |
| 17 | `server.py`: `lies` / `git diff` / `tail` auf `config.env` | je abgelehnt — Guards halten (L2-B-01) |
| 18 | `server.py`: `befehl('grep -rn API orchestrator')` | **0** — Klartext-Key in der Antwort (L2-B-01) |
| 19 | `grep -c Kontextmanifest` über alle 9 Prompts | 8×1, `70-arbiter.md` 0 (L2-N-01) |
| 20 | `grep -c LESSONS orchestrator/orchestrate.sh` | **0** (L2-N-02) |
| 21 | `git status --porcelain --untracked-files=all` im Prüfrepo | leer — nichts geändert |

---

## 8. Nicht geprüft / Restunsicherheiten

1. **T-1 mit echtem Tunnel.** `HARNESS_T1_WITH_TUNNEL=1` wurde nicht gefahren
   (kein `cloudflared` im Prüfstand). Der in `docs/ABNAHME.md:24-31`
   festgehaltene Nachweis ist damit nicht gegengeprüft. L2-B-01 stützt sich für
   die Expositionslage auf den Code (`bootstrap.sh:205-222`,
   `server.py:451-471`), nicht auf einen ausgeführten Tunnel.
2. **Alle übrigen Lauf-1-Befunde** außer L1-B-02, -11, -15, -17, -23 habe ich
   nicht nachgeprüft.
3. **Gate-Beispiele.** `gates.d/*.example` wurden gelesen, aber außer
   `82-territory` und `87-golden-adr` nicht ausgeführt; T-2/T-3 fahren zwei
   eigens gebaute Fixture-Gates.
4. **Projektierungsschicht (A7)** und die Presets wurden in diesem Lauf nicht
   geprüft.
5. **Schwere-Einstufung** ist ein Vorschlag, kein Verdict. Die Reproduktionen
   sind der belastbare Teil; die Einordnung als kritisch/hoch ist meine
   Bewertung.
6. **`M08`/`M09`-Hypothese widerlegt.** Ich hatte einen Oktal-Parsefehler
   vermutet; die Probe in Abschnitt 3/L2-B-05 zeigt rc 0. Nur ziffernlose IDs
   brechen.

---

## 9. Vorgeschlagene Reihenfolge der Korrekturen

1. **L2-B-01** — Geheimnisse verlassen die Maschine. Sofort: `grep`-Pfade durch
   `pruefe_pfad()` schicken bzw. `--exclude=*.env` erzwingen; `config.env` ohne
   Geheimnisse betreiben. Zusätzlich `test_allowlist.py` in `run-all.sh`
   aufnehmen — der Test existiert, läuft aber nie in der Abnahme.
2. **L2-B-02** — Territoriumsprüfung darf nicht an `.gitignore` hängen.
   `orchestrator/**` unabhängig davon fingerprinten, `orchestrator/.lock` aus
   `*.lock` herausnehmen.
3. **L2-B-03** — Verbotsliste gegen den expandierten Befehl prüfen oder
   `$`-Referenzen außer `$PROMPT_FILE` in Rollenkommandos ablehnen.
4. **L2-B-04** — `acquire_lock` bei fremdem lebendem Lock ohne `refresh_status`
   und ohne `notify_event` beenden.
5. **L2-B-05** — `qa_required` auf Manifest-Indexvergleich umstellen;
   `QA_REQUIRED_FROM` in PREFLIGHT als Manifest-ID validieren.
6. **Danach T-5 nachschärfen** — für jede der sechs in Abschnitt 4 genannten
   Zeilen einen ausführenden Test statt eines Suchankers. Ohne diesen Schritt
   bleibt die nächste Abnahme genauso grün wie diese.
