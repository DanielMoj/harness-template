# harness-template — Werkbank für autonome Projekte

Stand **v1.0**. Bauplan, zwei anfängliche adversarielle Prüfberichte,
Rework und Nachprüfungen liegen unter `docs/template/`.

Dieses Template orchestriert drei getrennte Rollen: Ein **Builder** baut,
ein **Reviewer** prüft und entscheidet, und eine optionale **QA-/Red-Team-
Rolle** sucht reproduzierbare Gegenbeispiele. Unterschiedliche
Modellfamilien können über die Rollenkommandos gewählt werden, werden vom
Harness aber nicht erzwungen; die effektiven Modellaufrufe kommen aus
`orchestrator/config.env`.

Ein Meilenstein wird nur abgeschlossen, wenn die aktiven Gate-Skripte
`pass` melden und der Reviewer ein `PASS` ohne blocking-Befunde
liefert. Dateien bilden das gemeinsame Gedächtnis. Resume-/Session-Flags
sind verboten, und jede Modellphase startet als neuer Prozess. Der
Betreiber projektiert und konfiguriert das Vorhaben, startet und beobachtet
die Läufe und entscheidet nur dort fachlich nach, wo das Harness eine
konkrete Human-Eskalation erzeugt.

Leitprinzip: *Prompts erinnern, Gates erzwingen.* Specs, Budgets und der
Not-Aus bleiben Betreiberentscheidungen.

Alle Pfade in diesem Dokument sind relativ zur Repository-Wurzel. Als
**Laufzeitpfad** oder **Projektierungs-Ausgabe** gekennzeichnete Ziele
werden erst durch `bootstrap.sh`, die Projektierung oder einen Lauf erzeugt;
die jeweils genannte Vorlage beziehungsweise der erzeugende Code ist im
Template vorhanden.

---

## Inhalt

1. [Rollen und Territorien](#1-rollen-und-territorien)
2. [Der Meilenstein-Zyklus](#2-der-meilenstein-zyklus)
3. [Welche Datei macht was](#3-welche-datei-macht-was)
4. [Neues Projekt — der vollständige Weg](#4-neues-projekt--der-vollständige-weg)
5. [Vorhandenes Material einbringen](#5-vorhandenes-material-einbringen)
6. [Konfiguration](#6-konfiguration)
7. [Gates](#7-gates)
8. [Sicherheit und ihre Grenzen](#8-sicherheit-und-ihre-grenzen)
9. [Beobachtung und Betrieb](#9-beobachtung-und-betrieb)
10. [Selbsttest des Templates](#10-selbsttest-des-templates)
11. [Herkunft und Abnahme-Archiv](#11-herkunft-und-abnahme-archiv)
12. [FAQ](#12-faq)
13. [Designphilosophie](#13-designphilosophie)

---

## 1. Rollen und Territorien

Die Produktpfade in der Tabelle entstehen erst im projektierten Zielrepo.
Die tatsächlich erzwungene Zuordnung steht in
`orchestrator/orchestrate.sh`; die Rollenregeln stehen in `AGENTS.md`.

| Rolle | Darf schreiben | Darf nicht schreiben | Urteil |
|---|---|---|---|
| **Builder** | je nach Phase `orchestrator/handoff/<MS>/`; in Build/Rework/Rebuild außerdem `src/**`, `tools/**`, `tests/unit/**`, `tests/properties/**`, `public/assets/**`, `contracts/api/**`, `PROGRESS.md`, `docs/decisions/**`, unterstützte Paketmanifeste und konfigurierte Zusatzpfade | Abnahmetests, Specs, fremde Handoffs und `orchestrator/**` außerhalb der ausdrücklich erlaubten Handoff-Dateien | nein |
| **Reviewer** | `tests/acceptance/**`, `reference/anchors/**`, `orchestrator/handoff/<MS>/**`, `IMPLEMENTATION-RULES.md`, `contracts/PROTOCOLS.md`, `BACKLOG.md`, `docs/decisions/**` sowie konfigurierte Zusatzpfade; die genaue Menge hängt von der Phase ab | Builder-Nutzlast | `PASS`, `REWORK` oder `ESCALATE` |
| **QA / Red Team** | `tests/e2e/**`, `tests/fuzz/**`, `orchestrator/handoff/<MS>/QA.md`, `BACKLOG.md` sowie konfigurierte Zusatzpfade | alle anderen Pfade | kein Verdict; jeder Befund braucht einen reproduzierbaren Test |
| **Orchestrator** | `orchestrator/state/**`, `orchestrator/logs/**`, maschinelle Handoffs/Eskalationen, `STATUS.md`, Phasencommits und Tags | — | Gate-Ergebnisse, Territorien und Ablaufzustand |
| **Betreiber** | Intake und Freigaben, `orchestrator/config.env`, `orchestrator/secrets.env`, `toolchain.json`, Gate-Auswahl und `orchestrator/**` | — | Projektverfassung und Human-Eskalationen |

Nach jedem Modellversuch prüft der Orchestrator getrackte und ungetrackte
Änderungen, auch an ignorierten Pfaden. Frühere Dateien unter
`orchestrator/logs/**` werden zusätzlich per Hash-Manifest geschützt. Bei
einer Territoriumsverletzung wird der Versuch zurückgerollt und genau einmal
mit Hinweis wiederholt; die zweite Verletzung endet mit FATAL/Exit 2.

Die regulären Build-/Laufzeitartefakte in
`orchestrator/artifact-paths.allowlist`, etwa `dist/`, `reports/` und
`node_modules/`, sind von der Territoriumsprüfung ausgenommen. Diese
Ausnahme ist bewusst weit: Sie ist keine inhaltliche Prüfung der Artefakte.

Für fachlichen Dissens gilt **Spec > Reviewer > Builder**. Deckt kein
Spec-Zitat die Builder-Position, bindet nach Ende der Verhandlung das
Reviewer-Urteil und wird als ADR dokumentiert; widersprüchliche Specs führen
zur Eskalation.

## 2. Der Meilenstein-Zyklus

Die implementierte Reihenfolge in `orchestrator/orchestrate.sh` lautet:

```text
PREFLIGHT
  → ACCEPTANCE
  → PLAN ↔ PLAN-REVIEW
  → BUILD
  → GATES
  → optional QA
  → bei ausgeführter QA: GATES erneut
  → CODE-REVIEW
      ├─ Gates pass + Reviewer PASS → DONE
      └─ sonst REWORK → nächste Runde ab GATES
```

- **PREFLIGHT** prüft Git-Identität, Manifest und Dependency-Zyklen,
  Vertragspfade, Toolchain-Versionen, reale CLI-Hilfen und konfigurierte
  Sicherheitsflags. Getrackte oder nicht ignorierte Git-Änderungen außerhalb
  der ausdrücklich tolerierten Status-, STOP-, Summary- und Lockpfade machen
  den Arbeitsbaum FATAL; regulär ignorierte Artefakte erscheinen in dieser
  PREFLIGHT-Prüfung nicht.
- **ACCEPTANCE** lässt den Reviewer vor der Implementierung
  `orchestrator/handoff/<MS>/CRITERIA.json` und ausführbare Tests unter
  `tests/acceptance/**` schreiben. Rot ist in dieser Phase erwartet; der
  Orchestrator führt hier selbst noch kein Testkommando aus.
- **PLAN/PLAN-REVIEW** verhandeln über stabile Einwand-IDs. Der Default sind
  höchstens zwei Planrunden (`MAX_ROUNDS_PLAN=2`); die Konfiguration kann den
  Wert ändern.
- **GATES** führt alle ausführbaren Dateien mit dem Muster
  `orchestrator/gates.d/NN-*.sh` aus und schreibt den Laufzeitpfad
  `orchestrator/state/<MS>/gates.json`. Ohne aktives Gate lautet das Ergebnis
  `error`.
- **QA** läuft nach dem ersten nicht rein infrastrukturell fehlgeschlagenen
  Gate-Lauf, wenn `QA_ENABLED=1`. Danach werden die Gates erneut ausgeführt.
  Standardmäßig läuft QA einmal pro Meilenstein; eine Datei
  `orchestrator/state/<MS>/qa-requested` fordert einen weiteren QA-Lauf an.
- **Leiter**: Wenn `LADDER_ENABLED=1`, setzt der Orchestrator ab
  `REBUILD_ROUND` einmal die in `REBUILD_PATHS` genannten Builder-Pfade auf
  `plan/<MS>` zurück und ruft Prompt 62 auf. Bei `ESCALATE` oder verbrauchtem
  Rundenbudget entscheidet einmal eine frische Arbiter-Session. `RESOLVE`
  gibt `ARBITER_EXTRA_ROUNDS` Zusatzrunden; `HUMAN` parkt den Meilenstein.
- **PARK & CONTINUE** schreibt
  `orchestrator/ESCALATION-<MS>.md`, `orchestrator/ESCALATION.md` und den
  Laufzeitmarker `orchestrator/state/<MS>/parked`. Danach werden weitere
  Meilensteine mit erfüllten Abhängigkeiten geprüft.
- **DONE** verlangt zusätzlich, dass `PROGRESS.md` seit `plan/<MS>` geändert
  wurde, und erzeugt den unveränderlich behandelten Tag `done/<MS>`.

Exit-Codes von `orchestrator/orchestrate.sh`:

- **0**: Lauf regulär beendet oder die konfigurierte Autonomiegrenze wurde
  planmäßig erreicht.
- **2**: FATAL, zum Beispiel PREFLIGHT-, Transport-, Rollen-, Commit- oder
  Vertragsfehler.
- **3**: Lauf beendet und mindestens ein Meilenstein ist geparkt; dazu zählt
  auch ein dauerhaft reiner Gate-Infrastrukturfehler.

## 3. Welche Datei macht was

### Repository-Wurzel

| Datei | Zweck |
|---|---|
| `AGENTS.md` | Verfassung: Rollen, Territorien, acht Integritätsregeln, Handoff-Disziplin und auszufüllender Projektblock |
| `CLAUDE.md` | Kompatibilitätszeiger auf `AGENTS.md` |
| `IMPLEMENTATION-RULES.md` | verbindliche Bauregeln im Reviewer-Territorium |
| `contracts/PROTOCOLS.md` | Phasen-, Verdict-, Gate-, Status-, Provenienz-, Anker- und Toolchain-Vertrag |
| `contracts/api/README.md` | Vertrag für projektbezogene Public-API-Snapshots |
| `BACKLOG.md` | nonblocking Befunde und vertagte Punkte; spätere Pläne müssen sie adressieren oder begründet vertagen |
| `PROGRESS.md` | Langzeitgedächtnis des Builders; eine Änderung seit `plan/<MS>` ist DONE-Bedingung |
| `RUNBOOK.md` | Handgriffe für PARKED, HUMAN, FATAL, STOP, Locks, Tunnel und Watchdog |
| `bootstrap.sh` | prüft Core-Werkzeuge und Git-Identität, erzeugt lokale Konfiguration/Secrets, installiert oder prüft Toolchain und MCP-Umgebung, prüft den Statusvertrag und startet standardmäßig MCP plus Tunnel in tmux |
| `start.sh` | prüft minimale Voraussetzungen und ersetzt sich im **Vordergrund** durch `orchestrator/orchestrate.sh`; es erzeugt keine tmux-Session und führt keine eigene Transportprobe aus |
| `config.env.example` | versionierte Vorlage; `bootstrap.sh` kopiert sie in den ungetrackten Laufzeitpfad `orchestrator/config.env` und setzt Modus 600 |
| `toolchain.json.example` | leere Vertrag-v1-Vorlage; `bootstrap.sh` kopiert sie bei Bedarf in den ungetrackten Laufzeitpfad `toolchain.json` |
| `docs/00-vision.md.template` | Vorlage, die im Zielprojekt durch die freigegebene Vision ersetzt wird |
| `docs/decisions/ADR-000-vorlage.md` | ADR-Vorlage |
| `docs/template/` | Bau-, Rework- und Abnahme-Archiv des Templates; **Zielprojekte dürfen diesen gesamten Ordner löschen** |
| `reference/` | vorhandene Wurzel für Projektquellen |
| `reference/anchors/README.md` | Schema für projektbezogene Ankerdateien unter `reference/anchors/*.json`; das unveränderte Template enthält noch keinen normativen JSON-Anker |

`bootstrap.sh` akzeptiert genau die Flags `--update`, `--non-interactive`,
`--no-start` und `--edit`. `--update` verwendet vorhandene
`updateCommand`-Einträge aus `toolchain.json` und fällt sonst auf das jeweilige
`installCommand` zurück; `--no-start` überspringt MCP und Tunnel.

### `orchestrator/`

| Datei | Zweck |
|---|---|
| `orchestrator/orchestrate.sh` | Lock, PREFLIGHT, Phasenschleife, Rollenaufrufe, Retries, Territorien, Commits, Tags, Rebuild, Arbiter und Park-&-Continue |
| `orchestrator/verifier.sh` | Gate-Runner für ausführbare `orchestrator/gates.d/NN-*.sh` |
| `orchestrator/gates.d/README.md` | kurze Aktivierungsanleitung für Gate-Beispiele |
| `orchestrator/gates.d/_lib.sh` | gemeinsame Funktionen für konfigurierte Kommando-Gates |
| `orchestrator/status.sh` | schreibt `STATUS.md` und `orchestrator/state/summary.json` nach Statusvertrag v1 |
| `orchestrator/notify.sh` | best-effort HTTP-POST für `FATAL`, `PARKED`, `ARBITER`, `NEEDS_HUMAN`, `DONE` und `STALE` |
| `orchestrator/watchdog.sh` | meldet `STALE`, wenn eine Lock-PID lebt und der Summary-Heartbeat zu alt ist |
| `orchestrator/milestones.json.example` | Manifestvorlage; `bootstrap.sh` erzeugt daraus bei Bedarf die projektbezogene Datei `orchestrator/milestones.json` |
| `orchestrator/prompts/10-acceptance.md` bis `orchestrator/prompts/70-arbiter.md` | neun Phasenprompts: 10, 20, 30, 40, 45, 50, 60, 62 und 70; jeder enthält ein Kontextmanifest |
| `orchestrator/handoff/SCHEMA.md` | Schema für Plan, Review, Verdicts, Arbiter und Mutation-Äquivalenz |
| `orchestrator/handoff/<MS>/` | Laufzeitpfad für meilensteinbezogene Rollenübergaben |
| `orchestrator/state/<MS>/` | Laufzeitpfad für Gates, Phasenmarker, Runde und Parkzustand |
| `orchestrator/logs/` | lokale Laufzeitlogs und Promptarchive |
| `orchestrator/artifact-paths.allowlist` | Regex-Liste territoriumsfreier Build-/Laufzeitartefakte |
| `orchestrator/mcp/server.py` | MCP-Connector mit den Tools `lies`, `liste`, `befehl` und `lessons_schreiben`; die drei ersten sind lesend, das letzte ist der einzige Schreibpfad |
| `orchestrator/mcp/tests/test_allowlist.py` | ausführbare Allowlist-Abnahme mit aktuell 72 Fällen |
| `orchestrator/LESSONS.md` | kuratiertes Destillat; `lessons_schreiben` ersetzt die Datei vollständig und akzeptiert höchstens 16.000 Zeichen |

Modelltranskripte heißen
`<MS>-<phase>-r<runde>-a<versuch>-<zeitstempel>.log`. Das einmal pro
Phasenaufruf gerenderte Promptarchiv heißt
`<MS>-<phase>-r<runde>-<zeitstempel>-prompt.md`; QA-Routenproben verwenden
ein eigenes `qa-probe-<zeitstempel>-<versuch>.md`-Muster. Die Prompts 20,
30, 40, 50, 60 und 62 lesen `orchestrator/LESSONS.md`, wenn die Datei
vorhanden ist.

### `projektierung/`

| Datei | Zweck |
|---|---|
| `projektierung/PROJEKTIERUNG.md` | eigenständiges Playbook für zehn logische Projektierungs-Ausgaben; bei Intake-Lücken verlangt es Rückfragen statt Annahmen |
| `projektierung/INTAKE-CHECKLISTE.md` | acht Pflichtfelder des Betreiber-Inputs |
| `projektierung/SPEC-KONTRAKT.md` | Format für Specs, Kriterien, Traceability, Meilensteine, Anker und ADRs |
| `projektierung/presets/software-ts/PRESET.md` | TypeScript-Layout, Gate-Grundsätze und Zusatzterritorien |
| `projektierung/presets/text/PRESET.md` | Manuskript-Layout, Text-Gates und Zusatzterritorien |
| `projektierung/presets/daten/PRESET.md` | Datenpipeline-Layout, Daten-Gates und Zusatzterritorien |
| `projektierung/beispiel/README.md` | Einordnung des gekürzten Demiurg-Beispiels unter `projektierung/beispiel/demiurg/` |

### `tests/template/`

`tests/template/run-all.sh` fährt die Selbsttests des Templates. Diese Tests
gehören zur Template-Abnahme, nicht zu den späteren Produkttests eines
Zielprojekts.

## 4. Neues Projekt — der vollständige Weg

**Schritt 0 · Besprechen.** Das Destillat wird gegen
`projektierung/INTAKE-CHECKLISTE.md` geführt. Die acht Felder sind: Vision,
Zielgruppe/Nutzungskontext, Out-of-Scope, Stack/Format samt Laufzeiten,
messbarer Qualitätsmaßstab je Kernfeature, Quellen/Originale, Risiken und
offene Fragen sowie Rollen/Budget.

**Schritt 1 · Projektieren.** Gib das Destillat zusammen mit
`projektierung/PROJEKTIERUNG.md`,
`projektierung/INTAKE-CHECKLISTE.md`,
`projektierung/SPEC-KONTRAKT.md` und genau einem passenden
`projektierung/presets/*/PRESET.md` in eine Projektierungs-Session. Bei
Lücken soll die Session stoppen und gesammelt nachfragen. Entschiedenes
wandert in die Spec, offen Erwogenes in den Katalog, Verworfenes in
Out-of-Scope.

**Schritt 2 · Redigieren.** Lies zuerst die erzeugte
Projektierungs-Ausgabe `OFFENE-PUNKTE.md`, dann Specs und Kriterien. Erst die
Betreiberfreigabe verleiht Spec-Rang.

**Schritt 3 · Klonen und Ausgaben einsetzen.** Der konfigurierte Remote
dieses Repos lautet derzeit:

```bash
git clone https://github.com/DanielMoj/harness-template.git mein-projekt
cd mein-projekt
```

Die folgende Tabelle nennt **Projektierungs-Ausgaben**; diese Dateien sind
nicht als fertige Projektspezifikation im neutralen Template eingecheckt.

| Projektierungs-Ausgabe | Ziel im Klon |
|---|---|
| `docs/00-vision.md` | ersetzt `docs/00-vision.md.template` |
| `docs/01-fachspezifikation.md` und gegebenenfalls weitere nummerierte Specs | unter `docs/` |
| `docs/90-katalog-offen.md` | unter `docs/` |
| `orchestrator/milestones.json` | ersetzt die von `orchestrator/milestones.json.example` abgeleitete Laufzeitdatei |
| `AGENTS-PROJEKTBLOCK.md` | Inhalt in den Projektblock von `AGENTS.md` übernehmen |
| `gates-auswahl.md` | Betreiber-Arbeitsdatei für die Gate-Aktivierung; der Orchestrator liest sie nicht automatisch |
| `ANKER-TODO.md` | Arbeitsliste für die spätere Reviewer-Erhebung unter `reference/anchors/`; der Orchestrator liest sie nicht automatisch |
| `BACKLOG-START.md` | Inhalt nach `BACKLOG.md` übernehmen |
| `toolchain-entwurf.json` | als `toolchain.json` übernehmen |
| `OFFENE-PUNKTE.md` | Betreiber-Arbeitsdatei; vor Freigabe abarbeiten |

**Schritt 4 · Bootstrap.** `bash bootstrap.sh` erzeugt bei Bedarf
`orchestrator/config.env`, `orchestrator/secrets.env`, `toolchain.json` und
`orchestrator/milestones.json`. Es installiert beziehungsweise prüft die
deklarierte Toolchain und das externe MCP-venv, führt MCP-Selbsttest und
Statusprüfung aus und startet standardmäßig MCP plus Cloudflare-Tunnel in
einer tmux-Session. Danach druckt es die Connector-URL. Für einen Lauf ohne
Server/Tunnel dient `bash bootstrap.sh --no-start`.

**Schritt 5 · Konfigurieren.** Fülle `orchestrator/config.env`. Die
effektiven Rollenaufrufe stehen in `BUILDER_CMD`, `REVIEWER_CMD` und
gegebenenfalls `QA_CMD`.

Aktiviere nur benötigte Gates. Kopieren allein genügt nicht, weil die
eingecheckten Beispiele Modus 644 haben; die Kopie muss ausführbar werden:

```bash
cp orchestrator/gates.d/30-tests.sh.example orchestrator/gates.d/30-tests.sh
chmod +x orchestrator/gates.d/30-tests.sh
```

**Schritt 6 · Vorwissen platzieren.** Siehe Abschnitt 5.

**Schritt 7 · Projektstand committen.** Vor dem Orchestratorstart müssen
Specs, `AGENTS.md`, `orchestrator/milestones.json`, aktivierte Gate-Skripte
und alle anderen nicht ignorierten Projektierungs-Ausgaben in einem
Betreiber-Commit stehen oder bewusst außerhalb des Checkouts liegen.
PREFLIGHT lehnt einen nicht sauberen Arbeitsbaum ab; die lokale
`orchestrator/config.env`, `orchestrator/secrets.env` und `toolchain.json`
sind davon wegen der Ignore-Regeln ausgenommen.

**Schritt 8 · M0 starten.** `bash start.sh M0` und
`bash orchestrator/orchestrate.sh M0` laufen beide im Vordergrund. Für eine
eigene tmux-Session muss der Betreiber den Befehl selbst in tmux starten.
M0 wird von `projektierung/PROJEKTIERUNG.md` und
`projektierung/SPEC-KONTRAKT.md` als Gerüst-/Toolchain-/Leere-Gates-
Meilenstein vorgegeben; der Orchestrator besitzt dafür keinen Sonderfall.
Ohne Ziel-ID verarbeitet `bash start.sh` die Queue nur bis zur Grenze von
`MAX_MS_PER_RUN`.

**Schritt 9 · Beobachten.** Konfiguriere `NOTIFY_URL`; richte den Watchdog
separat nach `RUNBOOK.md` als Cronjob ein. Benachrichtigungen sind
best-effort und hängen außerdem von `NOTIFY_ENABLED` ab.

**Schritt 10 · Eingreifen mit Beleg.** Bei PARKED zuerst
`orchestrator/ESCALATION-<MS>.md`, Handoff und Gate-Logs lesen. Nach Behebung
der Ursache den Laufzeitmarker `orchestrator/state/<MS>/parked` gezielt
entfernen und neu starten. `touch orchestrator/STOP` führt vor der nächsten
geprüften Phase zu FATAL/Exit 2; anschließend muss die STOP-Datei für die
Wiederaufnahme entfernt werden.

## 5. Vorhandenes Material einbringen

Das Projektierungs-Playbook verlangt vollständiges Sortieren statt stilles
Kürzen. Es ist eine Prompt-Regel, kein maschineller Beweis dafür, dass eine
Projektierungs-KI tatsächlich nichts ausgelassen hat; die Betreiberredaktion
bleibt nötig.

| Vorhandenes Material | Ablage/Verarbeitung | Tatsächlicher Harness-Bezug |
|---|---|---|
| KI-Besprechungen, Notizen, Ideenlisten | ungekürzt an das Intake anhängen | `projektierung/PROJEKTIERUNG.md` verlangt die Sortierung entschieden/offen/verworfen |
| Konzepte und Spezifikationen | Original unter `reference/` behalten und dem Intake beilegen | freigegebener bindender Inhalt wird als nummerierte Spec unter `docs/` projektiert |
| eigene Agentenregeln | nicht als zweite Verfassung parallel führen | Bauregeln nach `IMPLEMENTATION-RULES.md`, Projektfakten in den Projektblock von `AGENTS.md`, Quellenwissen nach `reference/` |
| bestehender Code | unter einem in der Spec benannten Unterordner von `reference/` ablegen | Portierung kann als früher Meilenstein mit Differentialtests geplant werden; ein automatisches Überstülpen des Templates existiert nicht |
| Daten, CSVs, Medien | unter `reference/` oder einem in der Spec benannten Projektpfad | die mitgelieferten Asset-/Daten-Gates führen nur konfigurierte Befehle aus; Manifest- oder SHA256-Prüfungen müssen im jeweiligen Projektkommando tatsächlich implementiert sein |
| Zahlen, Grenzwerte, Messlatten | Quellen in Intake-Feld 6 und der Projektierungs-Ausgabe `ANKER-TODO.md` | der Reviewer soll daraus projektbezogene `reference/anchors/*.json` nach `reference/anchors/README.md` erstellen |
| Stil-, Figuren- oder Weltbibel | Pfade gemäß `projektierung/presets/text/PRESET.md` | Freigabe über `REVIEWER_EXTRA_PATHS_REGEX`; konkrete Prüfkommandos kommen aus der Projektkonfiguration |
| bestehende Tests | als Quellenmaterial oder später im passenden Projektterritorium | Abnahmetests unter `tests/acceptance/**` schreibt der Reviewer neu aus freigegebenen Kriterien |

## 6. Konfiguration

Die vollständige Variablenliste und Defaults stehen in
`config.env.example`; die wirksame, ungetrackte Datei ist
`orchestrator/config.env`.

### Rollenaufrufe und Wächter

- Die ausführbaren Kommandos heißen exakt `BUILDER_CMD`, `REVIEWER_CMD` und
  `QA_CMD`. In diesen Strings ist `$PROMPT_FILE` beziehungsweise
  `${PROMPT_FILE}` die einzige zulässige Shell-Variablenreferenz.
- `BUILDER_HELP_CMD`, `REVIEWER_HELP_CMD` und `QA_HELP_CMD` werden im
  PREFLIGHT wirklich ausgeführt. Die zu suchenden Flags stehen in
  `BUILDER_REQUIRED_FLAGS`, `REVIEWER_REQUIRED_FLAGS` und
  `QA_REQUIRED_FLAGS`; die effektiven sicheren Modi werden mit
  `BUILDER_SAFE_MODE_PATTERN`, `REVIEWER_SAFE_MODE_PATTERN` und
  `QA_SAFE_MODE_PATTERN` geprüft.
- `ROLE_GUARDS=off` ist der einzige bewusste Abschalter für leere
  Required-/Safe-Mode-Prüfungen und wird in Log und Summary sichtbar. Die
  Verbotsliste für Rollenkommandos bleibt trotzdem aktiv: Unter anderem
  `--continue`, `--resume`, `--session`,
  `--dangerously-skip-permissions` und `--yolo` führen zu FATAL.
- `BUILDER_MODEL`, `REVIEWER_MODEL`, `QA_MODEL` und `QA_ENDPOINT` in der
  Vorlage steuern den Modellaufruf **nicht**. `QA_MODEL` erscheint nur als
  Bezeichnung im erfolgreichen QA-Probe-Log; die übrigen drei werden vom
  Orchestrator nicht ausgewertet. Modell und Endpoint müssen daher in
  `BUILDER_CMD`, `REVIEWER_CMD` beziehungsweise `QA_CMD` wirksam
  konfiguriert werden.

### Autonomie

Die Stufen setzen Defaults; explizite nichtleere Werte für
`MAX_MS_PER_RUN`, `LADDER_ENABLED` und `NOTIFY_ENABLED` überschreiben sie.

| `AUTONOMY_LEVEL` | Defaults im Orchestrator |
|---:|---|
| 0 | genau ein Phasencommit pro Aufruf; `MAX_MS_PER_RUN=1`, Leiter und Notify aus |
| 1 | höchstens ein Meilenstein pro Aufruf; Leiter und Notify aus |
| 2 | höchstens vier Meilensteine pro Aufruf; Leiter und Notify an; Vorlagen-Default |
| 3 | höchstens 999 Meilensteine pro Aufruf; Leiter und Notify an |

Stufe 3 installiert keinen Timer. Zeit- oder Nachtstarts müssen extern, etwa
über cron oder systemd, eingerichtet werden. Ein explizites Ziel wie
`bash start.sh M0` beschränkt den Lauf unabhängig von der Stufe auf diesen
Meilenstein.

### QA, Budgets und Betrieb

- QA: `QA_ENABLED`, `QA_REQUIRED_FROM`, `QA_PROBE_STRICT`,
  `QA_PROBE_RETRIES`, `QA_PROBE_TIMEOUT`, `QA_PROBE_SLEEP`. Ist QA ab einer
  Manifest-ID Pflicht, aber `QA_ENABLED` nicht 1, wird der Meilenstein vor
  der Rework-Schleife geparkt.
- Verhandlung/Leiter: `MAX_ROUNDS_PLAN`, `MAX_ROUNDS_REWORK`,
  `REBUILD_ROUND`, `ARBITER_EXTRA_ROUNDS`, `LADDER_ENABLED`.
- Transport/Gates: `PHASE_TIMEOUT`, `RETRY_MAX`, `RETRY_SLEEP`,
  `GATE_ERROR_RETRIES`, `MAX_MS_PER_RUN`.
- Zusatzterritorien: `BUILDER_EXTRA_PATHS_REGEX`,
  `REVIEWER_EXTRA_PATHS_REGEX`, `QA_EXTRA_PATHS_REGEX`; der Rebuild-Umfang
  steht in `REBUILD_PATHS`.
- Rollen-Umgebung: `BUILDER_ENV_ALLOWLIST`, `REVIEWER_ENV_ALLOWLIST`,
  `QA_ENV_ALLOWLIST`. Namen mit `API_KEY`, `TOKEN`, `SECRET`, `PASSWORD`
  oder `PRIVATE_KEY` werden abgelehnt.
- Benachrichtigungen: `NOTIFY_ENABLED` schaltet den Versand,
  `NOTIFY_URL` ist die vollständige POST-Zieladresse und `NOTIFY_TOPIC` wird
  nur als Präfix des HTTP-Title-Headers verwendet.
- `GATE_ERROR_CODES` ist eine **globale** Liste für die mit
  `gate_run_configured` ausgeführten Kommando-Gates. Sie ist keine
  gate-spezifische Zuordnung.

## 7. Gates

`orchestrator/verifier.sh` aktiviert ausschließlich ausführbare Dateien, die
`orchestrator/gates.d/NN-*.sh` entsprechen. Es exportiert unter anderem
`REPO_ROOT`, `ORCH`, `MILESTONE`, `ROUND`, `BASE_SHA`,
`GATE_ARTIFACT_DIR` und `GATES_PROGRESS_JSON`.

Der Steckplatzvertrag ist:

- Exit 0 → `pass`
- Exit 1 → `fail`
- Exit 2 → `error`
- jeder andere Exit-Code → `error` mit Runner-Hinweis
- letzte nichtleere stdout-Zeile → Kurzbefund
- vollständiges stdout/stderr →
  `orchestrator/state/<MS>/gate-<name>.log`
- Aggregat → `orchestrator/state/<MS>/gates.json`

Enthält ein Lauf mindestens ein `fail`, ist sein Aggregat `fail`, auch wenn
zugleich ein Gate `error` meldet. Ohne `fail`, aber mit mindestens einem
`error`, ist es `error`.

`orchestrator/gates.d/_lib.sh` behandelt bei
`gate_run_configured` standardmäßig rc 126 und 127 als Infrastrukturfehler;
andere rc größer 0 werden `fail`. `GATE_ERROR_CODES` ersetzt diese globale
Liste.

Ein reines Gate-Aggregat `error` verbraucht keine Rework-Runde und löst
keinen Rebuild aus. Mit dem Default `GATE_ERROR_RETRIES=2` folgen auf den
ersten Lauf zwei Wiederholungen in derselben Runde; bleibt das Ergebnis
`error`, wird der Meilenstein mit Exit 3 geparkt. Ein gemischter
Fail/Error-Lauf folgt dagegen dem normalen Rework-Pfad.

### Mitgelieferte Beispiele

Die einfachen Wrapper delegieren das fachliche Urteil an das jeweils
konfigurierte Kommando: `10-deps`, `20-lint`, `30-tests`, `40-smoke`, `50-graph`,
`60-api`, `80-bench`, `81-e2e`, `83-assets`, `84-shots`, `85-research`,
`91-stil-lint`, `93-zitate`, `94-schema`, `95-repro` und `96-golden`.
`84-shots` legt vorher zusätzlich das Gate-Artefaktverzeichnis an. Ein leerer
Kommandowert ergibt `error`; die Wrapper implementieren nicht selbst die
fachliche Prüfung.

Besondere Logik besitzen:

- `orchestrator/gates.d/70-trace.sh.example`: Ohne `TRACE_CMD` prüft es
  `orchestrator/handoff/<MS>/CRITERIA.json`, wörtliche Spec-Zitate und
  Manifest-IDs. Jedes dort geführte Kriterium muss irgendwo unter
  `tests/acceptance/**` referenziert sein; jede dort gefundene ID im Muster
  `<Buchstabe>-<MS>-<Zahl>` muss in derselben Kriterien-Datei bekannt sein.
  Es prüft
  weder, ob jede einzelne Testdatei eine ID trägt, noch eine Zuordnung von
  Gates zu Kriterien.
- `orchestrator/gates.d/82-territory.sh.example`: prüft, dass der letzte
  Territoriums-Audit zur aktuellen Runde und Basis passt.
- `orchestrator/gates.d/86-mutgate.sh.example`: berechnet einen
  Mutation-Score aus einem Stryker-Report, nutzt Floor/Ratchet/Baseline und
  meldet einen fehlenden Report nach Werkzeugabbruch als `error`.
- `orchestrator/gates.d/87-golden-adr.sh.example`: verlangt bei Änderungen
  unter dem konfigurierten Golden-Regex oder `reference/anchors/` mindestens
  eine geänderte Datei mit Präfix `docs/decisions/ADR-` im Diff seit
  `BASE_SHA`.
- `orchestrator/gates.d/90-laengenkorridor.sh.example`: zählt Wörter gegen
  die Bänder der mit `TEXT_LENGTH_ANCHOR` benannten JSON-Datei.
- `orchestrator/gates.d/92-kontinuitaet.sh.example`: erwartet von
  `CONTINUITY_CMD` ein JSON-Objekt mit `verdict: "PASS"|"FAIL"`; `reason`
  ist optional. Ein nicht erfolgreicher Judge-Prozess ist `error`.

Die zusätzliche Regel „jedes Gate trägt ein Kriterium, jedes Kriterium hat
ein Gate oder einen Test“ steht in `projektierung/SPEC-KONTRAKT.md`. Der
mitgelieferte Trace-Fallback erzwingt nur den oben beschriebenen Teil davon;
die Gate-zu-Kriterium-Richtung muss die Projektkonfiguration anderweitig
belegen.

## 8. Sicherheit und ihre Grenzen

- **Projekt-Secrets:** `bootstrap.sh` erzeugt den ungetrackten Laufzeitpfad
  `orchestrator/secrets.env` mit Modus 600. Es verschiebt die bekannten
  Namen `TUNNEL_TOKEN`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`,
  `OPENROUTER_API_KEY`, `QA_API_KEY` sowie Namen aus `HARNESS_SECRET_KEYS`
  aus `orchestrator/config.env` dorthin. Beliebige anders benannte
  Geheimnisse erkennt es nicht automatisch.
- **Rollenprozess-Umgebung:** Modellprozesse starten mit `env -i`. Der
  Orchestrator übergibt ausdrücklich nur `PROMPT_FILE`, `PATH`, `HOME`,
  `LANG` sowie die jeweilige Rollen-Allowlist; die gestartete Shell ergänzt
  übliche eigene Variablen wie `PWD`, `SHLVL` und `_`. Secrets werden nicht
  automatisch in diese Prozessumgebung exportiert.
- **Dateisystemgrenze:** Modus 600 schützt nur gegen andere OS-Benutzer. Da
  die Rollen-CLI unter demselben Benutzer im Checkout läuft, verhindert das
  Harness selbst keinen Lesezugriff auf `orchestrator/secrets.env`, wenn der
  konfigurierte CLI-Sandboxmodus ihn erlaubt. Die Umgebungsisolation ist
  daher keine vollständige Secret-Isolation vom Modell.
- **MCP-Connector:** `lies`, `liste` und `befehl` blockieren `.env`- und
  `.git`-Pfade und prüfen Pfadtokens per `realpath` gegen die Repo-Grenze;
  die Tests decken auch Symlink-Fluchten ab. `lessons_schreiben` darf als
  einzige Ausnahme `orchestrator/LESSONS.md` ersetzen und versucht
  standardmäßig, nur diese Datei zu committen. Der Connector ist damit nicht
  vollständig read-only.
- **Tunnel:** Quick und Named Tunnel sind implementiert. Der Tunnel ist laut
  `orchestrator/mcp/README.md` keine Authentisierung; Connector-URL und ein
  zufälliger Named-Tunnel-Pfad müssen wie Secrets behandelt werden.
- **Territorium:** Die Prüfung umfasst ignorierte Pfade und schützt frühere
  Logs per Hash-Manifest. Pfade aus
  `orchestrator/artifact-paths.allowlist` bleiben eine ausdrückliche
  Ausnahme.
- **Provenienz:** `orchestrator/state/<MS>/gates.json` enthält Basis- und
  aktuellen SHA sowie Werkzeugversionen.
  `orchestrator/logs/orchestrate.log` protokolliert ausgewählte effektive
  Ablaufwerte, aber nicht die vollständige Konfiguration.

## 9. Beobachtung und Betrieb

- `STATUS.md` und `orchestrator/state/summary.json` zeigen denselben aus dem
  Zustand gerenderten Fortschritt; `summary.json` trägt `"contract": 1` und
  `ts` als Heartbeat.
- `orchestrator/logs/orchestrate.log` ist die Metaspur. Modelltranskripte und
  Promptarchive folgen den in Abschnitt 3 genannten unterschiedlichen
  Namensmustern.
- `orchestrator/notify.sh` sendet best-effort. Der Orchestrator ruft es für
  `FATAL`, `PARKED`, `ARBITER`, `NEEDS_HUMAN` und `DONE` auf;
  `orchestrator/watchdog.sh` nutzt es für `STALE`.
- `bootstrap.sh` installiert keinen Watchdog-Cronjob. Das Beispiel in
  `RUNBOOK.md` startet `orchestrator/watchdog.sh` alle 15 Minuten; der
  Default `WATCHDOG_STALE_SECONDS=1800` meldet erst nach mehr als 30 Minuten
  Heartbeat-Alter und nur bei lebender Lock-PID.
- Ein abgewiesener Doppelstart verändert weder Heartbeat noch
  Benachrichtigungen des laufenden Orchestrators.
- Wiederaufnahme erfolgt durch erneuten Start; vorhandene Phasenmarker werden
  berücksichtigt. STOP und PARKED müssen wie in `RUNBOOK.md` beschrieben
  gezielt aufgelöst werden.
- Bei `PUSH_REMOTE=1` und vorhandenem Remote `origin` versucht der
  Orchestrator nach jedem DONE ein `git push --follow-tags`; ein Fehlschlag
  wird nur als Warnung geloggt.

## 10. Selbsttest des Templates

`bash tests/template/run-all.sh` materialisiert temporäre Git-Repositories
unter `/tmp` und fährt die echte Orchestrator-/Gate-/Statuslogik mit
`tests/template/fake-model.sh` statt echten Modell-CLIs.

| Test | Tatsächlich geprüfter Schwerpunkt |
|---|---|
| T-1 | Bootstrap zweimal, Statusvertrag, externe MCP-Umgebung, bekannte Secret-Migration; der öffentliche Tunnel bleibt dabei deaktiviert |
| T-2 | zwei Meilensteine, rote Gates, Rework, Transport- und Territoriums-Retry, Commits und Tags |
| T-3 | Rebuild ab Runde 4, Arbiter `HUMAN`, PARKED und Exit 3 |
| T-4 | Notify, Watchdog, Doppelstart, fremdbefüllter Lock und Statuspräzedenz |
| MCP-Allowlist | aktuell 72 positive, negative, Struktur-, grep- und Symlink-Fälle |
| T-5B / T-5 | sechs ausgeführte Verhaltensnachweise und Vollinventar gegen `docs/template/T5-SOLL.md` |
| T-6 | aktive QA, QA-Park, acht Fortschritte mit Autonomiestufe 0 und ziffernlose IDs |
| T-7 | Territorien, Logschutz, Rollen-Umgebung, Flag-/Guard-Prüfung, Vertrags- und Manifestfehler |
| T-8 | Gate-error/fail, Mutation-Ratchet, Trace, Golden-ADR und Territory-Marker |

Der Suite-Lauf hängt Auditzeilen an den ignorierten Laufzeitpfad
`orchestrator/mcp/calls.log` an. Das ist erwarteter Testzustand, kein
versioniertes Artefakt.

## 11. Herkunft und Abnahme-Archiv

`docs/template/BAUPLAN.md` beschreibt die Extraktion aus dem damaligen
Demiurg-Projekt. Die beiden ursprünglichen adversariellen Berichte unter
`docs/template/abnahme/` endeten mit **FAIL**, nicht mit Abnahme. Darauf
folgten der achtteilige Rework R1–R8, eine unabhängige Wiederabnahme mit
Rot-Proben gegen den Vor-Rework-Stand, zwei neue Nachbefunde zur MCP-
Symlinkgrenze und zur Watchdog-Uhr sowie deren Nacharbeit/Nachprüfung. Die
Berichte und Betreiberentscheide E1–E9 bleiben vollständig im Archiv.

Der annotierte Git-Tag `v1.0` existiert und markiert den abgeschlossenen
Template-/Nachprüfungsstand vor dieser späteren README-Korrektur.

## 12. FAQ

**Andere Modelle einsetzen?** Ändere das jeweilige Rollenkommando in
`orchestrator/config.env`. Die Felder `BUILDER_MODEL`, `REVIEWER_MODEL` und
`QA_ENDPOINT` wählen selbst kein Modell und keinen Endpoint aus.

**Geht es ohne QA?** Ja. Bei leerem `QA_CMD` ist QA standardmäßig aus. Ist
zugleich `QA_REQUIRED_FROM` auf eine Manifest-ID gesetzt, parkt das Harness
ab dieser Position, solange `QA_ENABLED` nicht 1 ist.

**Kann ich das Template über ein bestehendes Repo legen?** Es gibt dafür
keinen automatisierten Pfad. Der dokumentierte Weg ist ein frischer Klon,
Originalmaterial unter `reference/` und eine projektspezifisch geplante
Portierung.

**Muss ich `docs/template/` behalten?** Nein. Es ist nur das interne Bau- und
Abnahme-Archiv des Templates und kann im Zielprojekt entfernt werden.

**Wo greife ich als Betreiber ein?** Bei Intake, Freigabe, Gate-Auswahl,
`orchestrator/config.env`, `orchestrator/secrets.env`, `toolchain.json`,
Betriebsereignissen nach `RUNBOOK.md` und den konkreten Fragen in
`orchestrator/ESCALATION-<MS>.md`.

## 13. Designphilosophie

Das Harness verbindet etablierte Software- und Betriebspraxis mit
Forschungslinien zu Multi-Agent-Systemen, Verifikation und
Kontextsteuerung. Die Verweise unten ordnen die Ideen fachlich ein; sie
belegen nicht, dass jede Funktion aus genau dieser Publikation abgeleitet
wurde. Die Tabelle ist keine systematische Forschungsbibliografie, und das
Repository enthält keinen Vergleichsversuch, der eine Überlegenheit gegenüber
einem einzelnen Agenten oder das „bestmögliche“ Ergebnis beweist.

Die letzte Spalte trennt deshalb vier Ebenen: **hart** bedeutet durch
Orchestrator, Schema, Territoriumsprüfung oder Test erzwungen;
**konfigurationsabhängig** gilt nur bei aktivierter Vorlage oder
Projektkonfiguration; **Vertrag/Prompt** ist eine Rollenregel, aber kein
vollständiger technischer Beweis; **Designziel** wird unterstützt, jedoch
nicht geprüft.

### Gewaltenteilung und Dekorrelation

| Feature | Praxis- oder Forschungslinie | Wofür es gut ist | Tatsächliche Umsetzung und Grenze |
|---|---|---|---|
| Builder und Abnehmer sind getrennt | Vier-Augen-Prinzip, spezialisierte Rollen wie in [MetaGPT](https://arxiv.org/abs/2308.00352) und [ChatDev](https://aclanthology.org/2024.acl-long.810/), dazu der Befund zur [Selbstbevorzugung von LLM-Judges](https://arxiv.org/abs/2404.13076) | Verhindert, dass der Autor Produktcode und Abnahmekriterien passend zueinander ändert oder die eigene Arbeit zertifiziert | **Hart für Rollen und Schreibterritorien:** Aktive Rollen laufen als getrennte Prozesse; Builder schreibt keine Abnahmetests, Reviewer keinen Produktcode. Die Konfiguration kann trotzdem dasselbe Modell oder sogar dasselbe Rollenkommando verwenden; personelle oder modellseitige Unabhängigkeit wird nicht nachgewiesen. |
| QA als dritte, adversarielle Rolle | Red Teaming und Ensemble-Idee; unterschiedliche Fehlerquellen sollen blinde Flecken reduzieren, obwohl LLM-Fehler laut [Korrelationsbefunden](https://arxiv.org/abs/2506.07962) nicht automatisch unabhängig sind | Sucht ausführbare Gegenbeispiele statt einer weiteren bestätigenden Bewertung und besitzt bewusst keine Verdict-Macht | **Konfigurationsabhängig:** QA erzeugt E2E-/Fuzz-Nachweise und kein Urteil. Sie ist standardmäßig optional. Drei Rollen sind nicht automatisch drei Modellfamilien; Familienidentität und Fehlerdekorrelation prüft das Harness nicht. `BUILDER_MODEL`, `REVIEWER_MODEL` und `QA_ENDPOINT` wählen selbst kein Modell. |
| Frischer Arbiter mit bindender Ablaufwirkung | „Fresh eyes“, Begrenzung von Verankerung und [Multi-Agent-Debatten](https://arxiv.org/abs/2305.14325) mit operationaler Abbruchregel | Beendet festgefahrene Rework-Schleifen und überführt den Fall eindeutig in Zusatzrunden oder einen Human-Park | **Hart im Ablauf:** Der Arbiter startet als neuer Prozess und sein strukturiertes Ergebnis steuert den weiteren Zustand. Er kann jedoch über dasselbe `REVIEWER_CMD` und damit dieselbe Modellfamilie laufen; kognitive Unabhängigkeit ist ein **Designziel**, kein geprüfter Fakt. |

### Deterministische Verifikation und Anti-Halluzinations-Grounding

| Feature | Praxis- oder Forschungslinie | Wofür es gut ist | Tatsächliche Umsetzung und Grenze |
|---|---|---|---|
| Modelle dürfen Gates nur lesen | Externe Verifikation statt bloßer Selbstkritik; Forschung zeigt klare Grenzen rein intrinsischer [Selbstkorrektur](https://deepmind.google/research/publications/48252/). Die Trennung begrenzt außerdem das in einem [Coding-Audit zu Reward Hacking](https://alignment.anthropic.com/2026/coding-audit-realism/) untersuchte Manipulieren von Tests. | Nur der Betreiber definiert die Wahrheitsprüfung; ein Modell kann ein rotes Gate nicht durch Umschreiben von `gates.json` oder der Gate-Auswahl grün machen | **Hart für Schreibrechte:** Modellrollen dürfen Orchestrator-Zustand und aktive Gates nicht schreiben; `orchestrator/verifier.sh` erzeugt die Fakten. Deterministisch ist die Kontrolllogik, nicht zwingend jeder konfigurierte Gate-Befehl oder externe Dienst. |
| Abnahmetests entstehen vor der Implementierung | Test-first/TDD und ausführbare Spezifikation; empirische Einordnung etwa in der [Test-first-Studie](https://doi.org/10.1109/TSE.2005.37) | Fixiert den Vertrag, bevor der Builder ihn erfüllen kann, und verhindert nachträglich maßgeschneiderte Abnahmetests | **Hart für Reihenfolge und Eigentum:** Der Reviewer schreibt die Acceptance-Verträge vor BUILD, ein roter Ausgang ist erlaubt und erwartet. Die ACCEPTANCE-Phase allein beweist jedoch nicht, dass jeder neue Test tatsächlich rot ausgeführt wurde; dieser Beleg muss aus den konfigurierten Gates kommen. |
| `error` ist nicht `fail` | SRE-Trennung zwischen Infrastrukturstörung und fachlichem Fehler | Transport- oder Umgebungsfehler verbrauchen keine fachlichen Rework-Runden | **Hart:** Ein reiner Gate-`error` wird standardmäßig nach dem ersten Versuch zweimal wiederholt und anschließend als Infrastrukturfall geparkt; ein gemischtes Ergebnis mit `fail` bleibt ein fachlicher Fehlschlag. |
| Mutation-Ratchet | Mutation Testing seit [DeMillo, Lipton und Sayward](https://doi.org/10.1109/C-M.1978.218136) plus Ratchet-Prinzip; relevant ist auch der Befund, dass Benchmark-Tests [inkorrekte SWE-bench-Patches akzeptieren können](https://software-lab.org/publications/icse2026_SWE-bench-correctness.pdf) | Prüft, ob Tests Fehler wirklich entdecken, und verhindert ein stilles Absinken des erreichten Mutation Scores | **Konfigurationsabhängig:** `orchestrator/gates.d/86-mutgate.sh.example` liest einen Stryker-Bericht, erzwingt Floor und bisherigen Bestwert und kennt genehmigte äquivalente Mutanten. Ohne aktiviertes Gate und erzeugten Bericht gibt es keine Mutation-Prüfung. |
| Differential-, Property-, metamorphe und Invariantentests | [Differential Testing](https://www.cs.swarthmore.edu/~bylvisa1/cs97/f13/Papers/DifferentialTestingForSoftware.pdf), [Metamorphic Testing](https://arxiv.org/abs/2002.12543) und Property-Based Testing wie [QuickCheck](https://doi.org/10.1145/357766.351266) | Prüft gegen ein ausführbares Original oder gegen allgemeine Relationen, wenn kein einzelner Sollwert als Orakel existiert | **Vertrag/Prompt:** Die Rollenregeln verlangen geeignete Orakel, feste Seeds und Erhaltungsaussagen. Das Template liefert dafür keine universelle Testmaschine; Fixtures, Toleranzen, Relationen und Referenzaufrufe müssen im projektierten Repo real implementiert werden. |
| Anker, Quellenzitat und Golden-ADR | Datenprovenienz und kontrollierte Golden-Master-Änderungen | Verhindert empirische Konstanten aus Modellgedächtnis und macht Änderungen an erwarteten Ergebnissen begründungspflichtig | **Hart als Rollenvertrag, Gate konfigurationsabhängig:** Empirische Werte gehören nach `reference/anchors/*.json` und brauchen Quelle, Beleg-Zitat, Einheit und Toleranz. `orchestrator/gates.d/87-golden-adr.sh.example` erzwingt bei Golden-Änderungen ein ADR nur, wenn das Gate aktiviert ist. |
| Traceability-Check | Requirements Traceability aus qualitäts- und sicherheitskritischer Entwicklung | Verbindet Spezifikationskriterien mit ausführbaren Abnahmen und erschwert erfundene oder ungedeckte Anforderungen | **Konfigurationsabhängig und bewusst leichtgewichtig:** `orchestrator/gates.d/70-trace.sh.example` prüft Manifest, Kriterien, exakte Zitate/Quelldateien und deren Vorkommen in Acceptance-Dateien. Es beweist keine vollständige Gate-zu-Kriterium-Matrix und verlangt nicht in jeder einzelnen Testdatei eine Kriterien-ID. |
| Unabhängige Mini-Referenz für kritische Logik | [N-Version Programming](https://doi.org/10.1109/TSE.1985.231893) | Gibt dem Reviewer einen zweiten Rechenweg statt nur einer Plausibilitätsprüfung des Produktcodes | **Vertrag/Prompt:** Der Reviewer soll kritische Logik unabhängig nachrechnen. Weder die algorithmische Unabhängigkeit noch eine Übereinstimmung zweier Modellfamilien wird maschinell geprüft. |
| Compiler, Toolchain und eingefrorene Manifeste | Reproduzierbare Builds, Typechecking und Dependency-Locking | Lässt erfundene APIs, unauflösbare Versionen und nicht reproduzierbare Abhängigkeiten an ausführbaren Werkzeugen scheitern | **Hart für den Toolchain-Vertrag, sonst konfigurationsabhängig:** `bootstrap.sh` erzeugt `toolchain.json` aus `toolchain.json.example`; Schema, deklarierte Laufzeiten und Manifestexistenz werden geprüft. Dependency-, Lint-, Test- und Repro-Gates sind Projektvorlagen. Das Template stellt keine vollständig hermetische Container- oder Build-Umgebung her. |
| Screenshot-Gate | Visuelle Regression und multimodale Abnahme | Macht UI-Behauptungen prinzipiell an Bildartefakten prüfbar | **Konfigurationsabhängig mit enger Grenze:** `orchestrator/gates.d/84-shots.sh.example` führt `SHOTS_CMD` aus und bereitet das Artefaktverzeichnis vor. Das generische Gate beweist weder, dass Bilder erzeugt wurden, noch dass ein multimodales Modell sie tatsächlich angesehen hat; das muss das Projektkommando und der Reviewprozess sicherstellen. |

### Kontext-Engineering und spec-getriebene Steuerung

| Feature | Praxis- oder Forschungslinie | Wofür es gut ist | Tatsächliche Umsetzung und Grenze |
|---|---|---|---|
| Jede Phase ist eine frische Einweg-Session; das Repo ist Gedächtnis | Stateless Workflows und Befunde zur schlechteren Nutzung langer Kontexte, etwa [Lost in the Middle](https://aclanthology.org/2024.tacl-1.9/) | Reduziert Kontextdrift, macht Übergaben nachvollziehbar und erlaubt Wiederaufnahme aus versioniertem Zustand | **Hart auf Prozessebene:** Resume-/Continue-Flags sind verboten und jede Modellphase startet neu. Das garantiert weder identische Modellausgaben noch, dass ein externer Provider keinerlei serverseitigen Zustand hält. |
| Kontextliste je Prompt und Review-Diff seit `plan/<MS>` | Context Engineering und Changeset-orientiertes Review | Begrenzt die primäre Lesemenge auf Auftrag, Regeln, Fakten und die Änderung des aktuellen Meilensteins | **Hart für die erzeugten Prompts, nicht als Lese-ACL:** Die Prompts nennen Pflichtdateien; Review- und QA-Prompts zusätzlich den Diff-Bezug. Das Modell kann technisch weitere erlaubte Repo-Dateien lesen; vollständige Aufmerksamkeit für die Liste wird nicht bewiesen. |
| Dateibasierte Handoffs, Schemata und stabile Einwand-IDs | Strukturierte Übergaben, endliche Verhandlung und ADRs im Stil von [Nygard](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) | Macht Läufe prüfbar, wiederaufnehmbar und Konflikte punktweise beantwortbar | **Gemischt:** Verdicts, Pflichtfelder, Rundenbudgets und Zustandsübergänge sind **hart**; Begründungsqualität, korrekte Spec-Zitate und inhaltlich unabhängige Prüfung bleiben **Vertrag/Prompt**. |
| Kuratierte `LESSONS.md` mit Größenlimit | Reflexions- und Agent-Memory-Praxis mit bewusster Destillation | Bewahrt wiederverwendbares Wissen, ohne unbegrenzt selbst erzeugte Memos und Fehler anzusammeln | **Hart für den MCP-Schreibpfad:** `lessons_schreiben` ersetzt gezielt `orchestrator/LESSONS.md` und begrenzt sie auf 16.000 Zeichen. Auswahl und Wahrheit der Lektionen werden kuratiert, nicht automatisch bewiesen. |
| Projektierung, Intake und `projektierung/SPEC-KONTRAKT.md` | Spec-driven Development, wie es auch [Spec Kit](https://github.github.com/spec-kit/index.html) und [Kiro Specs](https://kiro.dev/docs/cli/v3/specs/) verfolgen | Führt vor dem autonomen Lauf zu einer klaren Vision, überprüfbaren Kriterien und einem messbaren Qualitätsmaßstab | **Betreiberprozess:** Checklisten, Vorlagen und Freigabeschritte existieren, werden aber nicht vom normalen Meilensteinlauf automatisch inhaltlich ausgefüllt. Die Qualität des Maßstabs bleibt eine Betreiberentscheidung. |
| Entschieden, offen, verworfen und `BACKLOG.md` | Scope- und Decision-Management | Verhindert, dass Brainstorming still zur Anforderung wird oder nicht gelöste Befunde verschwinden | **Vertrag/Prompt:** Die Taxonomie und Backlog-Pflichten sind vorgegeben; Vollständigkeit und korrekte Einordnung lassen sich nicht allgemein maschinell beweisen. |

### Zuverlässigkeitstechnik, Provenienz und Sicherheit

| Feature | Praxis- oder Forschungslinie | Wofür es gut ist | Tatsächliche Umsetzung und Grenze |
|---|---|---|---|
| Retry mit Backoff nach Fehlerklasse | Resilienzpraxis verteilter Systeme | Fängt erkannte Rate-Limits, Netzwerk-Timeout-Muster und vorübergehende Transportfehler ab, ohne eine fachliche Rework-Runde zu zählen | **Hart für erkannte Muster:** Retries und Backoff sind begrenzt. Die Erkennung ist regex-basiert, hat keinen Jitter und kann unbekannte Providertexte oder ein bloß anders formuliertes `HTTP 429` übersehen. Ein durch `PHASE_TIMEOUT` ausgelöster Exit 124 wird nur dann wiederholt, wenn der Logtext zusätzlich einem Transportmuster entspricht. |
| Atomarer Lock, verwaiste Locks, Heartbeat, Watchdog, STOP, Timeouts und Wiederaufnahme | SRE- und Distributed-Systems-Praxis | Verhindert Doppelstarts, unterscheidet abgestürzte von aktiven Läufen und setzt harte Grenzen gegen Endlosschleifen | **Hart mit Betriebsgrenzen:** Lock, PID-Prüfung, Marker und Rundenbudgets sind implementiert; der Watchdog muss extern geplant werden. Der Heartbeat wird an Phasengrenzen aktualisiert, daher kann eine lange Modellphase vorübergehend alt aussehen. STOP beendet als FATAL; fehlt das Systemprogramm `timeout`, läuft der Fallback ohne erzwungenes Modell-Timeout. |
| Leiter Rework → Rebuild → Arbiter → Park | Begrenzte Eskalationspolitik gegen lokale Reparaturschleifen | Wechselt nach wiederholtem Scheitern vom Patchen zum Neuaufbau, terminiert Streit und lässt unabhängige Meilensteine weiterlaufen | **Hart, sofern die Stufen aktiviert sind:** Rebuild beginnt ab der konfigurierten Runde und setzt nur `REBUILD_PATHS`, nicht automatisch das gesamte Builder-Territorium, auf den Planstand zurück. Geparkte Abhängigkeiten blockieren weiterhin ihre Nachfolger. |
| SHA-, Werkzeug-, Konfigurations-, Log- und Tag-Provenienz | Reproduzierbarkeitskultur und Provenienzmodelle wie [SLSA](https://slsa.dev/spec/v1.2/provenance) | Macht sichtbar, welcher Stand mit welchen Werkzeugen geprüft und abgeschlossen wurde | **Hart, aber nicht vollständig:** `gates.json` enthält Basis-/aktuellen SHA und Werkzeugversionen; Logs, Phasencommits und Tags dokumentieren den Lauf. Die `CONFIG`-Zeile enthält ausgewählte Ablaufwerte, nicht jede Konfiguration, jeden Dokument-Hash oder eine hermetische Attestation. |
| Least Privilege gegenüber den Modellrollen | Separation of Duties und Least Privilege, etwa die Kontrollen AC-5/AC-6 in [NIST SP 800-53](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) | Begrenzt Schäden durch Prompt Injection, Fehlbedienung oder absichtliches Umgehen der Abnahme | **Hart innerhalb der Harness-Kontrollen:** Git-Diff-Territorien einschließlich ignorierter Pfade, Log-Hash-Schutz, minimierte Rollen-Umgebungen, bekannte Secret-Migration und verbotene Bypass-Flags sind implementiert. Das ist keine OS-Benutzer- oder vollständige Leseisolation; Rollen teilen Repo und `HOME`, externe CLI-Sandboxes müssen separat wirksam sein, und Betreiber können die CLI-Rollenwächter bewusst abschalten. |
| Gehärteter MCP-Pfadzugriff | Path-Traversal-Abwehr mit kanonischen Pfaden, Symlink-Prüfung und Denylist für sensible Dateien | Verhindert, dass relative Pfade oder Symlinks aus der Repository-Grenze beziehungsweise in `.env`- und `.git`-Inhalte führen | **Hart für die getesteten Connector-Werkzeuge:** `realpath`-, Repo-, `.env`-, `.git`- und Symlink-Prüfungen sind abgedeckt. Der Connector ist wegen `lessons_schreiben` nicht vollständig read-only; ein veröffentlichter Tunnel bringt laut eigener Dokumentation keine Authentisierung mit. |

Der größte belastbare Nutzen entsteht damit nicht aus der bloßen Zahl der
Modelle, sondern aus getrennten Schreibrechten, ausführbaren
Abnahmekriterien, begrenzten Schleifen und prüfbarer Provenienz. Eine
vollständige, feingranulare Funktionsinventur des v1.0-Templates steht
in `docs/template/T5-INVENTAR.md`; die Tabellen hier beschreiben die
übergeordneten Entwurfsentscheidungen und deren Grenzen.
