# Abnahmebericht harness-template

> Historischer Lauf; Pfadangaben dokumentieren den damaligen Stand.

## 1. Gesamturteil: **FAIL**

Die vorgeschriebene Abnahme läuft grün (`bash tests/template/run-all.sh` → Exit 0, „A6 PASS: T-1 T-2 T-3 T-4 T-5"). Das ist reproduzierbar und ich habe es selbst gefahren. Die Suite prüft jedoch nur den glücklichen Pfad einer einzigen Autonomiestufe mit zwei eigens gebauten Fixture-Gates. Meine Gegenproben haben drei kritische und vier hohe Befunde erzeugt, die jeweils **stille Falschmeldungen** produzieren: der Orchestrator meldet `DONE`/Exit 0, während die zugesagte Sicherung nicht stattgefunden hat. Damit sind A9-Blöcke „Sicherheitsschienen (§5)", „Rollen (§1)", „Betrieb (§6)", „Phasen (§2)", „Gates (§4)" und „Autonomie (Patch v2)" nicht erfüllt. T-5 kann seine eigene Vollständigkeitsbehauptung strukturell nicht belegen.

---

## 2. Befunde

### KRITISCH

---

**B-01 · `set -e` schützt die Meilensteinschleife nicht — `DONE` ohne einen einzigen Commit und ohne Tags**

*Verletzte Anforderung:* A9 §5 „lineare Historie, Tags je Phase … sauberer Baum"; A3.5 Exit-Codes; A3.1 (`summary.json` = eine Wahrheit); docs/12 §5.

*Datei/Zeile:* `orchestrator/orchestrate.sh:758` (`if run_ms "$ms"; then rc=0; else rc=$?; fi`), Folgestellen `:442` (`git diff --cached --quiet || git commit`), `:481` (`git tag -a`), `:713` (PROGRESS-Prüfung), `:720`. Vorherige Fassung (`set +e; run_ms; rc=$?; set -e`, `d0792f0:691`) hatte denselben Effekt — der Refactor in `865840e` hat ihn strukturell zementiert.

Bash ignoriert `-e` im gesamten dynamischen Umfang einer Funktion, die in einer Bedingung läuft. Nachweis:

```
$ bash -c 'set -e; f(){ false; echo "WEITER trotz Fehler"; }; if f; then echo rc0; else echo "rc=$?"; fi'
WEITER trotz Fehler
rc0
exit=0
```

*Reproduzierendes Kommando* (frischer Laptop ohne git-Identität — `bootstrap.sh` prüft sie nicht):

```bash
bash mkcase.sh /tmp/probe-ident && cd /tmp/probe-ident
git config --unset user.name; git config --unset user.email
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null HOME=/tmp/probe-ident-home
MCP_ENV_DIR=/tmp/probe-ident-venv MCP_PYTHON=… TUNNEL_MODE=quick PROJECT_SLUG=probe-ident PORT=31111 \
  bash bootstrap.sh --non-interactive --no-start          # Exit 0
PATH=…/fake-bin:$PATH FAKE_NOTIFY_LOG=/tmp/pid.log bash orchestrator/orchestrate.sh M0
```

*Tatsächliche Ausgabe / Exitcode:*

```
bootstrap: summary.json contract v1 gültig
BOOTSTRAP_EXIT=0
…
fatal: empty ident name (for <user@host.localdomain>) not allowed
[20260806-003252] === M0 DONE ===
[20260806-003252] Lauf beendet.
EXITCODE=0
--- notify: done
$ git log --oneline        → f7ec5f4 probe: initial state     (kein Phasen-Commit)
$ git tag --list           → (leer)                            (kein plan/M0, kein done/M0)
$ jq -c '{phase,exit}' orchestrator/state/summary.json
{"…","phase":"done","exit":0}
$ grep '^| M0' STATUS.md   → | M0 | … | ✅ | fertig |
```

Der Meilenstein gilt als fertig, `8-done.done` liegt, der Betreiber bekommt einen DONE-Push, der Leitstand sieht „fertig" — und im Repo steht kein Commit und kein Tag. Auch die PROGRESS-Prüfung fällt offen (`git diff plan/M0..HEAD` scheitert an der fehlenden Ref und gilt als „geändert"). Explizite `fatal`-Wächter feuern weiterhin (belegt in B-09), aber **jedes ungeprüfte Kommando** in `run_ms` und allem, was es aufruft, schlägt still fehl.

*Minimale Korrektur:* `run_ms`-Ergebnis über eine Variable statt über eine Bedingung holen (`run_ms "$ms" || rc=$?` in einer `set -e`-neutralen Hülle reicht nicht — nötig ist explizite Fehlerbehandlung), mindestens aber `git add/commit/tag` in `commit_phase`, `tag_once` und `run_ms` einzeln prüfen und bei Fehlschlag `fatal` aufrufen; zusätzlich `git config user.name/user.email` in `bootstrap.sh` und im PREFLIGHT verifizieren.

---

**B-02 · Territoriumsprüfung ist blind für `.gitignore`-Pfade — Modelle können die Beweisspur fälschen**

*Verletzte Anforderung:* A9 §1 („Erzwingung per git-diff je Phase"), §5 („Logs: jeder Modellaufruf vollständig unter `orchestrator/logs/`"), AGENTS.md:46-50 („`orchestrator/**` … Betreiber-Territorium"), Integritätsregel 4.

*Datei/Zeile:* `orchestrator/orchestrate.sh:271` — `git ls-files --others --exclude-standard -z` schließt ignorierte Pfade aus; `.gitignore:17-32` ignoriert u. a. `reports/`, `artifacts/`, `dist/`, `coverage/`, `orchestrator/logs/*.log`, `orchestrator/logs/*-prompt.md`.

*Reproduzierendes Kommando:* Fake-Builder schreibt in `40-build` zusätzlich `reports/evil.txt`, `dist/hack.js`, `artifacts/hack.bin`, `coverage/hack.txt`, `orchestrator/logs/M0-40-build-r1-TAMPERED.log`; in `60-rework` überschreibt er den archivierten Acceptance-Prompt und das Build-Transkript. Danach `bash orchestrator/orchestrate.sh`.

*Tatsächliche Ausgabe / Exitcode:*

```
EXITCODE=0
--- Territoriumsverletzung gemeldet? 1        (nur die beabsichtigte Reviewer-Probe)
-rw-r--r-- … reports/evil.txt  dist/hack.js  artifacts/hack.bin  coverage/hack.txt
-rw-r--r-- … orchestrator/logs/M0-40-build-r1-TAMPERED.log
[orchestrator/logs/M0-10-acceptance-r1-…-prompt.md]  FAELSCHUNG durch das Modell in Runde 2
[orchestrator/logs/M0-40-build-r1-….log]             FAELSCHUNG durch das Modell in Runde 2
--- M0 DONE?  orchestrator/state/M0/8-done.done ; done/M0 ; done/M1
```

Positivkontrolle (getrackte Datei) greift korrekt: Manipulation von `orchestrator/state/M0/gates.json` → `WARN: builder verletzt Territorium … genau ein Retry` → `FATAL … wiederholt` → Exit 2. Die Lücke betrifft ausschließlich ignorierte Pfade — und dort liegt das gesamte Modelltranskript.

*Minimale Korrektur:* `changed_paths()` auf `git ls-files --others` **ohne** `--exclude-standard` erweitern (mit gezielter Ausnahme für `orchestrator/logs/` **nur** in Schreibrichtung des Orchestrators) oder die Logs vor jeder Modellphase per Hash-Manifest sichern und nach der Phase gegenprüfen.

---

**B-03 · Fehler beim Prompt-Rendern bleiben unbemerkt; PREFLIGHT prüft die Vertragspfade nicht**

*Verletzte Anforderung:* BAUPLAN A3:171 „PREFLIGHT prüft die Vertragspfade beim Start"; A9 §5b „Kontextmanifest je Prompt"; A3.3.

*Datei/Zeile:* `orchestrator/orchestrate.sh:232-242` (`render_prompt` endet auf `printf`, sed-Status geht verloren), `:390` (`render_prompt … > "$PROMPT_FILE"` ungeprüft), `:166-230` (`preflight()` prüft git/jq/bash, Manifest, Limits, Rollen-CLI, Toolchain, sauberen Baum — **keine** Vertragspfade).

*Reproduzierendes Kommando:*

```bash
rm -f orchestrator/prompts/10-acceptance.md && git commit -qam "prompt weg"
bash orchestrator/orchestrate.sh M0
```

*Tatsächliche Ausgabe / Exitcode:*

```
EXITCODE=0
[20260806-003252] === M0 DONE ===
$ cat orchestrator/logs/M0-10-acceptance-r1-…-prompt.md
(leer, bis auf)
Git-Hinweis: Der Orchestrator committet nach der Territoriumsprüfung. …
→ 111 Bytes: keine Rolle, kein Kontextmanifest, keine Kriterien
```

Der Reviewer erhält als ACCEPTANCE-Auftrag eine Zeile Git-Hinweis; der Meilenstein läuft bis DONE durch. Verwandter Auslöser: ein `|` in `criteriaRef` bricht die sed-Kette (`sed: -e expression #3, char 25: unknown option to 's'`) und erzeugt ebenfalls einen leeren Prompt — dort schlug erst das Fake-Modell an (Exit 2).

*Minimale Korrektur:* `render_prompt` mit `|| fatal` absichern, sed-Delimiter auf ein in IDs unmögliches Zeichen wechseln und in `preflight()` die Existenz von `prompts/{10,20,30,40,45,50,60,62,70}`, `handoff/SCHEMA.md`, `contracts/PROTOCOLS.md`, `gates.d/`, `state/`, `reference/anchors/` prüfen.

---

### HOCH

---

**B-04 · `AUTONOMY_LEVEL=0` erreicht nie mehr als `20-plan` (Livelock)**

*Verletzte Anforderung:* BAUPLAN A2 „`AUTONOMY_LEVEL` 0–3 … 0 phasenweise mit Halt".
*Datei/Zeile:* `orchestrator/orchestrate.sh:38-40` (`PHASES_PER_RUN=1`), `:444-448`, `:634-656` (Planschleife ohne Runden-Marker).

```bash
sed -i 's/^AUTONOMY_LEVEL=3/AUTONOMY_LEVEL=0/' orchestrator/config.env
for i in 1 2 3 4 5 6 7; do bash orchestrator/orchestrate.sh; done
```

```
Lauf 1 -> exit=0 phase=10-acceptance
Lauf 2 -> exit=0 phase=20-plan  Halt nach Phase 20-plan
Lauf 3 -> exit=0 phase=20-plan  Halt nach Phase 20-plan
… Lauf 7 -> exit=0 phase=20-plan  Halt nach Phase 20-plan
$ git log --format=%s | head -7   → 6× "orch(M0): builder 20-plan r1"
```

Da für `20-plan` kein `.done`-Marker existiert, wird die Phase bei jedem Aufruf neu gefahren und der Halt greift erneut davor. Stufe 0 ist damit unbrauchbar und in keinem Test abgedeckt (T-2/T-3 fahren Stufe 3).
*Korrektur:* Rundenbezogenen Marker (`state/<MS>/plan-r<n>-planned.done`) setzen oder den Halt erst nach dem Phasenpaar auslösen.

---

**B-05 · Gate-Status `error` wirkt exakt wie `fail`: verbrennt Rework-Runden, löst Rebuild aus, parkt trotz PASS-Verdict**

*Verletzte Anforderung:* A3.2 „Exit 2 = error (Infrastruktur — **zählt nicht als Builder-Fehlschlag**)"; `contracts/PROTOCOLS.md:66`; Patch v2 README §4 („Stryker-Tod ⇒ error, Infra, kein Builder-fail").
*Datei/Zeile:* `orchestrator/orchestrate.sh:687` (`[ "$gate_rc" = 0 ]`), `orchestrator/verifier.sh:98-99`.

```bash
# Gate liefert dauerhaft exit 2, Reviewer urteilt durchgehend PASS/blocking=[]
bash orchestrator/orchestrate.sh
```

```
gate behavior: error — behavior: infra error        (r1)
RUN builder 60-rework (M0 r2) … gate behavior: error
RUN builder 60-rework (M0 r3) … gate behavior: error
REBUILD M0: Builder-Territorium zurück auf plan/M0
RUN builder 62-rebuild (M0 r4) … gate behavior: error
PARKED M0: Codepfad festgefahren (Gates rc=2, Verdict=PASS); Arbiter benötigt HUMAN.
EXITCODE=3
$ jq -c '{verdict,blocking}' orchestrator/handoff/M0/verdict-code.json
{"verdict":"PASS","blocking":[]}
```

Eine Infrastrukturstörung kostet drei Rework-Runden und wirft im Rebuild das Builder-Territorium weg (`git rm` auf `REBUILD_PATHS`) — genau die M3-Deadlock-Klasse, gegen die der Patch die `error`-Klasse eingeführt hat.
*Korrektur:* Bei `gate_rc=2` ohne `fail`-Gates keine Runde erhöhen und keinen Rebuild auslösen; stattdessen begrenzt wiederholen und danach mit eigener Begründung („Infrastruktur") parken.

---

**B-06 · Nicht auflösbarer deps-Graph → Exit 1 (vertragsfremd), kein FATAL, kein Notify, `summary.json` bleibt auf `preflight`**

*Verletzte Anforderung:* A3.5 (nur 0/2/3); A3.4 (FATAL-Notify); A3.1.
*Datei/Zeile:* `orchestrator/orchestrate.sh:772-781`, insbesondere `:775` — das `exit 1` in der `while`-Schleife beendet die **aktuelle** Shell und erreicht das dahinterliegende `fatal "kein ausführbarer Meilenstein…"` (`:780`) nie. `validate_manifest` (`:135-147`) prüft Referenzintegrität und Selbstbezug, aber keine Zyklen.

```bash
cat > orchestrator/milestones.json <<'EOF'
[{"id":"M0","title":"a","criteriaRef":["K-M0-1"],"deps":["M1"],"effort":"low"},
 {"id":"M1","title":"b","criteriaRef":["K-M1-1"],"deps":["M0"],"effort":"low"}]
EOF
bash orchestrator/orchestrate.sh
```

```
[…] M0 wartet auf: M1
[…] M1 wartet auf: M0
EXITCODE=1
$ jq -c '{phase,exit,needs_human,reason}' orchestrator/state/summary.json
{"phase":"preflight","exit":null,"needs_human":false,"reason":""}
--- notify log: (keine Notify-Datei — kein FATAL gesendet)
```

*Korrektur:* `exit 1` durch ein Flag ersetzen (`all_done=0; break`) und `validate_manifest` um eine Zyklenprüfung erweitern.

---

**B-07 · `orchestrate.sh <MS>` mit offenen deps meldet Exit 0 und `phase:"done"` — Regression gegenüber Patch v2**

*Verletzte Anforderung:* A9 „Autonomie (Patch v2): Meilenstein-Graph"; A3.1/A3.5.
*Datei/Zeile:* `orchestrator/orchestrate.sh:751-754` und `:772` (`[ -z "$TARGET" ]` schließt den Fatal-Zweig aus). Quelle: `sources/patch-v2/…/full/orchestrator/orchestrate.sh:347` — dort `die "$MS: Abhängigkeiten offen:$DEPS_WAIT"`.

```bash
bash orchestrator/orchestrate.sh M1     # M0 noch offen
```

```
[…] M1 wartet auf: M0
[…] Lauf beendet.
EXITCODE=0
{"contract":1,"phase":"done","milestone":{"id":"M0","index":1,"total":2},"exit":0,"needs_human":false}
```

*Korrektur:* Bei gesetztem `TARGET` und `DEPS_WAIT != ""` `fatal` aufrufen.

---

### MITTEL

---

**B-08 · Gesamter `config.env`-Inhalt — inklusive `TUNNEL_TOKEN` und API-Keys — wird in jedes Modellkommando exportiert**

*Anforderung:* A9 §5 Sicherheitsschienen; `bootstrap.sh:226` / README („Connector-URL … wie ein Geheimnis behandeln").
*Datei/Zeile:* `orchestrator/orchestrate.sh:17-20` (`set -a; source "$CONFIG"; set +a`), `:400` (`bash -c "$cmd"`); `bootstrap.sh:129` schreibt `TUNNEL_TOKEN` in dieselbe Datei.

```
$ grep -h 'LEAK' orchestrator/logs/M0-*.log
LEAK TUNNEL_TOKEN=GEHEIM-TUNNEL-TOKEN-123 API=sk-GEHEIM-API-KEY-456
```
(Exit 0; das Fake-Modell hat schlicht seine eigene Umgebung ausgegeben.)

*Korrektur:* Geheimnisse aus `config.env` in eine separate, nicht exportierte Datei trennen und `run_model` mit `env -u TUNNEL_TOKEN -u …` bzw. einer Allowlist starten.

---

**B-09 · Presets `text` und `daten` beschreiben Reviewer-Territorien, die der Orchestrator nicht vergeben kann**

*Anforderung:* A7.4.
*Datei/Zeile:* `orchestrator/orchestrate.sh:315-338` — nur `BUILDER_EXTRA_PATHS_REGEX` (`:333`) existiert; `config.env.example:77`. `projektierung/presets/text/PRESET.md` erklärt `stilbibel.md`, `figurenbibel.md`, `weltbibel.md` zu „normative Anker, Reviewer-Besitz"; `presets/daten/PRESET.md` ebenso `schemas/**`.

```bash
# Reviewer legt in 10-acceptance stilbibel.md an
bash orchestrator/orchestrate.sh M0
```
```
WARN: reviewer verletzt Territorium: stilbibel.md — genau ein Retry mit Hinweis
FATAL: reviewer verletzt Territorium wiederholt: stilbibel.md
EXITCODE=2
```
*Korrektur:* `REVIEWER_EXTRA_PATHS_REGEX` und `QA_EXTRA_PATHS_REGEX` analog zum Builder-Hook einführen und in `config.env.example` sowie den Presets dokumentieren.

---

**B-10 · T-5 ist selbstbestätigend und kann seine Vollständigkeitsbehauptung nicht belegen**

*Anforderung:* A6 T-5 („jede Funktion aus Demiurgs orchestrate.sh, AGENTS.md, docs/12 und Patch v2 ist … nachgewiesen oder … begründet"); Beleg-Regel.
*Datei/Zeile:* `tests/template/test-t5-inventory.py:62` — `minimum = {"ORCH":12,"AGENT":5,"D12":64,"PATCH":15,"D14":7,"NEW":9}`.

```
$ grep -o '^| T5-[A-Z0-9]*' docs/T5-INVENTAR.md | … | sort | uniq -c
      5 AGENT   64 D12   7 D14   9 NEW   12 ORCH   15 PATCH
```

Die „Mindestabdeckung" ist exakt die Ist-Zeilenzahl der selbst geschriebenen Tabelle; die Schwelle kann nie greifen. Der Test liest keine Quelle (docs/12, docs/14, Patch v2, Demiurg-AGENTS) und prüft nur, ob ein selbstgewählter Suchanker in der selbstgenannten Datei vorkommt. Beispiel für die Schwäche der Anker: `T5-D12-45 „Vollständige Modelllogs und Promptarchiv"` gilt als „belegt", weil der String `Jeder Modellaufruf erzeugt` in PROTOCOLS.md steht — die Eigenschaft selbst ist durch B-02 und B-12 verletzt.
*Korrektur:* Für die Kategorien ORCH/D12/D14/PATCH die Sollzeilen aus einer versionierten, aus den Quellen abgeleiteten Referenzliste ziehen und Suchanker gegen ausführbares Verhalten statt gegen Zeichenketten prüfen.

---

**B-11 · `qa_required()` bricht bei Meilenstein-IDs ohne Ziffer — Pflicht-QA fällt still aus**

*Anforderung:* A9 „Autonomie (Patch v2): QA-Park"; `contracts/PROTOCOLS.md:41` erlaubt jede ID nach `^[A-Za-z][A-Za-z0-9_-]*$`.
*Datei/Zeile:* `orchestrator/orchestrate.sh:484-493`.

```bash
# milestones.json mit id "SETUP", QA_REQUIRED_FROM=M3, QA_ENABLED=0
bash orchestrator/orchestrate.sh
```
```
orchestrator/orchestrate.sh: line 492: [: SETUP: integer expected
[…] === SETUP DONE ===
EXITCODE=0
```
Der Park-Zweig „QA-Route inaktiv, aber QA ist ab … Pflicht" greift nicht. Gleiches gilt für gemischte Schemata (`MV1` → 1 < 3).
*Korrektur:* Reihenfolge über den Index im Manifest statt über die aus der ID extrahierte Zahl bestimmen; bei nicht auswertbarer Grenze `fatal`.

---

**B-12 · Retry überschreibt das Log des fehlgeschlagenen Versuchs**

*Anforderung:* A3.3/A9 §5 „vollständige Logs"; `contracts/PROTOCOLS.md:100-102`.
*Datei/Zeile:* `orchestrator/orchestrate.sh:412` und `:427` — `log_file="…-r$round-$(TS).log"` bei Sekundenauflösung.

```
$ grep '20-plan' orchestrator/logs/orchestrate.log
[…002414] RUN builder 20-plan (M0 r1, Versuch 1) -> …/M0-20-plan-r1-20260806-002414.log
[…002414] WARN: Transportfehler builder/20-plan rc=75 — Retry 1/1 …
[…002414] RUN builder 20-plan (M0 r1, Versuch 2) -> …/M0-20-plan-r1-20260806-002414.log
$ ls orchestrator/logs/ | grep '^M0-20-plan'
M0-20-plan-r1-20260806-002414.log        (nur eine Datei: der erfolgreiche 2. Versuch)
```
Dasselbe trifft den Territoriums-Retry — dort geht genau das Transkript verloren, das die Verletzung belegt.
*Korrektur:* Versuchszähler in den Dateinamen (`-a$try`) aufnehmen.

---

**B-13 · `docs/ABNAHME.md` enthält einen T-1-Nachweis, den das committete Skript nicht erzeugen kann**

*Anforderung:* A6 Beleg-Regel („keine Abnahme ohne ausgeführten Kommando-Output").
*Datei/Zeile:* `docs/ABNAHME.md:18` vs. `tests/template/test-t1-bootstrap.sh:65`.

```
ABNAHME.md:18  T-1 PASS: bootstrap=2 summary=contract-v1 repo-env=absent mcp-manifest=pinned
Skript:65      echo "T-1 PASS: … mcp-manifest=pinned tunnel=${HARNESS_T1_WITH_TUNNEL:-0}"
```
Das Feld `tunnel=` fehlt; der Block stammt aus einer Vorversion. Beide Dateien liegen im selben Commit `865840e`.
*Korrektur:* Nachweisblock neu erzeugen oder als Vorversion kennzeichnen.

---

**B-14 · Commit `865840e` bündelt vier Arbeitspakete unter einer Testmeldung**

*Anforderung:* A10 §3 „Ein Commit je Arbeitspaket mit sprechender Message"; Prüfauftrag A.
*Beleg:* `git show 865840e --stat` — neben `tests/template/**` enthält er (a) die vollständige Neufassung der Ownership-Mechanik in `orchestrator/orchestrate.sh` (`path_fingerprint`, `snapshot_worktree`, `restore_worktree`, `clear_worktree_snapshot`, Umbau von `ownership_check`), (b) die A3.9-Pflicht **PORT** in `bootstrap.sh:80,95-99` (im „Bootstrap-und-Betreiber-Werkzeuge"-Commit `d0792f0` noch nicht vorhanden), (c) die semantische Default-Änderung `QA_REQUIRED_FROM=M0 → M3` in Skript und `config.env.example`. Ergänzend: nach Commit 1 (`1ffbd0d`) ist `orchestrator/verifier.sh` noch nicht vorhanden, `orchestrate.sh` aber ruft es bereits auf — der Baum ist zwischen Commit 1 und 2 nicht lauffähig.

---

**B-15 · Der Sandbox-/Permission-Wächter ist per leerer Variable abschaltbar und in keinem Test aktiv**

*Anforderung:* A9 §5 „Sandbox-/Permission-Modus je Rolle".
*Datei/Zeile:* `orchestrator/orchestrate.sh:162-163` — `[ -z "$safe_pattern" ] || grep -Eq …`: leeres Muster überspringt die Prüfung ersatzlos. `tests/template/fixtures/config-t2.env:10,16` und `config-t3.env:9,15` setzen genau diese Variablen leer, ebenso `*_REQUIRED_FLAGS`. Die Vorlage `config.env.example:9-10,15-16` ist sicher besetzt, die Erzwingung fehlt.
*Korrektur:* Leeres `*_SAFE_MODE_PATTERN`/`*_REQUIRED_FLAGS` als `fatal` behandeln (oder mindestens als laut protokollierte, in `summary.json` sichtbare Abweichung) und einen Negativtest ergänzen.

---

### NIEDRIG

| ID | Befund | Fundstelle | Empfehlung |
|---|---|---|---|
| **B-16** | Gate `territory` ist tautologisch: es prüft nur die Existenz von `state/<MS>/territory-ok`, die der Orchestrator nach jeder erfolgreichen Prüfung schreibt und nie löscht — es kann im Normalbetrieb nie fehlschlagen. | `orchestrator/gates.d/82-territory.sh.example:3-8`, `orchestrate.sh:373` | Zeitstempel/Runde/Basis-SHA gegen die aktuelle Phase prüfen. |
| **B-17** | Lock-Rennfenster zwischen `mkdir` und dem Schreiben von `pid`: existiert das Verzeichnis ohne pid-Datei, übernimmt der zweite Prozess. Nachweis: `mkdir orchestrator/.lock && bash orchestrator/orchestrate.sh M0` → `WARN: verwaister Lock (PID unbekannt) — wird übernommen`. AUTONOMY_LEVEL 3 („Nachtlauf per Timer, der Lock macht ihn gefahrlos", A2) hängt daran. | `orchestrate.sh:105-122` | `mkdir` + `pid` atomar über `mkdir tmp; echo pid > tmp/pid; mv`-Muster oder `flock`. |
| **B-18** | `render_prompt`-sed nutzt `\|` als Delimiter; `\|` bzw. `&` in `criteriaRef` bricht bzw. verfälscht den Prompt (Nachweis: `sed: -e expression #3, char 25: unknown option to 's'`, Exit 2). `validate_manifest` beschränkt `criteriaRef` nicht. | `orchestrate.sh:235-240`, `:140` | Delimiter wechseln, `criteriaRef` auf `^[A-Za-z0-9._-]+$` einschränken. |
| **B-19** | Der Beispiel-Anker verletzt den eigenen Ankervertrag: kein `tolerance`, `source_url` ist ein Repo-Pfad statt einer URL, Feld heißt `harvested` statt `retrieved`. Er ist die erklärte „Messlatte" für generierende KIs (A7.5). | `projektierung/beispiel/demiurg/M0/anchor.json` vs. `reference/anchors/README.md`, `contracts/PROTOCOLS.md:108-110` | Im `beispiel/README.md` die Schemaabweichung explizit benennen (wie beim Manifest bereits geschehen). |
| **B-20** | `needs_human`-Herleitung mit unklarer Präzedenz: `[ A ] \|\| [ B ] && [ C ]` gruppiert zu `(A\|\|B)&&C`; bei leerem `ARG_MS` wird `phase=parked` nicht auf `needs_human=true` abgebildet. Aktuell durch den expliziten Aufrufparameter maskiert. | `orchestrator/status.sh:85` | Klammern setzen. |
| **B-21** | Unvollständige Generalisierung: `.dependency-cruiser.*` ist als Reviewer-Pfad fest verdrahtet (JS-spezifisch), während für andere Ökosysteme kein Hook existiert (siehe B-09). Ebenso landen die template-eigenen Dokumente `docs/BAUPLAN.md`, `docs/ABNAHME.md`, `docs/T5-INVENTAR.md` im `docs/`-Namensraum jedes geklonten Projekts, obwohl A1 `docs/` als projektleer beschreibt; A5 nennt keinen Aufräumschritt. | `orchestrate.sh:321,324`; A1:48 | Reviewer-Hook einführen; Template-Dokumente nach `docs/template/` verschieben oder in A5/README einen Löschschritt ergänzen. |
| **B-22** | Kein einziges mitgeliefertes Gate-Beispiel wird getestet — T-2/T-3 fahren zwei eigens gebaute Fixture-Gates. Insbesondere Mutgate v2 (Pre-Mutation-Tod = error, Ratchet, Äquivalenz-Abzug) ist ungetestet, obwohl die Quelle ausdrücklich Tests hatte („Alles gegen einen synthetischen Stryker-Report getestet (pass/ratchet-fail/error)", `README-APPLY.md` §4). | `tests/template/*`, `gates.d/86-mutgate.sh.example` | Synthetische Report-Fixtures für mutgate, trace und golden-adr ergänzen. |
| **B-23** | Die gesamte QA-Rolle ist ungetestet: `fake-model.sh:139-142` bricht bei `45-qa` ab, beide Fixtures setzen `QA_ENABLED=0` und `QA_REQUIRED_FROM=M99`. Damit sind QA-Phase, QA-Park (Patch-v2-Kernfeature, A2.1 Punkt 1, `T5-PATCH-10`), `qa-requested`-Wiederholung und die strikte QA-Routenprobe (Block H, A2.1 Punkt 2) unbelegt. | `tests/template/fixtures/config-t{2,3}.env:19-20/17-18` | T-6 mit aktiver Fake-QA und ein Park-Szenario mit `QA_ENABLED=0`, `QA_REQUIRED_FROM=M0`. |
| **B-24** | `gate_run_configured` bildet nur rc=1 auf `fail` ab; jeder andere Rückgabewert wird zu `error` — reale Werkzeuge (z. B. pytest rc=5, diverse Linter) liefern fachliche Fehlschläge mit rc>1 und werden dadurch als Infrastruktur klassifiziert (in Verbindung mit B-05 folgenlos, aber in `gates.json` falsch protokolliert). | `orchestrator/gates.d/_lib.sh:25-29` | Fail-/Error-Codes je Gate konfigurierbar machen. |

---

## 3. A9-Abdeckungsmatrix

| A9-Block | Urteil | Beleg |
|---|---|---|
| Konstruktionsprinzipien (Gewaltenteilung, deterministische Gates, dateibasiertes Protokoll) | **PASS** | `AGENTS.md:3-7`, `contracts/PROTOCOLS.md:1`; ausgeführte Positivkontrolle: Manipulation von `gates.json` durch den Builder → `FATAL … verletzt Territorium wiederholt`, Exit 2 |
| Rollen (§1), Territorienkarte, Erzwingung per git-diff | **FAIL** | B-02 (ignorierte Pfade, inkl. `orchestrator/logs/**`, Exit 0), B-09 (Presets nicht abbildbar, Exit 2) |
| Phasen (§2): PREFLIGHT · ACCEPTANCE · PLAN · PLAN-REVIEW · BUILD · GATES · QA · CODE-REVIEW · REWORK · DONE | **FAIL** | Ablauf belegt in T-2/T-3-Läufen; aber B-03 (leerer Prompt → DONE, Exit 0), B-04 (Stufe 0 Livelock), B-23 (`45-qa` nie ausgeführt) |
| Verhandlung (§3): Einwand-IDs, Präzedenz, BACKLOG, ESCALATION | **PASS** | `verdict()` `orchestrate.sh:461-468` erzwingt `ref`-Pflicht und PASS⇒leeres `blocking`; T-3: `verdict-arbiter.json` HUMAN → `ESCALATION-M0.md` + `ESCALATION.md`, Exit 3 |
| Gates mit Zweck (§4), Modelle schreiben `gates.json` nie | **FAIL** | Steckplatzvertrag geprüft (exit 0/1/2/3 → pass/fail/error/error, leere Gate-Menge → error, Exit 2); aber B-05 (`error`≡`fail`), B-16 (territory tautologisch), B-22 (kein Beispielgate getestet) |
| Anti-Halluzination (§7a), acht Mechanismen | **UNGEKLÄRT** | Regeln vollständig dokumentiert (`IMPLEMENTATION-RULES.md`, `gates.d/70-trace.sh.example`, `87-golden-adr.sh.example`, Provenienz in `verifier.sh:111-124`); keiner dieser Mechanismen wurde je ausgeführt (B-22), und die Provenienzspur ist manipulierbar (B-02) |
| Sicherheitsschienen (§5): lineare Historie, Tags, kein force-push, sauberer Baum, verbotene Flags, Sandbox, Timeouts, STOP, Logs, PREFLIGHT-Flagprüfung | **FAIL** | Positiv belegt: Resume-/Bypass-Verbot (`:180-185`), `PHASE_TIMEOUT`, `MAX_MS_PER_RUN`, STOP, sauberer Baum, `tag_once` verschiebt keine Tags. Verletzt: B-01 (Historie/Tags fallen still aus), B-02 + B-12 (Logs), B-15 (Sandbox abschaltbar), B-03 (PREFLIGHT ohne Vertragspfade) |
| Kontexthygiene (§5b): frische Session, Resume-Verbot, Kontextmanifest, Diff-Reviews, idempotente Wiederaufnahme | **FAIL** | Resume-Verbot und Marker-Idempotenz belegt (Park → `rm state/M0/parked` → Wiederaufnahme ab r4 → DONE, Exit 0); aber B-03 (Kontextmanifest kann leer sein) |
| Betrieb (§6): STATUS-Board nach jeder Phase, `state/<MS>`, `summary.json` | **FAIL** | Format-Vertrag v1 erfüllt (T-1: `contract==1`, alle Pflichtfelder); Inhalt aber falsch bei B-01 (`done`/0 ohne Commit), B-06 (`preflight`/null bei Deadlock), B-07 (`done`/0 bei blockiertem Ziel) |
| Autonomie (Patch v2): Transport-Retry, Territoriums-Retry, Lock, Notify, Leiter, QA-Park, Findings-Klassen, Mutgate v2, LESSONS-Lesepfad, CONFIG-Zeile | **FAIL** | Belegt: Transport-Retry (rc=75/503, „keine Runde verbraucht"), Territoriums-Retry (genau einer, dann FATAL), Lock, Notify DONE/PARKED/STALE, Rebuild@r4, Arbiter HUMAN, Park + Exit 3, CONFIG-Zeile, LESSONS-Zeile in 20/30/40/50/60/62. Verletzt: B-05, B-07 (Regression gegen `full/orchestrate.sh:347`), B-23 (QA-Park), B-22 (Mutgate v2), B-17 (Lock-Rennen) |
| Toolchain (A3.9): deklarierte Laufzeiten, eingefrorene Manifeste, Update-Pfad, Umgebungen außerhalb des Baums, PREFLIGHT-Versionsprüfung | **PASS** | T-1 ausgeführt: `mcp-runtime: version=1.28.1 env=external`, `mcp==1.28.1` gepinnt, `find . -name .venv` leer, `MCP_ENV_DIR` außerhalb des Repos erzwungen (`bootstrap.sh:159`), `PORT`/`REPO_PATH` gesetzt und validiert, `bootstrap.sh` zweimal idempotent. Einschränkung: `toolchain.json.example` ist leer, die Versionsprüfung lief also gegen null Laufzeiten |
| Lernen und Spur: LESSONS mit Deckel, BACKLOG, ADRs, PROGRESS | **PASS** | MCP-Selbsttest 20/20 („lessons abgelehnt: leerer Inhalt/über Deckel"), Lesepfad in allen sechs Entscheidungsprompts, `BACKLOG.md`, `docs/decisions/ADR-000-vorlage.md`, PROGRESS-Prüfung vor DONE (`:713`) |
| **A6/T-5 selbst** | **FAIL** | B-10 (tautologische Schwellen), B-13 (veralteter Nachweisblock) |

**Entkopplung (Prüfauftrag B) — PASS.** `git grep -i demiurg` liefert außerhalb von `docs/BAUPLAN.md`, `docs/T5-INVENTAR.md` und `projektierung/beispiel/` nur einen Treffer (ein A9-Prüfstring in `test-t5-inventory.py:81`). Keine absoluten Entwicklerpfade (`git grep -E '/home/|/Users/|/mnt/c/'` leer), keine Laufzeitreferenz auf `../demiurg`, keine `.venv` im Baum. Das `beispiel/` ist ein wortgetreuer Auszug (`milestones.json`, `M0/CRITERIA.json`, `REVIEW.md`, `verdict-code.json`, `gates.json`, alle vier `M0.*.spec.ts`, `ADR-001`, `anchor.json` — jeweils byte-identisch zur Quelle) und ausdrücklich als historisch gekennzeichnet. Der MCP-Server ist sauber generalisiert (`REPO_PATH`/`PORT`/`MCP_PATH`/`PROJECT_SLUG`/`MCP_AUDIT_LOG` aus der Umgebung, Tool-Fläche identisch). Einzige Restkopplung: B-21.

---

## 4. Ausgeführte Prüfkommandos

| # | Kommando (gekürzt) | Exit / Ergebnis |
|---|---|---|
| 1 | `git log --oneline --all --stat`, `git log --format='%H %ci %s'` | 0 — 5 Commits |
| 2 | `find . -path ./.git -prune -o -type f -print \| sort` | 0 — 105 Dateien |
| 3 | `git status --porcelain --untracked-files=all` (vor und nach der Prüfung) | 0 — leer, `HEAD=865840e` unverändert |
| 4 | **`HARNESS_MCP_PYTHON=~/dev/mcp-demiurg/.venv/bin/python bash tests/template/run-all.sh`** | **0** — T-1…T-5 PASS, „A6 PASS" |
| 5 | Zyklus-Manifest, `bash orchestrator/orchestrate.sh` | **1** (B-06) |
| 6 | `bash orchestrator/orchestrate.sh M1` bei offener dep | **0**, `phase:"done"` (B-07) |
| 7 | Builder schreibt `reports/ dist/ artifacts/ coverage/ orchestrator/logs/`, `orchestrate.sh` | **0**, 0 Verletzungen (B-02) |
| 8 | Builder überschreibt archivierte Prompts/Logs, `orchestrate.sh` | **0**, Fälschung überlebt (B-02) |
| 9 | Meilenstein-ID `SETUP`, `QA_REQUIRED_FROM=M3`, `orchestrate.sh` | **0** + `[: SETUP: integer expected` (B-11) |
| 10 | `ROUND=1 bash orchestrator/verifier.sh M0` mit Gate exit 3 | **2**, `status=error`, Vermerk im Gate-Log |
| 11 | `ROUND=1 bash orchestrator/verifier.sh M0` ohne aktive Gates | **2**, `result=error` |
| 12 | Gate exit 2 dauerhaft + Verdict PASS, `orchestrate.sh` | **3** nach 3 Rework-Runden + Rebuild (B-05) |
| 13 | `mkdir orchestrator/.lock; orchestrate.sh M0` | Lock übernommen (B-17) |
| 14 | Positivkontrolle: Builder manipuliert `state/M0/gates.json` | **2** — FATAL nach genau einem Retry |
| 15 | `TUNNEL_TOKEN`/`ANTHROPIC_API_KEY` in `config.env`, Modell gibt Umgebung aus | **0** — Leak belegt (B-08) |
| 16 | `AUTONOMY_LEVEL=0`, 7 aufeinanderfolgende Läufe | 7× **0**, stets `20-plan` (B-04) |
| 17 | Park → `rm state/M0/parked` → Wiederaufnahme | **3**, danach **0**, `parked:[]` |
| 18 | `criteriaRef` mit `\|`, `orchestrate.sh` | **2** + `sed: … unknown option to 's'` (B-18) |
| 19 | `python orchestrator/mcp/tests/test_allowlist.py` | **0** — 61/61 OK |
| 20 | `rm orchestrator/prompts/10-acceptance.md; orchestrate.sh M0` | **0** — 111-Byte-Prompt, DONE (B-03) |
| 21 | MCP-Server lokal starten, `curl http://127.0.0.1:39411/mcp`, `ss -ltn` | HTTP **406**, Bind ausschließlich `127.0.0.1` |
| 22 | `server.py --selftest` mit `MCP_PATH` ∈ {`/mcp`,`/mcp-<hex>`,`/hack`,`/mcp-<script>`,`/mcp-XYZ`} und `PORT` ∈ {0,70000,abc,8765} | 20/20 OK bzw. korrekte Ablehnung |
| 23 | Ohne git-Identität: `bash bootstrap.sh --non-interactive --no-start` | **0** |
| 24 | Ohne git-Identität: `bash orchestrator/orchestrate.sh M0` | **0**, DONE, **0 Commits, 0 Tags** (B-01) |
| 25 | Text-Preset: Reviewer schreibt `stilbibel.md` | **2** — FATAL (B-09) |
| 26 | `diff` `beispiel/**` ↔ `sources/demiurg/**` (8 Dateien) | alle identisch |
| 27 | `git grep -i demiurg` / `-E '/home/\|/Users/'` / `'\.\./demiurg'` | nur erwartete Treffer |
| 28 | `bash -c 'set -e; f(){ false; echo …; }; if f; then …'` | **0** — `-e`-Suppression belegt |

Mkcase-Hilfsskript: `/tmp/claude-1000/…/scratchpad/mkcase.sh` (materialisiert `git ls-files` des Templates in ein `/tmp`-Verzeichnis, legt Fixture-Config/Manifest/Gates ab und initialisiert ein eigenes Git-Repo — exakt wie `tests/template/lib.sh`).

---

## 5. Restunsicherheiten

1. **Tunnelpfad ungeprüft.** `HARNESS_T1_WITH_TUNNEL=1` hätte einen öffentlichen Cloudflare-Tunnel auf ein Repo geöffnet — eine nach außen wirkende Handlung, für die ich keine Freigabe habe. `bootstrap.sh:200-227`, `orchestrator/mcp/start.sh` (Quick **und** Named), `connector.url`-Erzeugung und der tmux-Start sind damit von mir **nicht** verifiziert; der entsprechende Block in `docs/ABNAHME.md:24-31` bleibt unbestätigt. Lokal habe ich stattdessen Serverstart, Bind-Adresse, `MCP_PATH`- und `PORT`-Validierung geprüft.
2. **Keine echten Rollen-CLIs.** `codex`/`claude` sind hier nicht installiert. `validate_role_cli` gegen echte `--help`-Ausgaben, die strikte QA-Routenprobe und die realen Sandbox-Flags sind ungeprüft.
3. **Gate-Beispiele nie gegen echte Werkzeugketten gefahren** (mutgate/Stryker, trace mit echten CRITERIA, laengenkorridor, kontinuitaet-Judge). Deren fachliche Korrektheit habe ich nur gelesen, nicht ausgeführt.
4. **`bootstrap.sh`-Installationspfade** (`apt-get`, cloudflared-Download, venv-Neuanlage ohne `MCP_PYTHON`) sind nur im Pfad „externes Python vorhanden" gelaufen.
5. **Nebenläufigkeit** habe ich nur am Lock-Fenster gezeigt, nicht als echtes Wettrennen zweier gleichzeitig startender Orchestratoren.

## 6. Offene Spezifikationsfragen

1. **Was soll bei Gate-Status `error` passieren?** A3.2/PROTOCOLS §4 sagen „kein Builder-Fehlschlag", definieren aber das Schleifenverhalten nicht. Soll `error` (a) die Runde nicht erhöhen und nach n Wiederholungen mit eigener Begründung parken, oder (b) wie heute den vollen Rework-/Rebuild-Pfad auslösen? (→ B-05)
2. **Soll `AUTONOMY_LEVEL=0` je Aufruf genau eine Phase weiterkommen** oder genügt „hält an"? A2 sagt nur „phasenweise mit Halt". (→ B-04)
3. **Welcher Exit-Code gilt für „kein ausführbarer Meilenstein"?** A3.5 kennt nur 0/2/3. Ist das FATAL (2) — und ist ein deps-Zyklus ein Manifestfehler, den `validate_manifest` ablehnen soll? (→ B-06)
4. **Soll `orchestrate.sh <MS>` bei offenen deps FATAL sein** (so Patch v2) oder ein stiller No-Op mit Exit 0? (→ B-07)
5. **Gehören die Modelltranskripte unter `orchestrator/logs/` in die Versionierung?** A9 §5 verlangt „vollständige Logs"; heute sind sie ignoriert und damit weder committet noch von der Territoriumsprüfung geschützt. (→ B-02)
6. **Wie soll T-5 seine Vollständigkeit belegen,** wenn die Quellen (docs/12, docs/14, Patch v2) im Template bewusst nicht vorliegen? Ohne eine mitgelieferte, aus den Quellen abgeleitete Sollliste bleibt der Test eine Selbstauskunft. (→ B-10)
7. **Sollen `docs/BAUPLAN.md`, `docs/ABNAHME.md`, `docs/T5-INVENTAR.md` im geklonten Projekt verbleiben?** A1 beschreibt `docs/` als projektleer; A5 nennt keinen Aufräumschritt. (→ B-21)
8. **Ist es beabsichtigt, dass `config.env` die Rollen-Geheimnisse und den Tunnel-Token trägt** und vollständig in jede Modellumgebung exportiert wird? (→ B-08)
