#!/usr/bin/env Rscript
# deps-Gate für R-Pakete (Preset r-paket): Abhängigkeiten aus DESCRIPTION (Depends, Imports,
# LinkingTo, Suggests) prüfen, nur fehlende oder zu alte Pakete installieren und die
# Versionen protokollieren. Liegt im Betreiber-Territorium.
# Exit 0 = alle erfüllt, 1 = mindestens eine Anforderung bleibt unerfüllt, 2 = Infrastruktur.
# Aufruf aus der Repo-Wurzel: Rscript orchestrator/lib/r-deps.R [--check-only]

say <- function(...) cat("r-deps: ", ..., "\n", sep = "")
infra <- function(...) {
  message("r-deps: ", ...)
  quit(save = "no", status = 2)
}

check_only <- "--check-only" %in% commandArgs(trailingOnly = TRUE)
if (!file.exists("DESCRIPTION")) infra("DESCRIPTION fehlt; aus der Repo-Wurzel aufrufen")

fields <- c("Depends", "Imports", "LinkingTo", "Suggests")
dcf <- read.dcf("DESCRIPTION", fields = fields)
entries <- unlist(lapply(fields, function(field) {
  value <- dcf[1, field]
  if (is.na(value)) return(character())
  trimws(strsplit(gsub("\\s+", " ", value), ",", fixed = TRUE)[[1]])
}))
entries <- entries[nzchar(entries)]
pattern <- "^([A-Za-z][A-Za-z0-9.]*)\\s*(\\(\\s*(>=|<=|==|!=|>|<)\\s*([^)[:space:]]+)\\s*\\))?$"
bad <- entries[!grepl(pattern, entries)]
if (length(bad)) infra("nicht lesbare Abhängigkeit in DESCRIPTION: ", paste(bad, collapse = "; "))
reqs <- data.frame(
  package = sub(pattern, "\\1", entries),
  op = sub(pattern, "\\3", entries),
  version = sub(pattern, "\\4", entries),
  stringsAsFactors = FALSE
)

satisfies <- function(installed, op, required) {
  if (!nzchar(op)) return(TRUE)
  installed <- package_version(installed)
  required <- package_version(required)
  switch(op,
    ">=" = installed >= required, ">" = installed > required,
    "<=" = installed <= required, "<" = installed < required,
    "==" = installed == required, "!=" = installed != required
  )
}
installed_version <- function(package) {
  if (package == "R") return(as.character(getRversion()))
  path <- find.package(package, quiet = TRUE)
  if (!length(path)) return(NA_character_)
  as.character(packageVersion(package, lib.loc = dirname(path[1])))
}
unmet <- function() {
  ok <- mapply(function(package, op, version) {
    have <- installed_version(package)
    !is.na(have) && satisfies(have, op, version)
  }, reqs$package, reqs$op, reqs$version)
  reqs[!ok, , drop = FALSE]
}

missing <- unmet()
to_install <- setdiff(unique(missing$package), "R")
if (length(to_install) && !check_only) {
  say("installiere: ", paste(to_install, collapse = ", "))
  repos <- getOption("repos")
  if (is.null(repos) || is.na(repos["CRAN"]) || repos["CRAN"] == "@CRAN@") {
    options(repos = c(CRAN = "https://cloud.r-project.org"))
  }
  user_lib <- Sys.getenv("R_LIBS_USER")
  if (nzchar(user_lib) && !any(file.access(.libPaths(), 2) == 0)) {
    dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)
    .libPaths(c(user_lib, .libPaths()))
  }
  tryCatch(
    utils::install.packages(to_install, dependencies = NA),
    error = function(e) say("Installation meldet: ", conditionMessage(e))
  )
  missing <- unmet()
}

for (i in seq_len(nrow(reqs))) {
  have <- installed_version(reqs$package[i])
  wanted <- if (nzchar(reqs$op[i])) paste(reqs$op[i], reqs$version[i]) else "beliebig"
  say(sprintf("%-14s %-12s (verlangt: %s)", reqs$package[i], ifelse(is.na(have), "fehlt", have), wanted))
}
if (nrow(missing)) {
  say("fail — unerfüllt: ", paste(sprintf("%s %s %s", missing$package, missing$op, missing$version), collapse = "; "))
  quit(save = "no", status = 1)
}
say("pass — ", nrow(reqs), " Anforderungen erfüllt (R ", as.character(getRversion()), ")")
