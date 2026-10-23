# Preset r-paket

Typbaustein für ein R-Paket in CRAN-Struktur (`DESCRIPTION`, `NAMESPACE`,
`R/`, `man/`, `tests/testthat/`). Die Projektierung übernimmt ihn, wenn
Intake-Feld 4 ein R-Paket festlegt. Versionen werden nicht geschätzt; was hier
als belegt steht, wurde am 23.10.2026 mit R 4.6.1, testthat 3.3.2, muttest
0.3.0, Codex CLI 0.164.0, Claude Code 2.1.309, Gemini CLI 0.65.0 und Qwen Code
0.26.0 ausgeführt. Der Selbsttest T-10 (`tests/template/test-t10-r-paket.sh`)
fährt die markierten Konfigurationsblöcke dieses Dokuments unverändert aus.

## Voraussetzungen

- R ab 4.1 mit `testthat` und `pkgload`; für Vignetten `rmarkdown`, `knitr`
  und pandoc; für `R CMD check` außerdem `qpdf`. Für Mutationstests das
  CRAN-Paket `muttest` (ab 0.3.0).
- WSL2 und Linux mit Codex CLI: `bubblewrap` (`bwrap`). Die Linux-Sandbox der
  Codex CLI nimmt das erste `bwrap` im `PATH` und warnt beim Start, wenn es
  fehlt.
- Gemini CLI als QA: `ripgrep` (`rg`); ohne es meldet die CLI „Ripgrep is not
  available“ und sucht langsamer.
- Jede Rollen-CLI ist unter `HOME` angemeldet. Rollen laufen mit `env -i`,
  Schlüssel aus Umgebungsvariablen kommen nicht an (README Abschnitt 6).

## Layout und Territorien

| Rolle | Pfade | Herkunft der Regel |
|---|---|---|
| Builder | `R/`, `man/`, `tests/testthat/`, `vignettes/`, `inst/`, `data/`, `data-raw/`, `DESCRIPTION`, `NAMESPACE`, `NEWS.md`, `.Rbuildignore` | `BUILDER_EXTRA_PATHS_REGEX` (unten) plus die festen Builder-Pfade des Orchestrators |
| Reviewer | `tests/acceptance/`, `reference/anchors/` | feste Reviewer-Pfade des Orchestrators |
| QA | `tests/e2e/`, `tests/fuzz/` | feste QA-Pfade des Orchestrators |
| Betreiber | `orchestrator/**` mit `orchestrator/lib/r-*.R` und `r-check.sh`, `tests/testthat.R`, `toolchain.json`, `config.env` | keine Modellrolle |

`tests/testthat.R` gehört bewusst keiner Rolle; der Betreiber legt es in M0
an, falls es fehlt. Das Test-Gate ruft testthat direkt über die Ordner auf und
hängt nicht von dieser Datei ab. Der Reviewer achtet bei Änderungen an
`.Rbuildignore` darauf, dass die Harness-Einträge erhalten bleiben.

Fertige Konfigurationszeilen für `orchestrator/config.env`:

<!-- preset-test: config-env -->
```sh
BUILDER_EXTRA_PATHS_REGEX='^(R/|man/|tests/testthat/|vignettes/|inst/|data/|data-raw/|DESCRIPTION$|NAMESPACE$|NEWS\.md$|\.Rbuildignore$)'
REVIEWER_EXTRA_PATHS_REGEX=
QA_EXTRA_PATHS_REGEX=
REBUILD_PATHS='R tests/testthat'
DEPS_CMD='Rscript orchestrator/lib/r-deps.R'
TEST_CMD='Rscript orchestrator/lib/r-tests.R'
LINT_CMD='bash orchestrator/lib/r-check.sh'
MUT_CMD='Rscript orchestrator/lib/r-mutation.R'
MUT_SCOPE_REGEX='^R/.*\.R$'
MUT_REPORT=reports/mutation/mutation.json
GATE_ERROR_CODES='2 126 127'
```

`GATE_ERROR_CODES` ergänzt die Vorgabe `126 127` um 2: Die R-Skripte melden
fehlende Werkzeuge, Pakete oder Dateien mit Exit 2; das ist Infrastruktur und
verbraucht keine Rework-Runde. Fachliche Fehlschläge enden mit Exit 1. Die
Liste gilt global für alle Kommando-Gates.

## Toolchain

Beispiel für `toolchain.json` (R ab 4.1, `DESCRIPTION` als Manifest). R selbst
installiert das Harness nicht; fehlt es, bricht `bootstrap.sh` benannt ab.

<!-- preset-test: toolchain -->
```json
{
  "contract": 1,
  "runtimes": [
    {
      "name": "R",
      "command": "Rscript",
      "versionCommand": "Rscript --version",
      "versionRegex": "R\\) version (4\\.([1-9]|[1-9][0-9]+)|([5-9]|[1-9][0-9]+)\\.[0-9]+)\\.[0-9]+",
      "installCommand": "",
      "updateCommand": ""
    }
  ],
  "manifests": [
    {
      "path": "DESCRIPTION",
      "installCommand": "Rscript orchestrator/lib/r-deps.R",
      "updateCommand": ""
    }
  ]
}
```

`Rscript --version` meldet etwa „Rscript (R) version 4.6.1 (2026-06-24)“; der
Ausdruck nimmt 4.1 bis 4.x und jede spätere Hauptversion an, 4.0 nicht.

## Gates

Aktivieren heißt kopieren, ausführbar machen und mit Modus 100755 eintragen.
Auf `/mnt/c` gilt `core.filemode=false`; ein gewöhnliches `git add` trägt neue
Dateien dort als 100644 ein, und ein frischer Klon hätte nicht ausführbare
Gates. Darum immer `git add --chmod=+x`:

```bash
for gate in 10-deps 20-lint 30-tests 70-trace 82-territory 86-mutgate 87-golden-adr; do
  cp "orchestrator/gates.d/$gate.sh.example" "orchestrator/gates.d/$gate.sh"
  chmod +x "orchestrator/gates.d/$gate.sh"
  git add --chmod=+x "orchestrator/gates.d/$gate.sh"
done
git ls-files -s orchestrator/gates.d/[0-9][0-9]-*.sh   # jede Zeile beginnt mit 100755
```

- `deps` (`DEPS_CMD`, `orchestrator/lib/r-deps.R`): liest Depends, Imports,
  LinkingTo und Suggests aus `DESCRIPTION`, installiert nur fehlende oder zu
  alte Pakete und schreibt die Versionen ins Gate-Log. Suggests gehören dazu,
  weil `R CMD check` sie verlangt. Exit 1, wenn eine Anforderung unerfüllt
  bleibt.
- `tests` (`TEST_CMD`, `orchestrator/lib/r-tests.R`): ein testthat-Lauf über
  `tests/testthat`, `tests/acceptance`, `tests/e2e` und `tests/fuzz` mit aus den
  Quellen geladenem Paket (`load_package = "source"`). Exit 1 bei jedem
  Fehlschlag oder Fehler, auch wenn das Laden des Pakets scheitert. Leere
  Ordner werden übersprungen; enthält keiner Tests, ist das `fail`. Das Skript
  liegt im Betreiber-Territorium, damit keine Modellrolle es ändern kann.
- `lint` (`LINT_CMD`, `orchestrator/lib/r-check.sh`): `R CMD build` und
  `R CMD check --as-cran --no-manual` in einem temporären Verzeichnis außerhalb
  des Repos. Gebaut wird der Stand der versionierten Dateien; ignorierte Dateien
  wie Quellen, Logs oder `secrets.env` erreichen den Build nie. ERROR oder
  WARNING heißt `fail`, NOTEs bestehen. Die netzabhängigen Teile der
  CRAN-Incoming-Prüfung sind lokal abgeschaltet
  (`_R_CHECK_CRAN_INCOMING_REMOTE_=false`), damit das Gate ohne Netz
  deterministisch bleibt; die CI prüft sie weiterhin. `R_CHECK_TIMEOUT`
  (Vorgabe 3600 s) begrenzt Build und Check, `R_CHECK_KEEP=1` behält das
  Arbeitsverzeichnis zur Fehlersuche.
- `trace`, `territory`, `golden-adr`: wie in README Abschnitt 7.
- `mutgate` (`MUT_CMD`, `orchestrator/lib/r-mutation.R`): siehe unten.

## Mutationstests mit muttest

`muttest` 0.3.0 schreibt mit `JSONMutationReporter` einen Bericht im
Stryker-Schema: `files` → `mutants` mit `status`, `mutatorName` und
`location.start.line`. Das ist genau das Format, das
`orchestrator/gates.d/86-mutgate.sh.example` auswertet; der Adapter
`orchestrator/lib/r-mutation.R` reicht den Bericht unverändert nach
`MUT_REPORT` durch und erfindet keine Werte. Er

- mutiert nur die geänderten Dateien aus `MUT_FILES` (von 86-mutgate, Umfang
  `MUT_SCOPE_REGEX`),
- arbeitet in einer schlanken Kopie des Pakets außerhalb des Repos
  (`DESCRIPTION`, `NAMESPACE`, `R/`, `inst/`, `data/`, `src/` und die
  Testordner), damit muttest nicht je Mutant das ganze Harness kopiert,
- zählt einen Mutanten als entdeckt, sobald ein Test eines der Ordner aus
  `MUT_TEST_DIRS` ihn bemerkt (Vorgabe: die vier Testordner der Rollen),
- nimmt als Mutatoren die Operator- und Literalfamilien von muttest
  (`MUT_R_MUTATORS`, kommagetrennte Funktionsnamen; Vorgabe:
  `arithmetic_operators`, `comparison_operators`, `logical_operators`,
  `boolean_literals`, `condition_mutations`, `numeric_literals`, `na_literals`,
  `string_literals`, `index_mutations`),
- läuft mit `MUT_WORKERS` parallelen R-Prozessen (Vorgabe 1).

Unterschied zur muttest-Zusammenfassung: muttest zählt `RuntimeError`
(Testfehler, Zeitüberschreitung) als entdeckt; 86-mutgate zählt wie Stryker
nur `Killed` und `Timeout` als entdeckt und `RuntimeError` gar nicht. Der
Gate-Score ist dadurch höchstens so hoch wie der von muttest gemeldete.
Laufzeit: Jeder Mutant führt die gesamte Testmenge aus. Bei langen Testläufen
`MUT_TEST_DIRS` einschränken oder `MUT_WORKERS` erhöhen; Schwellen bleiben
unverändert.

## Artefakte

`R CMD build`, `R CMD check` und Vignetten erzeugen `*.Rcheck/`,
`<paket>_<version>.tar.gz`, `doc/` und `Meta/`. Die Gates bauen außerhalb des
Repos. Baut der Builder selbst im Checkout (etwa `R CMD build .` oder
`devtools::build_vignettes()`), meldet die Territoriumsprüfung diese Pfade,
auch wenn `.gitignore` sie ausschließt. Entweder außerhalb bauen
(`devtools::check()` arbeitet ohnehin in einem temporären Verzeichnis) oder im
Zielrepo diese Zeilen in `orchestrator/artifact-paths.allowlist` ergänzen; sie
gelten dann als territoriumsfreie Artefakte und werden nach einem verworfenen
Versuch gelöscht:

```text
(^|/)[^/]+\.Rcheck(/|$)
^[^/]+_[0-9][0-9.-]*\.tar\.gz$
^doc(/|$)
^Meta(/|$)
^pkgdown-site(/|$)
```

## `.Rbuildignore`

Alle Harness-Dateien bleiben aus dem Paket, sonst meldet `R CMD check` fremde
Dateien auf oberster Ebene. `tools/install-into.sh` ergänzt diese Zeilen bei
einem R-Paket selbst; `.gitignore` und `.gitattributes` schließt R ohnehin aus:

```text
^orchestrator$
^projektierung$
^reference$
^contracts$
^docs$
^tests/acceptance$
^tests/e2e$
^tests/fuzz$
^reports$
^AGENTS\.md$
^CLAUDE\.md$
^BACKLOG\.md$
^PROGRESS\.md$
^STATUS\.md$
^RUNBOOK\.md$
^IMPLEMENTATION-RULES\.md$
^bootstrap\.sh$
^start\.sh$
^config\.env\.example$
^toolchain\.json
```

Wer das Template klont statt einsetzt, ergänzt zusätzlich `^tests/template$`
und `^tools$` oder löscht diese beiden Template-Ordner im Zielprojekt.

## `docs/` und pkgdown

Das Harness legt Vision, Specs und ADRs unter `docs/` ab; das Golden-ADR-Gate
sucht ADRs unter `docs/decisions/`. pkgdown baut standardmäßig nach `docs/`,
und viele Pakete ignorieren `docs/` in `.gitignore`. Dann würden Specs nie
versioniert, und `pkgdown::build_site_github_pages()` bricht mit `clean = TRUE`
auf einem fremden, nicht leeren `docs/` ab („is non-empty and not built by
pkgdown“). Festlegung: pkgdown baut in ein eigenes Ziel, Vorgabe
`pkgdown-site/`.

- `.gitignore`: Zeile `docs/` entfernen, `pkgdown-site/` ergänzen.
- `.Rbuildignore`: `^pkgdown-site$` ergänzen; `^docs$` bleibt.
- `_pkgdown.yml`: `destination: pkgdown-site` (wirkt auf `pkgdown::build_site()`).
- GitHub-Workflow: `pkgdown::build_site_github_pages(dest_dir = "pkgdown-site", ...)`
  und im Deploy-Schritt `folder: pkgdown-site`.
  `build_site_github_pages()` überschreibt `destination` mit `dest_dir`
  (Vorgabe `"docs"`); der Eintrag in `_pkgdown.yml` allein genügt dort nicht.
- Prüfung: `git check-ignore docs/00-vision.md` bleibt leer, und der
  pkgdown-Workflow läuft nach dem Push grün.

Alternative: pkgdown nur in der CI auf einen eigenen Branch bauen und lokal
nicht. Das Installationsskript ändert keine dieser Projektdateien; es meldet den
Konflikt und nennt die Änderungen.

## Quellen

Die Territoriumsprüfung schwächt das Preset nicht ab: Sie erfasst auch
ignorierte Dateien. `snapshot_worktree` hasht und kopiert vor jedem
Modellaufruf jede ignorierte Datei nach `/tmp`, `ownership_check` hasht sie
danach erneut. Große Quellen im Checkout verlangsamen deshalb jeden Aufruf.

- Ins Repo kommt nur der Textspiegel der Quellen: `reference/quellen/text/`
  (eine `.txt` je Quelle mit Seitenmarken; git-ignoriert, weil die Inhalte
  urheberrechtlich geschützt sein können). `tools/install-into.sh` nimmt
  `reference/quellen/` in `.gitignore` auf.
- Der Katalog der Quellen wird versioniert: `reference/QUELLENKATALOG.md`
  (`tools/install-into.sh --katalog <KATALOG.md>` kopiert ihn).
- PDFs, EPUB und Rohdaten bleiben außerhalb des Repos; ihr Pfad steht in der
  Spec. Eingefrorene Datenteilmengen kommen mit SHA-256 ins Repo, soweit die
  Lizenz es erlaubt.

Messung am 23.10.2026 (WSL2, Ubuntu 26.04): Dauer eines Orchestrator-Aufrufs
mit genau einer Modellphase und einer Attrappe als Modell, Median aus drei
Läufen. Der Abstand zur Spalte „ohne Quellen“ ist der Mehraufwand je
Modellaufruf; Skript und Rohwerte in `PROGRESS.md`, Abschnitt „Umbau 1.1.0“.

| Checkout | ohne Quellen | mit Textspiegel (174 Quellen, 303 Dateien, 39 MB) | zusätzlich 1,3 GB Rohdaten (2 Dateien, synthetisch) |
|---|---:|---:|---:|
| `/mnt/c` | 3,7 s | 24,2 s | 56,5 s |
| WSL-Dateisystem (ext4) | 0,4 s | 4,0 s | nicht gemessen |

Der Aufwand wächst vor allem mit der Zahl der Dateien (je Datei mehrere
Prozessstarts für `stat`, `sha256sum`, `cp` und `grep`), bei großen Dateien
zusätzlich mit der Datenmenge. Ein Meilenstein hat mindestens fünf
Modellaufrufe, mit QA sechs. Rohdaten im Checkout kosten auf `/mnt/c` rund
eine halbe Minute je Aufruf; liegt das Repo im WSL-Dateisystem, sinkt der
Aufwand des Textspiegels von rund 20 s auf rund 4 s je Aufruf.

## Einsetzen in ein bestehendes Paket

1. `bash <template>/tools/install-into.sh [--katalog <KATALOG.md>] <paket>`
   kopiert die Harness-Teile, überschreibt nie `README.md`, `LICENSE`,
   `LICENSE.md`, `CITATION.cff`, `.zenodo.json` oder andere vorhandene
   Dateien, führt `.gitignore`, `.gitattributes` und `.Rbuildignore` zusammen
   und trägt jede im Template ausführbare Datei mit `git add --chmod=+x` ein.
   Es staged nur; Exit 3 heißt: eingesetzt, aber mit offenen Punkten (etwa der
   docs/-Konflikt oben). `--dry-run` zeigt die Aktionen ohne Änderung.
2. Offene Punkte lösen, `git status` und `git diff --cached --stat` prüfen.
3. `bash bootstrap.sh --no-start --non-interactive` (kein Editor, Tunnelmodus
   `quick` als Vorgabe); danach `orchestrator/config.env` bearbeiten. Wer
   interaktiv startet, setzt `EDITOR=nano`: Beim ersten Lauf öffnet
   `bootstrap.sh` die Konfiguration mit `${EDITOR:-vi}` und fragt auch mit
   `--no-start` nach dem Tunnelmodus.
4. `toolchain.json` nach dem Block oben, Konfigurationszeilen eintragen, Gates
   aktivieren, Betreiber-Commit. `git ls-files -s orchestrator/*.sh
   orchestrator/lib/*.sh orchestrator/gates.d/[0-9][0-9]-*.sh`: jede Zeile
   beginnt mit 100755.

## Rollenkommandos

Die geprüfte Beispielkonfiguration für Builder (GPT-6 Astra über Codex CLI),
Reviewer und Schiedsrichter (Claude Opus 5.5 über Claude Code) und QA (Gemini 4
Argon über Gemini CLI, Ersatz Kimi K3 über Qwen Code) steht auskommentiert in
`config.env.example`.

- QA braucht eine Shell für `Rscript`, um rote Tests auszuführen. Gemini CLI:
  Policy-Datei `orchestrator/policies/qa-gemini.toml` über `--policy` (nur
  `Rscript`, nie yolo). Qwen Code: `--allowed-tools 'run_shell_command(Rscript)'`.
- Der Reviewer braucht `Rscript` für Anker und Gegenrechnungen mit
  unabhängigen Paketen (etwa VCA, irr, SixSigma) und um die eigenen
  Abnahmetests rot laufen zu sehen: `--allowedTools "Bash(Rscript:*)"`. Ohne
  diese Regel verweigert `claude -p --permission-mode acceptEdits` jeden
  Rscript-Aufruf.
- Die Freigabe nur für `Rscript` ist keine Sicherheitsgrenze: Über `system()`
  startet R jedes Kommando. Schutz bleiben die Territoriumsprüfung und der
  Rollback des Orchestrators.
- Im Codex-Modus `workspace-write` hat der Builder kein Netz. Abhängigkeiten
  installiert das deps-Gate vorab, also außerhalb der Sandbox.

## M0

M0 für ein bestehendes Paket: Toolchain, Preset und alle gewählten Gates laufen
grün auf dem vorhandenen Code, ohne Änderung an `R/`. Kriterien prüfen das
belegbar, etwa „`git diff --quiet plan/M0 -- R` ist leer“ und „gates.json
meldet pass für deps, tests, lint, trace und territory“. Fehlende Abnahmetests
schreibt der Reviewer in ACCEPTANCE; der Builder ergänzt in M0 höchstens
`PROGRESS.md`, `NEWS.md` oder Dokumentation.
