# Preset text

Typbaustein für Buch-, Dokumentations- und andere Manuskriptprojekte.
Format, Renderwerkzeug und Zitationsstil kommen aus dem Intake.

## Layout

- `kapitel/**`: Manuskriptteile, Builder.
- `stilbibel.md`, `figurenbibel.md`, `weltbibel.md`: normative Anker,
  Reviewer-Besitz.
- `quellen/**`: belegte Quellen-/Zitationsdaten.
- `tests/acceptance/**`: strukturelle Abnahmezeugen, Reviewer.
- `tests/e2e/**`: vollständige Render-/Leseflüsse, QA.

Der AGENTS-Projektblock gibt `kapitel/**` als zusätzliches
Builder-Territorium frei und setzt denselben Pfad in
`BUILDER_EXTRA_PATHS_REGEX`/`REBUILD_PATHS`.

Fertige Konfigurationszeilen:

```sh
BUILDER_EXTRA_PATHS_REGEX='^kapitel/'
REVIEWER_EXTRA_PATHS_REGEX='^(stilbibel\.md|figurenbibel\.md|weltbibel\.md|quellen/)'
QA_EXTRA_PATHS_REGEX='^(tests/e2e/|tests/fuzz/)'
REBUILD_PATHS='kapitel tools tests/unit tests/properties'
```

## Build

„Build“ bedeutet deterministischer Manuskript-Render in das Zielmedium plus
Wortzahl-/Strukturbericht. Renderer, Wörterzählung und Paketversionen stehen
in `toolchain.json`; Ausgabeformat und Zitationsstil sind Spec.

## Gates

- `laengenkorridor`: Wortzahl je Kapitel gegen belegte Ankerbänder.
- `stil-lint`: deterministische Verbots-/Stilregeln.
- `kontinuitaet`: LLM-Judge gegen Stil-, Figuren- und Weltbibel mit
  JSON-PASS/FAIL.
- `zitate`: verlangte Quellenbelege vollständig und auflösbar.
- optional `struktur`, `repro`, `golden-adr`.

QA arbeitet als Konsistenz- und Gegenbeispiellauf, nicht als
Geschmacks-Verdict. Jeder Befund nennt Stelle, Bibelregel und reproduzierbare
Probe.

## M0

Leere Kapitelstruktur, Bibelvorlagen, deterministischer Render, Wortbericht
und alle gewählten Gates laufen über eine klar als Fixture markierte
Mini-Seite.
