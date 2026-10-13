# Beispiel — kopierte Demiurg-Beweiskette

Dieses Verzeichnis ist eine lokale, read-only Messlatte für die
Projektierungs-KI. Die Dateien wurden aus einem realen Harness-Snapshot
von Demiurg kopiert, einem eigenen Computerspiel-Projekt des Autors (daher
Meilensteinnamen wie „Waffe 1: Meteorit“), und haben keinerlei Laufzeit- oder
Pfadabhängigkeit zu ihrer Quelle.

Enthalten sind:

- das echte historische Meilensteinmanifest,
- M0-Kriterien und sämtliche M0-Abnahmetests,
- das abschließende M0-Review samt Verdict und Gate-Fakten,
- ein ADR und ein belegter Referenzanker.

Das Beispiel zeigt Detailtiefe und Belegkette, nicht das aktuelle
Template-Schema. Historische Manifeste dürfen etwa `deps` auslassen
(Vorgänger-Fallback); neue Projektierungen müssen
`{id,title,criteriaRef,deps,effort}` aus `SPEC-KONTRAKT.md` schreiben.
Auch `M0/anchor.json` ist ein unveränderter historischer Beleg: Es verwendet
`harvested`, einen Repo-Pfad als `source_url` und kein `tolerance`. Neue Anker
müssen stattdessen den aktuellen Vertrag aus `reference/anchors/README.md`
mit `retrieved`, echter Quellen-URL und Toleranz erfüllen.

Kette:

`milestones.json` → `M0/CRITERIA.json` → `M0/tests/acceptance/**` →
`M0/REVIEW.md` + `M0/verdict-code.json` → `M0/gates.json` →
`M0/ADR-001-*.md` + `M0/anchor.json`.
