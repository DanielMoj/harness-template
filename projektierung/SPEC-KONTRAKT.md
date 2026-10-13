# SPEC-KONTRAKT — Auftragsschema für Harness-Projekte

Dieser Vertrag legt fest, welche Dateien die Projektierung erzeugt und wie
aus Besprechungswissen maschinell abnehmbare Kriterien werden. Freigegebene
Specs binden Builder, Reviewer und QA. Lücken werden vor der Generierung
gefragt, niemals plausibel ergänzt.

## 1. Dokumentensatz

Pflicht:

- `docs/00-vision.md`: Vision in drei Sätzen, Zielgruppe,
  Nutzungskontext, Scope und ausdrückliches Out-of-Scope.
- `docs/01-fachspezifikation.md` beziehungsweise nummerierte
  Fachspezifikationen je Domäne: nur entschiedener, bindender Inhalt und die
  Kriterien.
- `orchestrator/milestones.json`: maschinenlesbare Roadmap mit M0 und allen
  weiteren lieferbaren Schnitten.
- `AGENTS.md`-Projektblock: Vision-Verweis, Spezifika, zusätzliche
  Territoriumsregeln und Domäneninvarianten.

Wenn Material vorliegt:

- `docs/90-katalog-offen.md`: erwogene, aber nicht entschiedene Varianten;
  ausdrücklich nicht bindend.
- `BACKLOG.md`: bekannte Risiken und vertagte operative Befunde.
- `ANKER-TODO.md`: zu erhebende Referenzwerte mit vermuteter Quelle; keine
  ungeprüften Werte.

Verworfene Varianten stehen im Out-of-Scope-Kapitel und verschwinden nicht
still. Die freigegebenen Kriterien in den Fachspezifikationen plus
`milestones.json` sind gemeinsam die Roadmap; ein zusätzliches menschliches
Roadmap-Dokument darf sie nur spiegeln, nie umdeuten.

## 2. Kriterienformat

Eine Kriteriums-ID ist stabil und eindeutig:

`K-M<x>-<n>: <einzeln prüfbare Aussage> (Prüfweg: Test | Gate | Judge)`

Jedes Kriterium nennt:

1. das beobachtbare Artefakt oder Verhalten,
2. bei Dateien den Zielpfad,
3. die eindeutige Ja/Nein-Bedingung,
4. den Prüfweg und die geplante Test-/Gate-Zuordnung,
5. bei Zahlen ausschließlich `ankerRef: ANK-<nn>` statt eines nackten
   empirischen Werts.

Verboten sind Sammelkriterien und Wörter ohne Entscheidungskante wie
„funktioniert gut“, „intuitiv“, „robust“ oder „schnell“. Ein Kriterium darf
höchstens einen logisch gekoppelten Verhaltenstatbestand prüfen; sonst wird
es geteilt.

Beispiel:

```text
K-M1-2: Das Artefakt reports/schema.json wird in zwei unabhängigen Läufen
byte-identisch erzeugt (Prüfweg: repro-Gate).
```

Bei Zahlen:

```text
K-M2-3: Der Export bleibt unter dem in ankerRef: ANK-07 belegten Deckel
(Prüfweg: bench-Gate).
```

## 3. Beidseitige Traceability

- Jeder Eintrag `criteriaRef` in `milestones.json` existiert wörtlich in
  einer freigegebenen Spec.
- Der Reviewer kopiert ID, exakten Spec-Substring und Quelldatei in
  `orchestrator/handoff/<MS>/CRITERIA.json`.
- Jeder Kriteriumseintrag wird von mindestens einem Abnahmetest, Gate oder
  eindeutigem Judge referenziert.
- Jeder Abnahmetest nennt mindestens eine existierende Kriteriums-ID.
- Jedes ausgewählte Gate trägt mindestens ein Kriterium. Gate- und
  Kriterienwaisen sind unzulässig.

Das trace-Gate prüft diese Zuordnung maschinell.

## 4. Meilensteine

M0 lautet immer: „Gerüst steht, Toolchain ist installiert, alle gewählten
Gates laufen leer durch.“ Danach enthält jeder Meilenstein ein in einem Satz
sagbares, lieferbares Ergebnis und drei bis sieben Kriterien.

Schema:

```json
[
  {
    "id": "M0",
    "title": "Gerüst und leere Gates",
    "criteriaRef": ["K-M0-1", "K-M0-2", "K-M0-3"],
    "deps": [],
    "effort": "low"
  }
]
```

`deps` enthält nur zwingende fachliche Abhängigkeiten. Fehlt es in einem
historischen Manifest, gilt strikt der Vorgänger. Neue Projektierungen
schreiben es immer explizit. `effort` ist `low|high|max` und kommt aus dem
Intake-Budget, nicht aus einer Schätzung der Projektierungs-KI.

## 5. Anker und Belege

Empirische Werte werden nicht von der Projektierung erfunden. Sie erzeugt
einen `ankerRef` und einen ANKER-TODO-Eintrag. Der Reviewer erhebt später den
Anker unter `reference/anchors/` mit Wert, Einheit, Toleranz, `source_url`,
wörtlichem Kurz-Zitat und Abrufdatum. Nicht verifizierbare Quellen bleiben
blocking offen.

„Erfüllt“ setzt ausgeführten Kommando-Output voraus. Der Prüfweg wird schon
im Kriterium festgelegt; das tatsächliche Ergebnis steht später in
`gates.json`, Handoff oder `PROGRESS.md`.

## 6. Vertragsänderungen und ADRs

Nach Betreiberfreigabe ändert keine Modellrolle den Spec-Text; der
Orchestrator verwirft solche Änderungen. Schweigt die Spec, halten Reviewer
oder Arbiter die bindende Auslegung in einem ADR unter
`docs/decisions/ADR-nnn-*.md` fest, das Kontext, Entscheidung und Folgen für
Kriterien, Tests, Gates, Migration und Golden-Artefakte nennt. Ein ADR darf
keine widersprüchliche Spec heimlich überschreiben; ein echter Widerspruch
wird eskaliert.
