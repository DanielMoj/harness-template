# REVIEW M0 — Code-Review, Runde 2 (nach Builder-Rework r2, Commit 47525e9)

Geprüft: `orchestrator/state/M0/gates.json` + alle `gate-*.log` (Verifier-Lauf
auf env.sha `47525e9` = HEAD — Provenance-Lücke E27 damit geschlossen), beide
Screenshots `orchestrator/state/M0/shots/*.png` (Bilddateien angesehen),
`orchestrator/handoff/M0/QA.md` (Schritt 1b, Q4-Adjudikation nachgeholt),
Diff seit `plan/M0` mit Fokus auf das Delta seit der letzten Review
(`47525e9`: nur PROGRESS.md, STATUS.md, REWORK-NOTES.md und die zwei
Baseline-PNGs), REWORK-NOTES.md, PLAN.md/PLAN-REVIEW.md (keine
PLAN-UPDATE.md), CRITERIA.json, docs/07 §M0, docs/01, docs/03, docs/04,
docs/12, AGENTS.md, IMPLEMENTATION-RULES.md, contracts/PROTOCOLS.md,
Public-API-Diff (contracts/api: 4 Erst-Snapshots seit plan/M0, api-Gate
„4 public snapshots match" auf HEAD; seit r1 unverändert).

Einwand-Nummerierung fortlaufend: letzte vergebene ID war E30; diese Runde
vergibt KEINE neuen IDs.

## Faktenlage Gates (nicht verhandelbar)

`gates.json`: **result=pass**, env.sha `47525e90` == HEAD. Grün: shots, deps,
trace, smoke, mutgate (vakuum-grün, M0-Scope ohne mutierbare src-Dateien —
bekannt, E14), api, graph, tests, lint, assets. Skipped und legitim:
bench (Pflicht ab M1, `BENCH_REQUIRED_FROM`), e2e (Pflicht ab
`E2E_REQUIRED_FROM=M3`; die QA-E2E-Specs laufen dennoch real im tests-Gate
mit, s. u.), golden_adr (kein Golden in M0).

`gate-tests.log`: **68/68 Tests grün** in 13 Dateien — die 48 Bestandstests
plus die 15 QA-Fuzztests plus die 5 QA-E2E-Fälle (echter Preview-Server:4174
+ headless Chromium, Boot-Determinismus, Picking-Flow, Null-Pick,
Idempotenz). Der in r1 einzige rote Test „first snapshots are committed
under tools/shots/baseline/" ist grün.

## E24 — geschlossen (Erst-Baselines committet, Determinismus belegt)

`git ls-files` führt beide PNGs unter `tools/shots/baseline/`. Der Builder
hat den in r1 freigegebenen Fallback (b) genommen: byteidentische Übernahme
der echten `capture.mjs`-Artefakte aus dem Gate-Lauf `cf57621`, Provenienz
in PROGRESS.md dokumentiert (cmp + SHA256, Diff `cf57621..41002bb -- src
tools public/assets` leer). Stärkster Beleg: Der frische Verifier-Lauf auf
HEAD hat die Shots NEU erzeugt, und beide sind **byteidentisch** zu den
committeten Baselines (SHA256 `16acef9d…` / `02f727d9…` beidseitig
verifiziert) — der in r1 geforderte Deckungsgleichheits-Check ist damit
bestanden; das Capture ist über zwei unabhängige Läufe deterministisch.
A-M0-18/A-M0-19 bzw. CRITERIA O-M0-4 (e) sind erfüllt.

## E27 — geschlossen (Gate-Evidenz gilt für HEAD)

`gates.json` trägt den HEAD-SHA; alle vier QA-Specs wurden typgeprüft
(lint-Gate inkl. `tsc --noEmit` über `include: ["src","tests"]`) und
ausgeführt (tests-Gate). Beide Q4-Kandidaten aus QA.md sind damit
adjudiziert — **beide grün**:
- „unambiguous interior point of every checkable country" (exhaustives
  Picking gegen die Ray-Cast-Oracle): grün → kein Grenzfall-Pickfehler.
- „clicking off-globe space clears the selection" (Null-Pick am
  Viewport-Rand): grün → kein Viewport-/Picking-Befund.
Es entsteht kein src-Befund aus der QA-Runde.

## Visuelle Abnahme der Shots (docs/12 §4 Gate 11)

Maßstab unverändert: Globus-Grundzustand; ein Epochen-Look ist für M0 NICHT
gefordert (Epochen sind docs/07 §M4). Beide Shots stammen aus dem
HEAD-Verifier-Lauf und sind identisch zu den in r1 abgenommenen Bildern
(SHA-gleich), erneut angesehen:
- `globe-overview.png`: Erde klar erkennbar (Afrika/Südeuropa/Südamerika),
  kontinuierliche Klimafarbrampe (Sahara-Ocker läuft organisch über den
  Sahel ins Sattgrün — docs/04 §Art-Direction), Displacement-Relief,
  Grenz-Overlay, Overlay-Panel „Wähle ein Land", OSM-Attribution im Footer
  (AGENTS-Regel 7). Keine Artefakte, keine harten Kanten.
- `globe-selected-country.png`: Selektion konsistent (Overlay
  „Domäne/Antarctica/ATA" == `selectedIso3:"ATA"` im Smoke-Report). Zackige
  Küstensäume = per ADR-002 gedecktes 1°-Interimsterrain (E21, vertagt).
  Antarktis als Default-Fokus bleibt UX-Makel E28 (minor, unverändert).

Keine kaputte Darstellung; kein blocking-Befund aus den Shots.

## QA-Adjudikation (Schritt 1b, abgeschlossen)

Q1 (=E24): behoben, Test grün. Q2: bleibt minor E28 (Begründung der
Herabstufung unverändert aus r1: kein Abnahmekriterium verlangt ein
bestimmtes Default-Land; Picking/Overlay A-M0-6/A-M0-10 erfüllt und visuell
belegt; QA selbst schlägt „niedrig" vor). Q3: Info, korrekte
Float32-Toleranzform (PROTOCOLS §4), keine Aktion. Q4: beide Kandidaten
ausgeführt und grün (s. E27). Q5: zutreffend, kein M0-Befund.

## Integritätsprüfung — Ergebnis: sauber

- Territorium: Das Rework-Delta `41002bb..47525e9` berührt ausschließlich
  `tools/shots/baseline/*.png` (Builder-Territorium, exakt der freigegebene
  E24-Fix), PROGRESS.md, REWORK-NOTES.md sowie den Orchestrator-Zeitstempel
  in STATUS.md (Operator-Ebene). Keine Änderung an `src/**`, `tests/**`,
  Gate-Skripten, Schwellen, Configs oder `contracts/**`.
- Gezielt gesucht, nicht gefunden: hart kodierte Erwartungswerte, entkernte/
  geskippte Tests (kein `it.skip`/`.only` in tests/; 68 Tests wirklich
  ausgeführt), gelockerte Configs (tsconfig strict inkl.
  `skipLibCheck:false` weiter testverankert), erfundene Daten (assets-Gate:
  5 Dateien SHA256-verifiziert; Interimsterrain per ADR-002 gedeckt;
  Bootstrap verweigert weiterhin ehrlich die ungepinnte Copernicus-Quelle),
  Golden-Änderung ohne ADR (kein Golden in M0), Territoriumsnähe-Tricks.
- Die Baseline-PNGs sind KEINE Synthese, sondern nachweislich echte,
  reproduzierte Capture-Artefakte (byteidentischer Re-Capture auf HEAD).
- REWORK-NOTES.md konsistent mit dem tatsächlichen Diff; Integritätsregel 4
  eingehalten (Builder hat lokal blockierte Läufe als solche deklariert
  statt Grün zu behaupten; der Verifier hat den Beleg geliefert).

## Einwände

### Blocking

Keine.

### Minor (nonblocking)

Keine neuen. Bestand unverändert in BACKLOG.md: E8, E9, E10, E12, E14, E16,
E22, E23, E26 (fps-Messwert erneut unplausibel: 22 784/27 067 „fps" im
aktuellen Smoke — Befund bestätigt, Eintrag offen), E28, E29, E30;
vertagt: E13 (ADR-003), E21 (ADR-002).

## Backlog-Fortschreibung dieser Runde

- E11 (Magic Numbers colorForHeight): **erledigt** verifiziert —
  `colorForHeight` existiert nicht mehr; `colorForTerrain` bezieht sämtliche
  ästhetischen Werte aus benannten `[tunable]`-Tokens (`WORLD_STYLE`,
  src/render/style/tokens.ts). BACKLOG aktualisiert.
- E15 (QA-Phase): bereits in r1 als erledigt markiert.

## Abgleich Abnahmekriterien docs/07 §M0

Vite+TS+pnpm, eslint/vitest, Verzeichnislayout ✓ (M0.setup 18/18);
Pipeline-Minimum inkl. Fixtures ✓ (readers/binary/dist-Tests, assets-Gate);
Globus mit Displacement, Orbit-Kamera, Grenz-Overlay, Picking ✓ (Shots +
E2E-Flow + Smoke `selectedIso3`); ABOUT.md/Lizenz ✓ (unverändert seit r1,
OSM-Attribution sichtbar); `pnpm test` grün ✓; smoke 0 Console-Errors ✓;
mutgate/graph/api/assets/shots eingerichtet ✓; Erst-Snapshots committet ✓;
Lockfile committet ✓ (deps-Gate frozen-lockfile); PROGRESS.md initialisiert
und aktuell ✓. 60 fps: als Zahl gemessen weit über 60, Messmethode aber
unplausibel (E26, nonblocking, Backlog) — kein Gegenbeleg gegen die
Abnahme, Smoke rendert 360 Frames fehlerfrei.

## Verdict

**PASS.** `gates.result=pass` auf HEAD, keine blocking-Befunde, visuelle
Abnahme bestanden, QA-Befunde adjudiziert (Q1 behoben, Q4 grün), Integrität
sauber. Nonblocking-Bestand ist in BACKLOG.md fortgeschrieben; gemäß
BACKLOG-Regel muss der M1-PLAN die offenen Einträge adressieren oder
begründet vertagen.
