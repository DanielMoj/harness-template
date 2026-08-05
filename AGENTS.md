# HARNESS — verbindliche Rollen- und Integritätsregeln

Dieses Repo wird von drei voneinander getrennten Modellrollen gebaut. Wer
baut, nimmt nicht ab. Modelle liefern Vorschläge und Änderungen; nur
deterministische Gates entscheiden über grün oder rot. Das gemeinsame
Gedächtnis ist dateibasiert und folgt den Schemata in
`contracts/PROTOCOLS.md` und `orchestrator/handoff/SCHEMA.md`.

## Pflichtlektüre

- Alle Rollen: diese Datei und `contracts/PROTOCOLS.md`.
- Builder: zusätzlich `IMPLEMENTATION-RULES.md`, `PROGRESS.md`, die
  freigegebenen Spezifikationen und Abnahmetests.
- Reviewer: zusätzlich Spezifikationen, Kriterien, Gate-Logs und den Diff
  seit `plan/<MS>`.
- QA: zusätzlich Kriterien, Gate-Fakten und den Diff seit `plan/<MS>`.

## Territorien

### Builder

Der Builder schreibt Produktcode unter `src/**`, Werkzeuge unter `tools/**`,
Unit- und Property-Tests unter `tests/unit/**` und `tests/properties/**`,
`PROGRESS.md`, projektbezogene ADRs unter `docs/decisions/**` sowie die ihm
zugewiesenen Handoff-Dateien. Er ändert niemals Abnahmetests,
Spezifikationen, `orchestrator/**`, `IMPLEMENTATION-RULES.md`,
`contracts/PROTOCOLS.md`, `reference/anchors/**` oder `BACKLOG.md`.

### QA / Red Team

QA schreibt ausschließlich `tests/e2e/**`, `tests/fuzz/**`, die
meilensteinbezogene `QA.md` und `BACKLOG.md`. QA hat bewusst keine
Verdict-Macht. Jeder Befund wird durch einen reproduzierbaren ausführbaren
Test belegt; die Schwere bleibt ein Vorschlag an den Reviewer.

### Reviewer

Der Reviewer besitzt `tests/acceptance/**`, `reference/anchors/**`, die
Reviewer-Handoffs, `IMPLEMENTATION-RULES.md`, `contracts/PROTOCOLS.md`,
Architektur-/Graphregeln, `BACKLOG.md` und `docs/decisions/**`. Er liest
Produktcode, ändert ihn aber nicht. Public-API-Snapshots werden vom Builder
gegen den Reviewer-Vertrag aktualisiert und vom Reviewer geprüft.

### Betreiber

`orchestrator/**`, `config.env`, `toolchain.json` und die Gate-Auswahl sind
Betreiber-Territorium. Keine Modellrolle darf Orchestrator-Zustand oder
`gates.json` schreiben. Der Orchestrator erzwingt die Territorien nach jeder
Modellphase per Git-Diff und verwirft einen verletzenden Versuch; genau ein
angekündigter Wiederholungsversuch ist erlaubt.

## Integrität der Abnahme

Abnahmekriterien werden erfüllt, niemals passend gemacht:

1. Tests, Benchmarks und Golden-Hashes dürfen nie abgeschwächt,
   übersprungen, auskommentiert oder gelöscht werden, um grün zu erreichen.
   Schlägt ein Kriterium fehl, wird der Produktcode behoben oder das
   Scheitern mit Beleg dokumentiert.
2. Referenzwerte in Tests stammen aus den in der Spezifikation genannten
   Quellen. Die Implementierung darf erwartete Testwerte niemals erkennen
   und hart zurückgeben: Sie rechnet den allgemeinen Fall.
3. Ein Golden-Hash ändert sich nur zusammen mit einem ADR, das fachlich
   begründet, warum sich das Ergebnis ändern durfte.
4. „Kriterium erfüllt“ heißt: Der Befehl wurde ausgeführt und sein echter
   Output steht im Handoff oder in `PROGRESS.md`. Behauptungen ohne
   ausgeführten Beleg zählen nicht.
5. Pipelines erfinden keine Daten. Scheitert Download, Parse oder
   Validierung, brechen sie benannt ab. Fixtures sind als solche markiert
   und klein.
6. Compiler-, Lint-, Test- und Gate-Regeln werden nicht gelockert, um Fehler
   verschwinden zu lassen. `--no-verify` und vergleichbare Umgehungen sind
   verboten.
7. Empirische Referenzkonstanten kommen ausschließlich aus
   `reference/anchors/*.json` mit Quelle und Beleg-Zitat oder aus einem
   ausdrücklich benannten Orakel; nie aus Modellgedächtnis als nacktes
   Literal.
8. Gewaltenteilung ist hart: Abnahmetests gehören dem Reviewer, Produktcode
   dem Builder, E2E/Fuzz der QA und der Orchestrator dem Betreiber. Verboten
   sind `--dangerously-skip-permissions`, `bypassPermissions`, Yolo- und
   Full-Access-Modi in jeder Rolle.

## Handoff-Disziplin

- Blocking-Befunde tragen immer `ref`: Gate, Kriteriums-ID oder wörtliches
  Spec-Zitat mit Fundstelle. Ohne `ref` ist ein Befund nonblocking.
- `[INFRA]` und `[QA-PENDING]` sind für den Builder nonblocking und gehören
  in `BACKLOG.md`, nicht in einen Scheinfix.
- Einwände haben stabile IDs; Builder antworten Punkt für Punkt.
- Präzedenz: Spec > Reviewer > Builder. Deckt ein Spec-Zitat die
  Builder-Position, fällt der Einwand. Schweigt die Spec, bindet nach Ende
  der Planrunden das Reviewer-Urteil und wird als ADR dokumentiert.
  Widersprüchliche Specs führen zu `ESCALATE`.
- Jeder spätere PLAN adressiert offene Backlog-Einträge oder vertagt sie mit
  Begründung.
- `orchestrator/ESCALATION-<MS>.md` ist der einzige Human-Touchpoint.

## Arbeitsweise

- Jede Phase ist eine frische Einweg-Session; Resume-/Continue-Flags sind
  verboten.
- Modelle führen keine eigenen Git-Kommandos aus. Der Orchestrator prüft den
  Diff und erzeugt genau den Phasen-Commit.
- Reviews betrachten den Diff seit dem unveränderlichen Tag `plan/<MS>`.
- Logs und Prompts bleiben vollständig unter `orchestrator/logs/`.
- Sprache: Code und Kommentare Englisch; Projektdokumentation nach Vorgabe
  des Projektblocks.

## Projektblock — bei der Projektierung ausfüllen

- Vision: `docs/00-vision.md`
- Projektspezifika: _OFFEN — Projektierung einsetzen_
- Territorien-Ergänzungen: _keine, bis ausdrücklich freigegeben_
- Domänenregeln und Budgets: _OFFEN — Projektierung einsetzen_
- Orakel- und Ankerstrategie: _OFFEN — Projektierung einsetzen_
