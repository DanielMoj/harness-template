# ADR-001 — Projektinterne M0-Anker sind normativ

## Status

akzeptiert

## Kontext

Für M0 verlangt AGENTS.md empirische und normative Referenzwerte aus
`reference/anchors/*.json`. Die Acceptance-Phase konnte die externen Quellen
nicht nachverifizieren; `orchestrator/handoff/M0/PLAN-REVIEW.md` bestätigt unter
O-M0-1, dass die aus docs/01, docs/04, docs/07 und contracts/PROTOCOLS.md
wörtlich belegten Anker für M0 ausreichen.

## Entscheidung

Die vorhandenen M0-Anker sind für M0 normativ und werden vom Builder weder
ergänzt noch verändert. Laufzeitcode, Pipeline und Tests beziehen Erdradius,
Binärheadergröße, Float32-Wertbreite, nominale Länderzahl und FPS-Ziel aus
diesen Dateien. Externe Nachverifikation bleibt Reviewer-Arbeit und darf Werte
nur über ein weiteres ADR ändern.

## Konsequenzen

M0 bleibt vollständig auf die freigegebene Projektspezifikation rückführbar.
Die Entscheidung behauptet keine unabhängige naturwissenschaftliche
Nachverifikation und verhindert keine spätere, begründete Ankerkorrektur.
