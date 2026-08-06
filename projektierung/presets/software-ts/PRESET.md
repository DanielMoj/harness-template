# Preset software-ts

Typbaustein für ein einzelnes striktes TypeScript-Paket. Die Projektierung
übernimmt ihn nur, wenn Intake-Feld 4 diesen Stack festlegt; Versionen werden
nicht geschätzt.

## Layout

- `src/**`: Produktcode, Builder.
- `tools/**`: Build-, Analyse- und Pipelinewerkzeuge, Builder.
- `tests/unit/**`, `tests/properties/**`: Builder.
- `tests/acceptance/**`: Reviewer.
- `tests/e2e/**`, `tests/fuzz/**`: QA.
- `public/assets/**`: nur bei lokal gebündelten Laufzeitdaten und mit
  SHA256-Manifest.

## Werkzeuggrundsatz

- TypeScript strict, kein Lockern für grüne Builds.
- Vitest für Unit/Acceptance/Properties, Playwright für E2E,
  StrykerJS für geänderte Kernlogik.
- Exakte Node-/Paketmanager-Version und Lockfile stehen in
  `toolchain.json`; `deps` installiert frozen.

## Gate-Grundsatz

`deps`, `lint`, `tests`, `smoke`, `graph`, `api`, `trace`, `e2e`,
`territory`, `mutgate`; `bench` bei Performancekriterien, `shots` bei
sichtbarem Output, `assets` bei gebündelten Daten, `golden-adr` bei Golden-
Artefakten. Jedes Gate braucht ein tragendes Kriterium.

Die Architekturkonfiguration ist Reviewer-Territorium und wird über den
allgemeinen Hook freigegeben:

```sh
REVIEWER_EXTRA_PATHS_REGEX='^(\.dependency-cruiser\..*|dependency-cruiser\..*)$'
QA_EXTRA_PATHS_REGEX='^(tests/e2e/|tests/fuzz/)'
```

## M0

Manifest und Lockfile, strikte Compiler-/Lint-Konfiguration, leere
Produktstruktur, Test-/E2E-/Mutations-Runner, Architektur- und API-Snapshot-
Mechanik sowie alle ausgewählten Gates laufen erfolgreich ohne
projektspezifische Implementierung.
