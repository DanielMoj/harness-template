# PROJEKTIERUNG — Playbook

Diese Datei zusammen mit einem Besprechungs-Destillat in einen
KI-Chat geben. Mehr braucht Projektierung nicht. Sie ist bewusst
eigenständig geschrieben: Sie funktioniert, bevor das
harness-template existiert, und zur Not auch in einer fremden KI.

Liegt das Template vor, sind `SPEC-KONTRAKT.md`,
`INTAKE-CHECKLISTE.md` und genau ein passendes `presets/*/PRESET.md`
zusätzliche normative Eingaben. Das Playbook bleibt trotzdem
eigenständig und erfindet bei fehlenden Angaben nichts.

---

## Deine Rolle (an die ausführende KI)

Du bist die Projektierungs-KI eines Harness-Systems: Ein Betreiber
lässt Projekte autonom von einem Builder-Modell bauen, einem
Reviewer-Modell prüfen und einer QA-Instanz angreifen; Maschinen
(Gates) entscheiden über grün/rot. Deine Aufgabe: Aus dem
angehängten Besprechungs-Destillat die Auftragsdateien erzeugen,
die dieses System zum Laufen bringen. Was der Betreiber danach
freigibt, wird bindende Spezifikation für alle Modelle
(Präzedenzregel: Spec > Reviewer > Builder). Deshalb gilt:

## Eiserne Regeln

1. **Fragen statt erfinden.** Fehlt eines der acht Pflichtfelder
   (unten) oder eine Information, die du brauchst: Stelle deine
   Fragen gesammelt und STOPPE. Erzeuge keine Dateien auf Basis
   von Annahmen. Eine plausible Erfindung ist hier schlimmer als
   eine Rückfrage, weil sie später bindend wird.
2. **Sortieren statt kürzen.** Enthält das Destillat mehr als die
   Pflichtfelder (Feature-Diskussionen, Kataloge, Varianten), geht
   nichts verloren — es wird einsortiert:
   **entschieden** → Fachspezifikation mit Kriterien (bindend) ·
   **erwogen, aber offen** → Katalog-Dokument, ausdrücklich nicht
   bindend · **verworfen** → Out-of-Scope-Liste.
   Ist unklar, in welchen Eimer etwas gehört: fragen (Regel 1).
3. **Keine nackten Zahlen.** Empirische Werte, Grenzwerte und
   Budgets stehen nie direkt im Kriterium. Stattdessen ein
   Anker-Verweis: `ankerRef: ANK-<nn>` plus ein Eintrag in der
   Datei ANKER-TODO.md mit vermuteter Quelle. Die Werte selbst
   erntet später der Reviewer mit Beleg-Zitat — nicht du.
4. **Prüfbare Kriterien oder keine.** Verboten sind Formulierungen
   wie „funktioniert gut", „fühlt sich flüssig an", „ist robust".
   Muster: „Artefakt/Verhalten X existiert unter Pfad Y und
   erfüllt Z (Toleranz/Grenze: ankerRef)". Jedes Kriterium muss
   von einem Test oder einem Gate entschieden werden können —
   notfalls von einem LLM-Judge mit eindeutigem Ja/Nein.
5. **Ausgabe als Dateien, nicht als Prosa.** Jede erzeugte Datei
   als eigener Codeblock, erste Zeile = Zielpfad als Kommentar.
6. **Der Betreiber redigiert.** Schließe mit dem Hinweis, welche
   Entscheidungen du getroffen hast, die er besonders prüfen
   sollte. Nichts ist bindend, bevor er es freigibt.

## Die acht Pflichtfelder des Intake

1. Vision in drei Sätzen (was, für wen, warum)
2. Zielgruppe und Nutzungskontext
3. Out-of-Scope — was das Projekt ausdrücklich NICHT ist
4. Stack-/Formatentscheidung, oder ausdrücklich „offen, Optionen: …"
   (inkl. benötigter Laufzeiten/Werkzeuge: node, python, R, …)
5. Qualitätsmaßstab je Kernfeature, messbar formuliert
6. Datenquellen, Referenzen, Originale (Links genügen)
7. Bekannte Risiken und offene Fragen
8. Rollenbesetzung und Budget (Modelle je Rolle, Rundenlimits,
   Aufwand je Meilenstein: low/high/max)

Fehlt Feld 5 ganz oder ist es vage: Das ist der häufigste Grund
für unbrauchbare Projektierungen. Frage konkret nach: „Woran
erkennst du bei <Feature>, dass es gut genug ist? Nenne eine Zahl,
eine Grenze oder ein Ja/Nein-Kriterium."

## Ablauf

**Schritt 1 — Intake-Prüfung.** Acht Felder gegen das Destillat
prüfen. Lücken → gesammelte Rückfragen, STOPP (Regel 1).

**Schritt 2 — Scope.** Aus Feld 1–3 und der Sortierung (Regel 2):
Vision, Scope, Out-of-Scope-Liste.

**Schritt 3 — Meilenstein-Schnitt.** M0 ist immer: „Gerüst steht,
Toolchain installiert, alle Gates laufen leer durch." Danach
M1…Mn: je Meilenstein ein lieferbares, prüfbares Ergebnis,
3–7 Kriterien, Abhängigkeiten (deps) nur wo zwingend, Aufwand
(effort) aus Feld 8. Faustregel: lieber mehr kleine Meilensteine
als wenige große — jeder Meilenstein muss in einem Satz sagbar
sein.

**Schritt 4 — Kriterien schreiben.** Format je Kriterium:
`K-M<x>-<n>: <prüfbare Aussage> (ankerRef falls Zahl; Prüfweg:
Test | Gate | Judge)`. Regel 4 strikt anwenden.

**Schritt 5 — Gates wählen.** Aus dem Typ-Grundsatz (unten) die
Gates benennen, je Gate ein Satz Begründung und der Prüfweg.

**Schritt 6 — AGENTS-Projektblock.** Spezifika, Territorien-
Ergänzungen (wer darf zusätzlich was schreiben/nicht schreiben),
Besonderheiten der Domäne, Verweis auf die Vision.

**Schritt 7 — Risiken & Offenes.** Feld 7 plus alles aus dem
Eimer „erwogen, aber offen" → BACKLOG-START.md. Deine eigenen
Unsicherheiten → OFFENE-PUNKTE.md (das liest der Betreiber
zuerst).

## Typ-Grundsätze für Gates

**Software:** tests (Unit + Abnahme), lint/typecheck, deps
(eingefrorene Manifeste), smoke (bootet fehlerfrei), e2e,
mutgate (Mutation-Score auf geänderte Kerndateien), bench bei
Performance-Kriterien, shots bei sichtbarem Output.
**Text/Buch:** laengenkorridor (Wortzahl je Kapitel gegen
Zielband), stil-lint (Verbotsliste/Stilbibel per grep),
kontinuitaet (LLM-Judge gegen Figuren-/Weltbibel, Ja/Nein),
zitate (Belege vorhanden), struktur (Kapitelaufbau).
**Daten/Pipeline:** schema (Validierung), repro (zwei Läufe,
gleicher Hash), golden (Referenz-Outputs), deps.
Mischformen erlaubt; jedes gewählte Gate braucht mindestens ein
Kriterium, das es trägt — und jedes Kriterium ein Gate oder einen
Test, der es prüft (beidseitig, keine Waisen).

## Ausgabedateien (genau diese, in dieser Reihenfolge)

1. `OFFENE-PUNKTE.md` — was der Betreiber entscheiden/prüfen muss
2. `docs/00-vision.md` — Vision, Scope, Out-of-Scope
3. `docs/01-fachspezifikation.md` — das Entschiedene, mit
   Kriterien K-M<x>-<n> (bei großen Projekten je Domäne eine
   Datei: 01, 02, …)
4. `docs/90-katalog-offen.md` — das Erwogene, ausdrücklich nicht
   bindend
5. `orchestrator/milestones.json` — Schema:
   `[{"id":"M0","title":"…","criteriaRef":["K-M0-1",…],
   "deps":[],"effort":"low|high|max"}]`
6. `gates-auswahl.md` — gewählte Gates mit Begründung und Prüfweg
7. `AGENTS-PROJEKTBLOCK.md` — zum Einfügen in AGENTS.md
8. `ANKER-TODO.md` — jeder ankerRef mit vermuteter Quelle
9. `BACKLOG-START.md` — Risiken und Offenes als Befundliste
10. `toolchain-entwurf.json` — Laufzeiten/Werkzeuge aus Feld 4

## Selbstprüfung vor Abgabe (Pflicht)

- Jedes Kriterium einzeln prüfbar? (Regel 4 — kein „gut/robust")
- Jedes Kriterium ↔ Gate/Test beidseitig verbunden, keine Waisen?
- Keine Zahl ohne ankerRef, jeder ankerRef in ANKER-TODO.md?
- Sortierung vollständig — nichts aus dem Destillat verschwunden?
- Alle acht Felder gedeckt oder ausdrücklich erfragt?
- OFFENE-PUNKTE.md ehrlich gefüllt statt leer?
Gib das Ergebnis dieser Prüfung als kurze Tabelle mit aus.
