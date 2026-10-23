# PROTOCOLS — dateibasiertes Rollenprotokoll

Besitz: Reviewer. Änderungen sind möglichst additiv und referenzieren einen
PLAN-Einwand oder ein ADR. Der Builder implementiert gegen diese Verträge;
bei einer Lücke fragt oder schlägt er vor, statt zu raten.

## 1. Phasenvertrag

Jeder Meilenstein läuft in frischen Sessions durch:

1. `10-acceptance`: Reviewer extrahiert Kriterien wörtlich und schreibt
   Abnahmetests vor der Implementierung. Rot ist erwartet.
2. `20-plan`: Builder schreibt PLAN bzw. PLAN-UPDATE.
3. `30-plan-review`: Reviewer schreibt PLAN-REVIEW und `verdict-plan.json`;
   höchstens `MAX_ROUNDS_PLAN` Verhandlungsrunden.
4. `40-build`: Builder implementiert Plan, Unit-/Property-Tests und
   `PROGRESS.md`.
5. `45-qa`: QA ergänzt einmal pro Meilenstein reproduzierbare E2E-/Fuzz-
   Befunde, wenn die Rolle aktiv und fällig ist.
6. `gates`: `verifier.sh` führt die ausgewählten Steckplätze aus und schreibt
   Fakten.
7. `50-code-review`: Reviewer entscheidet `PASS|REWORK|ESCALATE`.
8. `60-rework`: Builder behebt referenzierte Befunde. Ab
   `REBUILD_ROUND` ersetzt `62-rebuild` einmalig den Flickpfad.
9. `70-arbiter`: Eine frische Reviewer-Session löst festgefahrene Punkte
   nach Spec > Reviewer > Builder. Nur `HUMAN` erreicht den Betreiber.
10. `done`: unveränderlicher Tag `done/<MS>` und PROGRESS-Prüfung.

Abgeschlossene Marker unter `orchestrator/state/<MS>/*.done` machen die
Wiederaufnahme idempotent. `plan/<MS>` ist der unveränderliche Basis-Tag für
Diffs und Rebuild.

## 2. Meilensteinmanifest

`orchestrator/milestones.json` ist ein JSON-Array:

```json
[{"id":"M0","title":"Gerüst","criteriaRef":["K-M0-1"],"deps":[],"effort":"low"}]
```

- `id` ist eindeutig und dateisystemtauglich.
- `criteriaRef` enthält die bindenden Kriterien-IDs aus `docs/**`.
- `deps` enthält ausschließlich bekannte IDs. Fehlt das Feld, gilt aus
  Kompatibilitätsgründen strikt der direkte Vorgänger.
- `effort` ist `low`, `high` oder `max`.

## 3. Verdicts und Verhandlung

Verdicts folgen `orchestrator/handoff/SCHEMA.md`. `PASS` ist nur mit leerem
`blocking` zulässig. Ein Verdict gilt nur für die Runde, in der es geschrieben
wurde; ein fehlendes oder älteres Verdict ist FATAL. Jeder blocking-Eintrag hat eine nichtleere `ref`.
Einwände besitzen stabile IDs und werden in PLAN-UPDATE Punkt für Punkt
beantwortet.

Präzedenz: Ein deckendes wörtliches Spec-Zitat schlägt den Einwand. Schweigt
die Spec, bindet nach Rundenende der Reviewer und dokumentiert die Auslegung
als ADR. Widersprechen sich Spec-Stellen, lautet das Verdict `ESCALATE`.
Nonblocking-Befunde wandern nach `BACKLOG.md`.

## 4. Gate-Steckplatz

Aktive Gates sind ausführbare Dateien `orchestrator/gates.d/NN-name.sh`.
Der Runner setzt `REPO_ROOT`, `MILESTONE`, `ROUND` und `BASE_SHA`.

- Exit 0: `pass`
- Exit 1: `fail` — fachlicher/produktbezogener Befund
- Exit 2: `error` — Infrastruktur; kein Builder-Fehlschlag
- Letzte nichtleere stdout-Zeile: Kurzbefund

Der Runner schreibt je Gate `state/<MS>/gate-<name>.log` und aggregiert
`gates.json` mit Milestone, Basis-SHA, Toolversionen, Status, Kurzbefunden
und Gesamtergebnis. Modelle lesen, aber schreiben diese Dateien nie.

## 5. Statusvertrag v1

`orchestrator/status.sh` schreibt `STATUS.md` und
`orchestrator/state/summary.json`. Das Maschinenformat enthält mindestens:

```json
{
  "contract": 1,
  "project": "slug",
  "ts": "2026-07-19T09:08:41+02:00",
  "milestone": {"id":"M0","index":1,"total":2},
  "phase": "50-code-review",
  "round": 1,
  "needs_human": false,
  "reason": "",
  "gates": {"tests":"pass"},
  "parked": [],
  "last_events": [],
  "exit": null
}
```

`ts` ist zugleich Heartbeat. Exit 0 bedeutet fertig, 2 FATAL und 3 fertig
mit mindestens einem geparkten Meilenstein.

## 6. Logs und Provenienz

Jeder Modellversuch erzeugt eindeutig
`<MS>-<phase>-r<runde>-a<versuch>-<zeitstempel>.log`; je Phase entsteht
zusätzlich ein Promptarchiv. `orchestrate.log` ist die Metaspur. Prompts werden über die
Umgebungsvariable `PROMPT_FILE` übergeben; Resume-Flags sind verboten.
`gates.json` trägt Basis-SHA, aktuellen SHA und Toolversionen.

## 7. Anker

Jede Datei `reference/anchors/*.json` enthält eine stabile ID, Wert, Einheit,
Toleranz, `source_url` und ein wörtliches Beleg-Zitat. Builder dürfen Anker
nur lesen. Wertänderungen benötigen Reviewer-Commit und ADR. Maschinell
geschriebene Mutation-Baselines unter `orchestrator/state/mut-baseline` sind
der dokumentierte Sonderfall.

## 8. Toolchain

`toolchain.json` versioniert Laufzeiten, Prüfkommandos, Installationswege und
eingefrorene Paketmanifeste. PREFLIGHT prüft die real installierten Versionen
und CLI-Flags. Umgebungen werden nicht im Repo angelegt.
