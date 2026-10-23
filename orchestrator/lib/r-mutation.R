#!/usr/bin/env Rscript
# Mutationsadapter für orchestrator/gates.d/86-mutgate.sh (Preset r-paket, MUT_CMD).
# Mutiert mit dem CRAN-Paket muttest die geänderten R-Dateien aus MUT_FILES in einer schlanken
# Paketkopie außerhalb des Repos und schreibt den muttest-Bericht unverändert nach MUT_REPORT.
# Der Bericht folgt dem Stryker-Schema (files -> mutants mit status, mutatorName, location);
# das Urteil (Score, Floor, Ratchet, Äquivalenz) fällt allein in 86-mutgate.
# Exit 0 = Lauf beendet und Bericht geschrieben, 2 = Infrastruktur (dann fehlt der Bericht und
# 86-mutgate meldet error). Liegt im Betreiber-Territorium.
#
# Umgebung: MUT_FILES (kommagetrennt, von 86-mutgate), MUT_REPORT, REPO_ROOT,
# MUT_TEST_DIRS (Vorgabe: die vier Testordner der Rollen), MUT_WORKERS (Vorgabe 1),
# MUT_R_MUTATORS (kommagetrennte muttest-Funktionen ohne Argumente).

say <- function(...) cat("r-mutation: ", ..., "\n", sep = "")
infra <- function(...) {
  message("r-mutation: ", ...)
  quit(save = "no", status = 2)
}

for (pkg in c("muttest", "testthat", "pkgload", "R6", "jsonlite")) {
  if (!requireNamespace(pkg, quietly = TRUE)) infra("R-Paket fehlt: ", pkg)
}

env_list <- function(name, default, split) {
  value <- Sys.getenv(name, default)
  items <- trimws(strsplit(value, split)[[1]])
  items[nzchar(items)]
}
repo <- normalizePath(Sys.getenv("REPO_ROOT", getwd()), mustWork = TRUE)
if (!file.exists(file.path(repo, "DESCRIPTION"))) infra("DESCRIPTION fehlt in ", repo)
report <- Sys.getenv("MUT_REPORT", "reports/mutation/mutation.json")
if (!grepl("^/", report)) report <- file.path(repo, report)
test_dirs <- env_list("MUT_TEST_DIRS", "tests/testthat tests/acceptance tests/e2e tests/fuzz", "[[:space:]]+")
test_dirs <- test_dirs[dir.exists(file.path(repo, test_dirs))]
if (!length(test_dirs)) infra("kein Testordner vorhanden: ", Sys.getenv("MUT_TEST_DIRS"))
workers <- suppressWarnings(as.integer(Sys.getenv("MUT_WORKERS", "1")))
if (is.na(workers) || workers < 1L) infra("MUT_WORKERS muss eine positive Ganzzahl sein")
mutator_names <- env_list(
  "MUT_R_MUTATORS",
  paste(
    "arithmetic_operators", "comparison_operators", "logical_operators", "boolean_literals",
    "condition_mutations", "numeric_literals", "na_literals", "string_literals",
    "index_mutations", sep = ","
  ),
  ","
)

files <- env_list("MUT_FILES", "", ",")
files <- files[grepl("^R/[^/]+\\.[Rr]$", files) & file.exists(file.path(repo, files))]

# Schlanke Paketkopie: nur, was Laden und Testen brauchen; das Harness bleibt außen vor.
stage <- file.path(tempfile("harness-mutation-"), "pkg")
dir.create(stage, recursive = TRUE)
for (part in c("DESCRIPTION", "NAMESPACE", "R", "inst", "data", "src", test_dirs)) {
  source <- file.path(repo, part)
  if (!file.exists(source)) next
  target <- file.path(stage, dirname(part))
  dir.create(target, recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(source, target, recursive = TRUE)) infra("Kopie fehlgeschlagen: ", part)
}

mutators <- unlist(lapply(mutator_names, function(name) {
  factory <- get0(name, envir = asNamespace("muttest"), mode = "function")
  if (is.null(factory)) infra("unbekannter muttest-Mutator: ", name)
  made <- factory()
  if (inherits(made, "Mutator")) list(made) else made
}), recursive = FALSE)

old_wd <- setwd(stage)
plan <- if (length(files)) muttest::muttest_plan(mutators = mutators, source_files = files) else NULL
dir.create(dirname(report), recursive = TRUE, showWarnings = FALSE)
unlink(report)
if (is.null(plan) || nrow(plan) == 0) {
  # Ohne Mutanten gibt muttest keinen Bericht aus; der leere Bericht gibt diesen Befund wieder.
  empty <- lapply(files, function(path) {
    list(language = "r", source = paste(readLines(path), collapse = "\n"), mutants = list())
  })
  names(empty) <- files
  jsonlite::write_json(list(schemaVersion = "1.0", files = if (length(empty)) empty else structure(list(), names = character())),
    report, auto_unbox = TRUE, pretty = TRUE)
  say("keine Mutanten für: ", if (length(files)) paste(files, collapse = ", ") else "(keine R-Datei im Umfang)")
  quit(save = "no", status = 0)
}

# Ein Mutant gilt als entdeckt, sobald ein Test eines der Rollenordner ihn bemerkt.
HarnessTestStrategy <- R6::R6Class("HarnessTestStrategy",
  inherit = muttest::TestStrategy,
  public = list(
    dirs = NULL,
    initialize = function(dirs) {
      self$dirs <- dirs
    },
    execute = function(path, plan, reporter) {
      results <- list()
      for (dir in self$dirs) {
        if (!length(list.files(dir, pattern = "^test.*\\.[rR]$"))) next
        outcome <- testthat::test_dir(dir,
          reporter = reporter, stop_on_failure = FALSE, load_package = "source"
        )
        results[[length(results) + 1L]] <- as.data.frame(outcome)
      }
      if (!length(results)) return(list())
      do.call(rbind, results)
    }
  )
)

say(nrow(plan), " Mutanten in ", paste(files, collapse = ", "), "; Tests: ", paste(test_dirs, collapse = ", "))
muttest::muttest(
  plan,
  path = test_dirs[1],
  reporter = muttest::MultiReporter$new(
    muttest::ProgressMutationReporter$new(),
    muttest::JSONMutationReporter$new(path = report)
  ),
  test_strategy = HarnessTestStrategy$new(test_dirs),
  workers = workers
)
setwd(old_wd)
if (!file.exists(report)) infra("muttest hat keinen Bericht geschrieben: ", report)
say("Bericht: ", report)
