# Plan A — Harness-Template („Werkbank")

> Template-interne Konstruktionsunterlage; Zielprojekte dürfen `docs/template/` löschen.

Stand 19.07.2026. Quellen: Demiurg-Repo (HEAD 7f12c50, M6 in Rework r4),
Autonomie-Patch v2 vom 17.07., Betreiber-Blöcke vom 17.07. (venv weg,
QA-Schalter, Budget 8, Probe-strict, tmux-Start).

## A0 Zielbild

Ein Repo `harness-template`, aus dem jedes neue Projekt entsteht.
Fertig heißt: `git clone` + `bash bootstrap.sh` auf einem frischen Laptop
ergibt einen lauffähigen Harness-Rohbau samt MCP-Server und Tunnel.
Projektspezifisch bleiben nur vier Dinge: `docs/`, `milestones.json`,
die Gate-Skripte in `gates.d/` und der Projektblock in AGENTS.md.
Der Weg vom Besprechungs-Destillat zu genau diesen vier Dingen ist
selbst Teil des Templates: die Projektierungsschicht (A7).
Demiurg wird dabei nicht umgebaut — es bekommt später den v3-Minimalschnitt
(A8, Schritt 3), der aus dem fertigen Template zurückgeschnitten wird.

## A1 Repo-Layout

```
harness-template/
  AGENTS.md                  # generischer Regelblock + leerer Projektblock
  CLAUDE.md                  # Zeiger auf AGENTS.md
  IMPLEMENTATION-RULES.md    # Reviewer-Land: verbindliche Bauregeln (A9)
  contracts/
    PROTOCOLS.md             # dateibasiertes Rollen-Protokoll (A9)
    api/                     # Public-API-Snapshots fürs api-Gate
  BACKLOG.md                 # nonblocking-Befunde, Reviewer-Besitz (A9)
  PROGRESS.md                # Langzeit-Gedächtnis, Builder schreibt (A3.7)
  bootstrap.sh               # Ersteinrichtung auf neuem Laptop (A4)
  start.sh                   # tmux-Start + Transportprobe (Muster „Block H")
  config.env.example         # Rollen, Budgets, Kommandos, Notify (A2)
  toolchain.json.example     # Laufzeiten, Versionen, Manifeste (A3.9)
  .gitignore                 # config.env, node_modules, .venv, reports/, *.lock
  orchestrator/
    orchestrate.sh           # Phasenschleife, Leiter, Lock, Retry, Notify
    verifier.sh              # nur noch Runner: iteriert gates.d/ (A3.2)
    gates.d/                 # Steckplätze; Demiurg-Gates als *.example
    status.sh                # schreibt STATUS.md + state/summary.json (A3.1)
    notify.sh                # ein curl an NOTIFY_URL (A3.4)
    watchdog.sh              # cron-Wächter für Heartbeat-STALE (A3.4)
    milestones.json.example  # Schema mit deps-Feld
    prompts/                 # 10,20,30,40,45,50,60 + NEU 62-rebuild, 70-arbiter
    handoff/SCHEMA.md        # Patch-Fassung: ref-Pflicht, [INFRA]/[QA-PENDING]
    LESSONS.md               # leer, nur Kopf + Deckel-Hinweis (16 kB)
    mcp/server.*             # generischer Read-only-Server (A2, letzter Punkt)
  docs/                      # projektleer; 00-vision.md.template als Ausfüllhilfe
    template/                # interne Bau-/Abnahmenachweise; im Zielprojekt löschbar
  reference/
    anchors/                 # normative Referenzwerte samt Beleg (A3.6)
  projektierung/
    SPEC-KONTRAKT.md         # Formatvertrag für docs/ und Kriterien (A7.1)
    PROJEKTIERUNG.md         # Playbook: Destillat → befüllte Maschine (A7.2)
    INTAKE-CHECKLISTE.md     # Pflichtfelder des Besprechungs-Destillats (A7.3)
    presets/                 # software-ts/, text/, daten/ (A7.4)
    beispiel/                # Demiurg-Auszug als Messlatte (A7.5)
  RUNBOOK.md                 # Betreiber-Handgriffe: PARKED, Arbiter, FATAL
```

## A2 Extraktion aus Demiurg — Datei für Datei

`orchestrate.sh` übernehmen und entkoppeln: alle projektfesten Kommandos
hinter config-Variablen (`BUILD_CMD`, `TEST_CMD`, `DEV_CMD`, `PKG`).
Übernommen wird ausdrücklich auch die stille Bestandsmechanik:
STOP-Datei zwischen den Phasen, Git-Sauberkeits-Check vor jedem Lauf,
Phasen- und Rundenzustand (`state/<MS>/round`, `*.done`,
`qa-requested`), Ablage der Planphase unter `plan/<MS>` als
Bezugspunkt des Rebuilds. Ebenfalls Bestand und mitzunehmen (docs/12
§5, §5b, §6): PREFLIGHT als Phase 0 — verifiziert die realen
CLI-Flags per `--help` statt sie anzunehmen, Kommando-Templates in
config.env, Prompts Quoting-sicher über `$PROMPT_FILE` und je Phase
in logs/ archiviert, Resume-Flags verboten (jede Phase ist eine
frische Session); idempotente Wiederaufnahme (fertige Phasen werden
übersprungen); lineare Git-Historie mit Tags `plan/<MS>` und
`done/<MS>`, nie force-push; `PHASE_TIMEOUT` und `MAX_MS_PER_RUN`
als Limits; die Verbotsliste gefährlicher Flags
(`--dangerously-skip-permissions`, `bypassPermissions`,
Yolo-/Full-Access-Modi) samt Sandbox- bzw. Permission-Modus je Rolle.
Danach die Patch-v2-Mechanik einweben — Transport-Retry für alle drei
Rollen (rc 124/137, 429/5xx, ECONNRESET → Backoff bis `RETRY_MAX`),
Lock unter `orchestrator/.lock` mit Erkennung verwaister Locks,
Territoriumsverletzung als ein Retry mit Ansage statt Sofortabbruch,
Strategieleiter (Rework → Rebuild ab `REBUILD_ROUND` mit Prompt 62 →
Arbiter mit Prompt 70 → Park & Continue, Exit-Code 3), QA-Park statt
Rundenverbrennen, Notify-Aufrufe an den Ereignispunkten, CONFIG-Zeile
je Lauf ins orchestrate.log. Kollisionsliste A2.1 beachten.

`verifier.sh` zum Runner umbauen (A3.2); die vorhandenen Demiurg-Gates
(tests, e2e, shots, mutgate, lint, deps, smoke, api, graph, bench,
trace, assets, golden_adr) wandern als `gates.d/*.example` mit —
mutgate in der v2-Fassung: Tod vor der Mutation ⇒ Status `error` statt
`fail`, Ratchet-Schwelle max(`MUT_SCORE_FLOOR`, Baseline − Toleranz),
Baseline in `state/mut-baseline`, Äquivalenz nur per Reviewer-Approval.

`status.sh` auf Vertrag v1 heben: schreibt weiterhin STATUS.md für
Menschen und zusätzlich `state/summary.json` für Maschinen (A3.1),
Aufruf am Ende jeder Phase.

`prompts/10–60` unverändert übernehmen, Projektbezüge raus;
`62-rebuild.md` und `70-arbiter.md` aus dem Patch-Ordner `full/`;
in 20/30/40/50/60/62 die Zeile „lies orchestrator/LESSONS.md, falls
vorhanden" ergänzen (Patch-Inhalt).

`handoff/SCHEMA.md` in der Patch-Fassung: blocking-Befunde nur mit ref
(Gate, Kriteriums-ID oder Spec-Zitat), [INFRA] und [QA-PENDING] sind
für den Builder nonblocking. Dazu das Verhandlungsprotokoll aus
docs/12 §3: Einwände mit IDs und Punkt-für-Punkt-Antworten, höchstens
zwei Plan-Verhandlungsrunden, Präzedenzregel Spec > Reviewer > Builder
(deckendes Spec-Zitat schlägt den Einwand; schweigt die Spec, bindet
nach Rundenende das Reviewer-Urteil und wird als ADR dokumentiert;
widersprüchliche Spec ⇒ ESCALATE), nonblocking-Befunde wandern nach
BACKLOG.md, und jeder spätere PLAN muss offene Einträge adressieren
oder begründet vertagen.

`milestones.json.example` mit dokumentiertem Schema:
`[{id, title, criteriaRef, deps: [], effort: "low|high|max"}]` —
fehlt `deps`, gilt strikt der Vorgänger (Patch-Verhalten, getestet).

`config.env.example`: `BUILDER_MODEL/CMD`, `REVIEWER_MODEL/CMD`,
`QA_MODEL/ENDPOINT`, `QA_ENABLED`, `MAX_ROUNDS_REWORK=8`,
`REBUILD_ROUND=4`, `ARBITER_EXTRA_ROUNDS`, `RETRY_MAX`, `NOTIFY_URL`,
`NOTIFY_TOPIC`, `BUILD_CMD`, `TEST_CMD`. Echte config.env bleibt
untracked (Keys), wie heute bei Demiurg. Neu: `AUTONOMY_LEVEL` 0–3
als Vorwahl — 0 phasenweise mit Halt, 1 ein Meilenstein je Lauf,
2 autonom mit Leiter (Default), 3 Nachtlauf per Timer (der Lock
macht ihn gefahrlos). Die Stufe setzt nur Defaults für
`MAX_MS_PER_RUN`, QA, Leiter und Notify und bleibt einzeln
überstimmbar. Geheimnisse stehen nie in `config.env`, sondern ausschließlich
in der unversionierten Datei `orchestrator/secrets.env`; Modellphasen erhalten
nur die dokumentierte Umgebungs-Allowlist.

AGENTS.md zweiteilen. Generischer Block: die Territorienkarte aus
docs/12 §1 — Builder schreibt src, tools, tests/unit, PROGRESS.md
und ADRs, nie Abnahmetests, Specs, orchestrator, RULES, PROTOCOLS
oder BACKLOG; QA schreibt tests/e2e, tests/fuzz, QA.md und BACKLOG
und hat bewusst keine Verdict-Macht, ihre Befunde sind ausführbare
Tests; der Reviewer besitzt Abnahmetests, `reference/anchors/**`,
Handoff, IMPLEMENTATION-RULES, PROTOCOLS, die Graph-Regeln, BACKLOG
und `docs/decisions/`; orchestrator/** bleibt Betreiber-Land; der
Verifier erzwingt alles per git-diff je Phase. Dazu die sechs
Abnahme-Integritätsregeln wörtlich und die Handoff-Disziplin.
Projektblock: Pflichtfelder Vision-Verweis, Spezifika,
Territorien-Ergänzungen.

MCP-Server generalisieren: `REPO_PATH` und `PORT` aus der Umgebung,
Tool-Fläche identisch zu Demiurg (befehl-Allowlist, lies, liste,
lessons_schreiben als einziger Schreibpfad). Tunnel: benannter
Cloudflare-Tunnel empfohlen (stabile URL, Leitstand-Kacheln müssen
dann nie editiert werden); Quick-Tunnel bleibt als Nullkonfig-Weg.
Bei benanntem Tunnel den MCP-Pfad zufällig wählen
(`/mcp-<zufall>`): Adresse stabil, aber nicht erratbar; bootstrap
fragt `TUNNEL_MODE=quick|named` ab.

### A2.1 Kollisionen Patch v2 ↔ Betreiber-Blöcke

1. QA-Park ist doppelt gedacht (Block-Schalter vs. Patch-Parklogik):
   Patch-Fassung gewinnt (parkt vor Rundenverbrauch), `QA_ENABLED`
   bleibt als Schalter erhalten.
2. Probe-strict aus Block H bleibt — der Patch kennt sie nicht.
3. Rundenbudget: Block setzte 8 (ADR-024), Patch-Default war 6 → 8 behalten.
4. `git apply` der v2-Diffs wird auf orchestrate.sh reißen (Datei seit
   17.07. 11:52 zweimal verändert). Deshalb: Inhalte einweben statt
   patchen; die `full/`-Dateien nur als Referenz, nie als Ersatz.

## A3 Vertrag v1 (normativ — genau das, was der Leitstand kennt)

Die Pfade und Dateinamen aus A1 sind selbst Vertragsbestandteil:
jedes Harness trägt dasselbe Skelett an denselben Orten —
orchestrator-Struktur, Log-Namensschema, state-, handoff-, anchors-
und ADR-Pfade, STATUS.md und summary.json. Nur die
Nutzlast-Verzeichnisse (src/tools/tests bei Software, kapitel/ und
Bibeln beim Text) kommen aus dem Typ-Preset — und sind innerhalb
eines Typs ebenfalls fix. PREFLIGHT prüft die Vertragspfade beim
Start; das contract-Feld in summary.json versioniert das Layout für
spätere Änderungen.

### A3.1 state/summary.json — eine Datei, eine Wahrheit

```json
{
  "contract": 1,
  "project": "demiurg",
  "ts": "2026-07-19T09:08:41+02:00",
  "milestone": { "id": "M6", "index": 7, "total": 18 },
  "phase": "60-rework",
  "round": 4,
  "needs_human": false,
  "reason": "",
  "gates": { "tests": "fail", "mutgate": "error", "lint": "pass" },
  "parked": [],
  "last_events": ["REVIEW r3 REWORK", "gates r3 fail"],
  "exit": null
}
```

Geschrieben von status.sh nach jeder Phase. `ts` ist zugleich der
Heartbeat. STATUS.md bleibt die menschliche Sicht daneben bestehen.

### A3.2 Gate-Steckplatz

`gates.d/NN-name.sh`, ausführbar. Umgebung: `REPO_ROOT`, `MILESTONE`,
`ROUND`. Exit 0 = pass, 1 = fail, 2 = error (Infrastruktur — zählt
nicht als Builder-Fehlschlag und geht als `error` in gates.json).
Letzte stdout-Zeile = Kurzbefund. Der Runner schreibt je Gate
`state/<MS>/gate-<name>.log` und aggregiert gates.json im
Demiurg-Schema (milestone, base, env, gates, result).

Gate-Beispiele für Nicht-Software-Projekte gehören mit ins Template:
`laengenkorridor.sh` (wc gegen Zielband je Kapitel), `stil-lint.sh`
(grep gegen Verbotene-Wörter-Liste), `kontinuitaet.sh` (LLM-Judge per
API-Call, JSON-Verdict auf Exit-Code gemappt), `zitate.sh`
(Quellenbelege vorhanden).

### A3.3 Logs

`<MS>-<phase>-r<runde>-a<versuch>-<zeitstempel>.log` plus ein
phasenbezogenes
`-prompt.md`; `orchestrate.log` als Metaspur; Verdikt-Logs (Review,
QA, Acceptance) klein halten, Transkripte ungekürzt lassen.

### A3.4 Notify und Watchdog

`notify.sh` sendet an `NOTIFY_URL` (ntfy-kompatibel) bei: FATAL,
PARKED, ARBITER, NEEDS_HUMAN, DONE. `watchdog.sh` läuft per cron
alle 15 min: Orchestrator-Prozess vorhanden, aber summary-`ts` älter
als 30 min → STALE-Meldung. Leerer `NOTIFY_URL` = alles aus.

### A3.5 Exit-Codes

0 fertig · 2 FATAL · 3 fertig-mit-geparktem-Meilenstein.

### A3.6 Anker — Erwartungswerte unter Änderungskontrolle

`reference/anchors/*.json`: jeder Anker trägt Wert, Einheit, Toleranz,
`source_url` und ein wörtliches Beleg-Zitat (Demiurg-Muster aus
docs/12 und ADR-001). Laufzeitcode, Pipeline und Tests beziehen ihre
Konstanten aus diesen Dateien statt aus Magic Numbers; Abnahmetests
prüfen „anchored" gegen sie. Territorium: Reviewer. Der Builder liest,
ergänzt und ändert nie; Wertänderungen laufen ausschließlich über ein
ADR. Das ist das erlaubte Gegenstück zur Integritätsregel gegen
hartkodierte Erwartungswerte: Erwartungswerte existieren, aber nur
hier — mit Herkunft, Toleranz und Änderungsprotokoll. `mut-baseline`
(A2) ist der maschinengeschriebene Sonderfall desselben Musters, und
das golden_adr-Gate prüft die Kopplung Anker ↔ ADR. Typübergreifend:
im text-Preset sind Stilbibel, Figurenbibel und Längenbänder die
Anker, im daten-Preset Schemata und Goldwert-Outputs.

### A3.7 Kontexthygiene — frische Session, Gedächtnis im Repo

Jede Phase ist ein Einweg-Aufruf und damit konstruktiv eine frische
Session; PREFLIGHT verweigert Resume-Flags. Das Gedächtnis ist das
Repo, nie der Chat, mit fester Taxonomie: AGENTS/RULES/PROTOCOLS
(Regeln), Specs + CRITERIA (Auftrag), PLAN/REVIEW/VERDICT
(Verhandlungsstand), PROGRESS.md (Langzeit), gates.json (Fakten),
BACKLOG.md (offene nonblocking-Befunde). Jeder Prompt trägt sein
Kontextmanifest — die exakte Leseliste. Reviews lesen den Diff seit
`plan/<MS>`, nicht das Repo; der Kontext wächst mit dem Meilenstein,
nicht mit der Codebasis. Handoff ist je Meilenstein isoliert, Rework
liest nur die jeweils letzte REVIEW.md. Stateless-Phasen sind
reproduzierbar und driftfrei — „frisch" ist hier Feature, kein
Risiko. (docs/12 §5b)

### A3.8 Anti-Halluzinations-Schicht

Gates fangen Faulheit und Gaming; gegen Halluzination braucht es
Grounding. Vertragsklassen, je Projekt konkret zu besetzen
(docs/12 §7a als Muster):

1. Orakel-Strategie: existiert ein Original, Differentialtests
   dagegen — bei Demiurg das R-Original als Orakel (Fixtures,
   Toleranz 1e-9, Ausnahmen nur für dokumentierte Bugfixes mit
   handgerechneten Ankern); beim Buch Quellen- und Figurenbibel.
   Existiert keins: orakelfreie Tests — metamorphe Relationen,
   Property-Tests mit festen Seeds, Erhaltungssätze als Asserts.
2. Anker statt Gedächtnis (A3.6): nackte Literale sind ein Befund;
   Unverifizierbares wird Einwand, nie Schätzung.
3. Traceability: CRITERIA muss wörtliche Substrings der Roadmap
   enthalten (Volltext-Check im Verifier) und beidseitig mit Tests
   verlinkt sein — erfundene Anforderungen und ungedeckte Kriterien
   fallen maschinell auf.
4. N-Version für kritische Logik: der Reviewer legt in den
   Abnahmetests eine unabhängige Mini-Referenzimplementierung an;
   zwei Modellfamilien müssen unabhängig zum selben Ergebnis kommen.
5. Schnittstellen-Halluzination stirbt in der Werkzeugkette:
   strikter Compiler bzw. Validator, eingefrorene Abhängigkeiten
   (deps-Gate), Smoke-Gate.
6. Provenance: gates.json trägt SHA und Toolversionen,
   Phasen-Dokumente den Basis-SHA — Behauptungen ohne ausgeführten
   Beleg existieren im Protokoll nicht.
7. Redteam als ständige dritte Rolle: bewusst eine andere
   Modellfamilie (dekorrelierte Fehlerbasis), liest das ganze Repo,
   sucht Gegenbeispiele gegen die Invarianten; Befunde werden neue
   Property-Tests, nie Prosa.

Leitprinzip: Prompts erinnern, Gates erzwingen — jede wichtige Regel
wird in ein Gate übersetzt; was nicht maschinell prüfbar ist, bekommt
Gewaltenteilung.

### A3.9 Toolchain — Laufzeiten als Vertrag

`toolchain.json` deklariert je Projekt die benötigten Laufzeiten und
Werkzeuge mit Versionen (node, python, R, …) und die zugehörigen
Paket-Manifeste (Lockfile, requirements/uv.lock, renv.lock).
bootstrap.sh installiert danach; `bootstrap.sh --update` aktualisiert
idempotent nach. PREFLIGHT verifiziert die realen Versionen — wie bei
den CLI-Flags: prüfen statt annehmen. Das deps-Gate generalisiert auf
alle Ökosysteme: installiert wird nur aus eingefrorenen Manifesten;
Paketänderungen sind gewöhnliche Manifest-Commits des Builders und
laufen durchs Gate, Versionswechsel der Laufzeiten selbst sind
Betreiber-Sache (toolchain.json ist Betreiber-Territorium).
Umgebungen (venv, renv-Bibliothek, node_modules) liegen außerhalb
des Arbeitsbaums oder auf der Ignore-Liste sämtlicher Werkzeuge —
die M3-Lehre, als eine .venv im Baum Strykers Sandbox-Kopie zerlegte
und fünf Rework-Runden kostete, wird damit Regel statt Erinnerung.

## A4 bootstrap.sh

Prüft git, tmux, jq, curl und installiert die in toolchain.json
deklarierten Laufzeiten samt Manifesten (A3.9); `bootstrap.sh
--update` zieht sie später idempotent nach.
Kopiert config.env.example → config.env und öffnet den Editor.
Startet den MCP-Server in tmux-Session `mcp-<slug>`, zieht den Tunnel
hoch, druckt die URL mit dem Hinweis „im Leitstand eintragen".
Läuft status.sh einmal als Smoke und validiert summary.json per jq
gegen das Schema. Idempotent: zweiter Aufruf repariert statt doppelt.

## A5 Checkliste „Neues Projekt"

1. Template klonen, Slug vergeben; den rein template-internen Ordner
   `docs/template/` im Zielprojekt löschen.
2. Projektierung fahren (A7): Destillat gegen die Intake-Checkliste
   prüfen, dann per PROJEKTIERUNG.md die docs/, milestones.json,
   Gate-Liste und den AGENTS-Projektblock erzeugen lassen —
   du redigierst, wie bei der Demiurg-Vorplanung.
3. M0 ist immer „Gerüst steht, alle Gates laufen leer durch".
4. Gates stecken: aus `gates.d/*.example` oder dem Typ-Preset
   übernehmen; neue nach dem Steckplatz-Vertrag A3.2 schreiben.
5. config.env füllen (Modelle je Rolle, `NOTIFY_TOPIC` = `dl-<slug>`).
6. `bootstrap.sh` auf dem Ziel-Laptop, Tunnel-URL in den Leitstand.
7. Probelauf M0. Erst wenn der grün ist, echte Meilensteine starten.

## A6 Abnahme des Templates (eigene Medizin)

T-1 Frisches Verzeichnis, bootstrap ohne Fehler, summary.json
validiert. T-2 Dummy-Projekt mit zwei Mini-Meilensteinen und zwei
Gates läuft unbeaufsichtigt durch, inklusive eines absichtlich roten
Gates → Rework → grün. T-3 Leiter greift: erzwungener Dauer-Fail
führt in Rebuild (Runde 4) und danach in den Arbiter; Park erzeugt
Exit 3 und ESCALATION-Datei. T-4 notify feuert bei PARKED und DONE;
watchdog meldet STALE bei angehaltenem status.sh.
T-5 Inventar-Abgleich: jede Funktion aus Demiurgs orchestrate.sh,
AGENTS.md, docs/12 (autonomer Bau) und Patch v2 ist im Template mit
Fundstelle nachgewiesen oder als
bewusst weggelassen begründet; Prüfliste ist das Vollinventar in A9
— die Frage „sind alle Features drin?"
wird damit zum Gate statt zum Gefühl.
Beleg-Regel gilt auch hier: keine Abnahme ohne ausgeführten
Kommando-Output als Nachweis.

## A7 Projektierungsschicht — der Teil, der bisher fehlte

A1–A6 beschreiben die Maschine. Was fehlte, ist der Weg vom
Besprechungs-Destillat zur befüllten Maschine. Bei Demiurg hieß dieser
Schritt „Vorplanung" (sieben Spezifikationen, nummerierte Kriterien,
Roadmap) und entstand freihand. Eine KI kann ihn nur wiederholen,
wenn das Verfahren selbst im Template steht. Grundsatz: Das Template
kann das Projektwissen nicht enthalten — aber es kann die Fragen
enthalten. Und die Integritätsregel gilt schon hier: Lücken im
Destillat werden erfragt, nie still aufgefüllt.

### A7.1 SPEC-KONTRAKT.md

Formatvertrag für docs/: welche Dokumente (Vision, Fachspezifikationen
je Domäne, Roadmap), wie Kriterien aussehen — nummeriert im
O-M6-1-Stil, einzeln prüfbar formuliert („Artefakt X existiert unter
Pfad Y und erfüllt Z", nie „funktioniert gut"), mit Beleg-Erwartung.
milestones.json verweist per criteriaRef auf diese IDs; Prompt 10
(Acceptance) liest genau dieses Format und macht Abnahmetests daraus.
Kriterien mit Zahlenwerten wiederholen die Werte nicht, sondern
binden per ankerRef an `reference/anchors/` (A3.6).
Die ADR-Konvention für spätere Vertragsänderungen gehört ebenfalls
hierher.

### A7.2 PROJEKTIERUNG.md

Das ausgeschriebene Playbook — zugleich der Wizard-Schritt-3-Prompt
aus Plan B, hier versioniert statt im Artefakt hartkodiert. Ablauf in
fester Reihenfolge: Intake prüfen (A7.3), fehlende Pflichtfelder
erfragen; dann erzeugen: Scope samt Out-of-Scope-Liste →
Meilenstein-Schnitt (M0 Gerüst; je Meilenstein drei bis sieben
Kriterien nach SPEC-KONTRAKT; deps) → Gate-Zuordnung mit Begründung
je Gate → Stack- bzw. Formatfestlegung aus dem Preset →
AGENTS-Projektblock → offene Risiken. Liegt mehr Material vor als
die acht Felder — ausdiskutierte Features, Mechanik-Kataloge,
Detailentscheidungen —, wird es nicht gekürzt, sondern sortiert:
entschieden → Fachspezifikation mit Kriterien, bindend; erwogen,
aber offen → Katalog-Dokument oder BACKLOG, ausdrücklich nicht
bindend; verworfen → Out-of-Scope-Liste. Demiurg-Muster: docs 08–11
und 13 sind genau solche Katalog-Spezifikationen für spätere
Meilensteine. Nur was der Betreiber freigibt, erhält Spec-Rang.
Ausgabe als Dateien, nicht als
Prosa. Danach Redaktion durch den Betreiber — dieser Schritt bleibt
Handarbeit, absichtlich.

### A7.3 INTAKE-CHECKLISTE.md — was der Betreiber liefert

Acht Pflichtfelder, jedes mit festem Zielort. Der Betreiber liefert
Entscheidungen und Quellen, keine Ausarbeitung:

1. Vision in drei Sätzen (was, für wen, warum) → docs/00-vision und
   AGENTS-Projektblock.
2. Zielgruppe und Nutzungskontext → Vision, Qualitätsmaßstäbe.
3. Out-of-Scope-Liste — was das Projekt ausdrücklich nicht ist →
   Scope-Kapitel; verhindert Feature-Drift in den PLAN-Phasen.
4. Stack- bzw. Formatentscheidung, oder ausdrücklich „offen,
   Optionen: …" → Preset-Wahl, `BUILD_CMD`/`TEST_CMD`, M0-Zuschnitt,
   toolchain.json (Laufzeiten, Werkzeuge, Versionen).
5. Qualitätsmaßstab je Kernfeature, messbar formuliert → wird zu
   nummerierten Kriterien (SPEC-KONTRAKT) und steuert die
   Gate-Auswahl.
6. Datenquellen, Referenzen, Originale (Links genügen) → reference/,
   Anker-Harvest des Reviewers, Orakel-Strategie (existiert ein
   Original, gibt es Differentialtests).
7. Bekannte Risiken und offene Fragen → Risikoteil des ersten PLAN,
   BACKLOG-Startbestand.
8. Rollenbesetzung und Budget (Modelle je Rolle, Rundenlimits,
   effort je Meilenstein) → config.env, milestones.json.

Dazu als Anhang der Rohtext der Multi-KI-Besprechung. Werden die
Besprechungen gegen diese Liste geführt, ist ihr Ergebnis automatisch
projektierungsfähig; fehlt ein Feld, fragt die Projektierung nach —
sie füllt nie still auf.

### A7.4 presets/

Typ-Bausteine als Text, nicht als Code. software-ts: Stack-Spezifikation
(vitest, Playwright, Stryker), Territorienkarte (src und tests/unit
Builder, tests/e2e QA), Gate-Grundsatz, was M0 baut. text: Repo-Layout
(kapitel/, stilbibel.md, figurenbibel.md), was „Build" heißt
(Manuskript-Render plus Wortzahlbericht), Gate-Satz laengenkorridor /
stil-lint / kontinuitaet / zitate, QA als Konsistenzlauf gegen die
Stilbibel. daten: Pipeline-Layout, Gates auf Schema-Validierung und
Reproduzierbarkeit. Das Preset fließt als Baustein in die docs ein;
den Rest entscheidet die Projektierung.

### A7.5 beispiel/

Ein gekürzter Demiurg-Auszug als Messlatte: die echte milestones.json,
ein Meilenstein komplett durchgezogen (Kriterien ↔ Abnahmetest ↔
REVIEW.md ↔ gates.json), ein ADR und ein Anker-JSON mit Beleg-Zitat. KIs schreiben auf dem Niveau ihrer
Vorlagen — ohne Beispiel wird jede Generierung generisch, egal wie gut
das Playbook ist.

Dazu RUNBOOK.md auf oberster Ebene: die Betreiber-Handgriffe bei
PARKED (Ursache beheben, state/<MS>/parked löschen, neu starten),
Arbiter-HUMAN-Verdict, FATAL, Tunnel-Neustart — destilliert aus dem
Patch-README und den Betreiber-Blöcken vom 17.07.

## A8 Reihenfolge

1. Leitstand v0 (Plan B) kann sofort — er braucht das Template nicht,
   weil sein Status-Abruf einen STATUS.md-Fallback hat.
2. Template bauen: Extraktion + Patch-Auflösung, gates.d-Umbau,
   Projektierungsschicht (A7, inkl. beispiel/-Auszug aus Demiurg),
   bootstrap — dann Abnahme T-1 bis T-5 (A6). Werkzeug: Codex CLI oder
   Claude Code im
   eigenen Template-Repo — ausdrücklich nicht im Demiurg-Harness.
   Größenordnung ein Tag Agent-Arbeit plus deine Reviews.
3. Demiurg-v3-Minimalschnitt aus dem fertigen Template zurück:
   mutgate v2, Findings-Disziplin, notify.sh, Lock. Einspielen in der
   nächsten Laufpause (M6 grün oder geparkt). Volle Leiter und
   deps-Graph für Demiurg optional danach. Das fehlende
   MC-Fit-Artefakt (A-M6-4/5) bleibt davon unberührt — echter Befund,
   normaler Rework-Weg.
4. Nachrüst-Kit für Bestands-Harnesses (Liqui, pbpk-literature):
   status.sh, summary.json und notify.sh als Mini-Paket, damit sie im
   Leitstand vollwertig erscheinen statt nur über den Fallback-Parser.
   Vorher Bestandsaufnahme: welche Zustandsdateien existieren dort
   heute überhaupt, und wer schreibt sie.

## A9 Vollinventar Multi-Agenten-Mechanik

Prüfliste für T-5. Quellen: docs/12 (§-Angaben), AGENTS.md (wird als
Block wörtlich übernommen und hier nicht zeilenweise wiederholt),
Patch v2. Die docs 01–11 und 13 sind Projektinhalt, keine
Harness-Mechanik — bewusst nicht Teil des Templates.

Konstruktionsprinzipien (docs/12, Kopf): Gewaltenteilung — wer baut,
prüft nicht ab. Deterministische Gates — Maschinen entscheiden über
grün/rot, Modelle nie über sich selbst. Dateibasiertes Protokoll mit
Schemata statt Chat. → Präambel des generischen AGENTS-Blocks.

Rollen (§1): drei Modellfamilien; QA ohne Verdict-Macht, Befunde als
ausführbare Tests; Territorienkarte samt Verbotslisten; Erzwingung
per git-diff je Phase. → A2 (AGENTS.md), territory-Gate.

Phasen (§2): PREFLIGHT · ACCEPTANCE (Tests vor Implementierung, Rot
erwartet — die Tests sind der Vertrag) · PLAN · PLAN-REVIEW
(verdict-plan.json, ≤ 2 Verhandlungsrunden) · BUILD · GATES · QA
(einmal je Meilenstein) · CODE-REVIEW (PASS/REWORK/ESCALATE) ·
REWORK (Budget, dann Leiter) · DONE (Tag, PROGRESS-Check).
→ prompts/ und orchestrate.sh (A2).

Verhandlung (§3): Einwand-IDs, Punkt-für-Punkt-Antworten, Präzedenz
Spec > Reviewer > Builder mit ADR-Pflicht, BACKLOG-Mechanik,
ESCALATION.md als einziger Human-Touchpoint. → A2 (SCHEMA.md).

Gates mit Zweck (§4): deps = keine erfundenen Versionen · lint/types
· tests inkl. Golden-Hashes · smoke = bootet ohne Fehler · graph =
Architektur als Regel statt Prosa · api = Schnittstellenänderung
wird sichtbarer Review-Diff · trace · bench = Budget · e2e ·
territory · assets = SHA256-Manifest, fehlende Daten sind nicht
„ersetzbar" · shots = der multimodale Reviewer SIEHT das Ergebnis ·
mutgate = Testqualität wird gemessen · Golden-Änderung nur mit ADR im
selben Meilenstein. Modelle lesen gates.json, schreiben es nie.
→ gates.d/ (A3.2), Beispiele im Template.

Anti-Halluzination (§7a): acht Mechanismen, generalisiert. → A3.8.

Sicherheitsschienen (§5): lineare Historie, Tags je Phase, kein
force-push, sauberer Baum; reference/** read-only; verbotene Flags;
Sandbox-/Permission-Modus je Rolle; PHASE_TIMEOUT, Rundenlimits,
MAX_MS_PER_RUN; STOP-Datei; vollständige Logs; PREFLIGHT verifiziert
CLI-Flags, `$PROMPT_FILE`-Quoting, Prompt-Archivierung. → A2, A3.3.

Kontexthygiene (§5b): frische Session je Phase, Resume verboten,
Gedächtnis-Taxonomie im Repo, Kontextmanifest je Prompt,
Diff-Reviews, isolierter Handoff, idempotente Wiederaufnahme (§6).
→ A3.7.

Betrieb (§6): STATUS-Board nach jeder Phase automatisch aktualisiert
und committet, Zustand in state/ je Meilenstein, summary.json.
→ A2 (status.sh), A3.1.

Autonomie (Patch v2): Transport-Retry alle Rollen,
Territoriums-Retry, Lock, Notify, Leiter (Rebuild/Arbiter/Park,
Exit 3), QA-Park, Findings-Klassen [INFRA]/[QA-PENDING], mutgate v2
mit Ratchet und Äquivalenz-Protokoll, LESSONS-Lesepfad,
CONFIG-Provenance-Zeile. → A2, A3.4, A3.5.

Toolchain (neu gegenüber Demiurg, aus der M3-.venv-Narbe abgeleitet):
deklarierte Laufzeiten und Versionen, eingefrorene Manifeste je
Ökosystem, Update-Pfad, Umgebungen außerhalb des Arbeitsbaums,
PREFLIGHT-Versionsprüfung. → A3.9, A4.

Lernen und Spur: LESSONS.md kuratiert mit Deckel (Befüllung
Betreiber/Analystenkanal), BACKLOG als offenes Befundbuch, ADRs als
Entscheidungsspur, PROGRESS.md als Langzeitgedächtnis. → A1, A2,
A3.7.

## A10 Praktischer Bauweg — Kickoff heute

1. Leeres Repo `harness-template` anlegen (GitHub, privat reicht).
   Diesen Plan als `docs/template/BAUPLAN.md` hineinlegen, die
   SYSTEM-UEBERSICHT als README-Grundlage.
2. Daneben ein read-only-Checkout von Demiurg (`../demiurg`) als
   Extraktionsquelle — gebaut wird ausdrücklich nicht im laufenden
   Demiurg-Harness, sondern in einer normalen Codex-/Claude-Code-
   Session im neuen Repo.
3. Kickoff-Prompt für diese Session:

```
Baue dieses Repo zum harness-template nach docs/template/BAUPLAN.md aus.
Quellen read-only: ../demiurg und dort docs/12-autonomer-bau.md.
Arbeitspakete und Reihenfolge: BAUPLAN A8 Schritt 2; das
Vollinventar A9 ist deine Prüfliste. Demiurg-Dateien kopieren und
entkoppeln, nie referenzieren. Jede Fertig-Meldung nur mit
ausgeführtem Kommando-Output (BAUPLAN A6, inkl. T-5-Nachweis-
tabelle). Ein Commit je Arbeitspaket mit sprechender Message.
Bei Spec-Lücken fragen, nichts erfinden.
```

4. Deine Reviews wie gewohnt; die Abnahme ist A6 samt Beleg-Regel,
   das Dummy-Projekt aus T-2 ist der erste echte Durchlauf der
   ganzen Maschine.
5. Danach schneiden: Demiurg-v3 und die Nachrüst-Kits aus dem
   fertigen Template (A8, Schritte 3–4). Der Leitstand v0 hängt an
   nichts davon und kann parallel entstehen.

## A11 Markt- und Forschungs-Backlog (erwogen, nicht bindend)

Aufgenommen 19.07.2026 nach Abgleich mit Spec-Kit-/Kiro-Mustern,
Cloud-Agenten (Devin, Codex, Jules, Claude Code) und
Verifier-Forschung. Reihenfolge = Empfehlung.

1. events.jsonl + Kostenspur: orchestrate.sh schreibt je Phase ein
   strukturiertes Ereignis (Phase, Runde, Dauer, Tokens, Kosten,
   Ergebnis). Leitstand-Trends ohne LLM-Parsing; dazu ein
   Budget-Gate in Euro je Meilenstein neben dem Rundenbudget.
   [klein, zuerst]
2. CI-Spiegel: verifier.sh zusätzlich in GitHub Actions je Push —
   zweiter, manipulationsferner Vollzug auf frischer Umgebung.
   Trennt Infra-error von echtem fail von selbst; der Leitstand
   kann den CI-Status mitlesen. [mittel]
3. BUILD_CANDIDATES=2 bei effort=max: zwei unabhängige Build-Würfe
   in git-worktrees, Gates + Reviewer wählen den besseren —
   Inference-Scaling statt vierter Rework-Runde. [mittel]
4. tasks.md im PLAN-Schema: der Plan zerfällt in nummerierte,
   einzeln abhakbare Tasks (Spec-Kit-Muster) — feinere Rework-Refs,
   messbarer PROGRESS, sauberere Wiederaufnahme. [klein]
5. devcontainer aus toolchain.json generieren: Container statt
   nackter Laptop — die .venv-Fehlerklasse strukturell beseitigt,
   identische Umgebung lokal und im CI-Spiegel. [mittel]
6. Worktree-Parallelität für deps-freie Meilensteine im selben
   Projekt (MAX_PARALLEL_MS) — erst nach 1–5 sinnvoll, sonst
   entsteht eine Beobachtbarkeitslücke. [später]

Bewusst nicht übernommen: selbstmodifizierende Schleifen und
automatisch befülltes LESSONS — kollidiert mit dem
Kuratierungs-Deckel und der Verfassung (Specs, Budget, STOP beim
Menschen).
