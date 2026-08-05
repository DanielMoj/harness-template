# Preset daten

Typbaustein für Datenpipelines, Analysen und reproduzierbare Exporte.
Sprache, Laufzeit und Speicherformat kommen aus dem Intake.

## Layout

- `src/**` oder `pipeline/**`: Pipelinecode, Builder; der konkrete Pfad wird
  im AGENTS-Projektblock und `BUILDER_EXTRA_PATHS_REGEX` festgelegt.
- `tools/**`: Import-, Validierungs- und Reproduktionswerkzeuge.
- `schemas/**`: normative Schemata, Reviewer-Vertrag.
- `tests/unit/**`: Builder; `tests/acceptance/**`: Reviewer;
  `tests/fuzz/**`: QA.
- `reference/anchors/**`: Goldwerte, Toleranzen und belegte Quellwerte.

Rohdaten werden nicht ins Repo kopiert, sofern Lizenz/Größe das verbieten.
Stattdessen stehen Quelle, Pin/Hash und reproduzierbarer Beschaffungsweg in
Manifesten. Fehlende Daten brechen benannt ab.

## Gates

- `schema`: Eingaben, Zwischenstände und Exporte validieren.
- `repro`: zwei unabhängige Läufe erzeugen denselben Hash.
- `golden`: Referenz-Outputs innerhalb belegter Toleranzen.
- `deps`: eingefrorene Laufzeiten und Pakete.
- `trace`: Kriterien, Tests und Outputs beidseitig verknüpft.
- optional `research`, `bench`, `assets`, `golden-adr`.

## M0

Toolchain, leere Pipeline mit winziger gekennzeichneter Fixture, Schema-
Validator, deterministischer Hashvergleich und alle gewählten Gates laufen
grün. Produktionsdaten werden in M0 nicht synthetisch ersetzt.
