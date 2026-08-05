# INTAKE-CHECKLISTE — Pflichtinput der Projektierung

Der Betreiber liefert Entscheidungen und Quellen, keine ausformulierte Spec.
Alle acht Felder müssen gedeckt oder ausdrücklich offen sein. Fehlt etwas,
stellt die Projektierungs-KI ihre Fragen gesammelt und stoppt vor der
Dateigenerierung.

## 1. Vision in drei Sätzen

- Was wird gebaut?
- Für wen?
- Warum ist es nützlich oder notwendig?

Ziel: `docs/00-vision.md` und AGENTS-Projektblock.

## 2. Zielgruppe und Nutzungskontext

Wer nutzt das Ergebnis, auf welcher Plattform/in welchem Medium und in
welcher Situation? Ziel: Vision und Qualitätsmaßstäbe.

## 3. Out-of-Scope

Was ist das Projekt ausdrücklich nicht? Welche diskutierten Varianten sind
verworfen? Ziel: Scope-Grenze gegen Feature-Drift.

## 4. Stack oder Format

Festgelegt oder ausdrücklich offen mit benannten Optionen. Benötigte
Laufzeiten, Werkzeuge und Paketmanager samt verfügbaren Versionsvorgaben
nennen. Ziel: Preset, `toolchain.json`, M0 und Projektkommandos.

## 5. Qualitätsmaßstab je Kernfeature

Für jedes Kernfeature eine Zahl mit belegbarer Quelle, eine Grenze oder ein
eindeutiges Ja/Nein-Kriterium. „Gut“, „robust“ oder „schön“ reicht nicht.
Ziel: nummerierte Kriterien und Gate-Auswahl.

## 6. Datenquellen, Referenzen und Originale

Links genügen. Originalimplementierungen, Datenbestände, Stil-/Figurenbibeln
und Primärquellen benennen. Ziel: Orakelstrategie, Anker-Harvest und
Differentialtests.

## 7. Risiken und offene Fragen

Bekannte technische, fachliche, rechtliche und betriebliche Unsicherheiten.
Ziel: PLAN-Risiken, `BACKLOG.md` und `OFFENE-PUNKTE.md`.

## 8. Rollen und Budget

Builder-, Reviewer- und QA-Modell beziehungsweise Endpunkt; Rundenlimits,
Benachrichtigung und Aufwand `low|high|max` je Meilenstein. Ziel:
`config.env` und `milestones.json`.

## Anhang

Den ungekürzten Rohtext der Multi-KI-Besprechung beifügen. Die
Projektierung sortiert jeden Inhalt als entschieden, offen erwogen oder
verworfen; sie lässt nichts still fallen.

## Übergabeprüfung

- [ ] Alle acht Felder beantwortet oder ausdrücklich offen?
- [ ] Für jedes Kernfeature eine maschinell entscheidbare Qualitätskante?
- [ ] Quellen/Originale mit Links oder benanntem Ablageort vorhanden?
- [ ] Offene Optionen als offen markiert, nicht versehentlich entschieden?
- [ ] Rollen, Rundenbudget und Aufwand je Meilenstein benannt?
- [ ] Rohtext vollständig angehängt?
