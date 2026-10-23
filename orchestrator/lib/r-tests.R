#!/usr/bin/env Rscript
# Test-Gate für R-Pakete (Preset r-paket): ein testthat-Lauf über die Testordner aller
# Rollen mit aus den Quellen geladenem Paket. Liegt im Betreiber-Territorium.
# Exit 0 = alle Tests grün, 1 = mindestens ein Fehlschlag oder Fehler, 2 = Infrastruktur.
# Aufruf aus der Repo-Wurzel: Rscript orchestrator/lib/r-tests.R [Testordner ...]

say <- function(...) cat("r-tests: ", ..., "\n", sep = "")
infra <- function(...) {
  message("r-tests: ", ...)
  quit(save = "no", status = 2)
}

if (!file.exists("DESCRIPTION")) infra("DESCRIPTION fehlt; aus der Repo-Wurzel aufrufen")
for (pkg in c("testthat", "pkgload")) {
  if (!requireNamespace(pkg, quietly = TRUE)) infra("R-Paket fehlt: ", pkg)
}

dirs <- commandArgs(trailingOnly = TRUE)
if (!length(dirs)) dirs <- c("tests/testthat", "tests/acceptance", "tests/e2e", "tests/fuzz")

totals <- c(tests = 0, failed = 0, errors = 0, skipped = 0)
ran <- character()
for (dir in dirs) {
  files <- if (dir.exists(dir)) list.files(dir, pattern = "^test.*\\.[rR]$") else character()
  if (!length(files)) {
    say(dir, ": keine Testdateien, übersprungen")
    next
  }
  say(dir, ": ", length(files), " Testdatei(en)")
  result <- tryCatch(
    testthat::test_dir(
      dir,
      reporter = testthat::ProgressReporter$new(show_praise = FALSE),
      stop_on_failure = FALSE,
      load_package = "source"
    ),
    error = function(e) e
  )
  if (inherits(result, "error")) {
    # Ein Abbruch vor oder zwischen den Tests (etwa ein Syntaxfehler unter R/) ist ein Fehlschlag.
    say(dir, ": Testlauf abgebrochen: ", conditionMessage(result))
    totals[["errors"]] <- totals[["errors"]] + 1
    ran <- c(ran, dir)
    next
  }
  df <- as.data.frame(result)
  totals[["tests"]] <- totals[["tests"]] + nrow(df)
  totals[["failed"]] <- totals[["failed"]] + sum(df$failed > 0)
  totals[["errors"]] <- totals[["errors"]] + sum(df$error)
  totals[["skipped"]] <- totals[["skipped"]] + sum(df$skipped)
  ran <- c(ran, dir)
}

if (!length(ran)) {
  say("kein Testordner enthält Tests")
  quit(save = "no", status = 1)
}
summary <- sprintf(
  "%d Tests in %s; %d fehlgeschlagen, %d Fehler, %d übersprungen",
  totals[["tests"]], paste(ran, collapse = ", "),
  totals[["failed"]], totals[["errors"]], totals[["skipped"]]
)
if (totals[["failed"]] + totals[["errors"]] > 0) {
  say("fail — ", summary)
  quit(save = "no", status = 1)
}
say("pass — ", summary)
