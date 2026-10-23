#!/usr/bin/env bash
# Prüf-Gate für R-Pakete (Preset r-paket): R CMD build und R CMD check --as-cran --no-manual
# in einem temporären Verzeichnis außerhalb des Repos. Gebaut wird der Stand der versionierten
# Dateien; ignorierte Dateien (Quellen, Logs, Geheimnisse) erreichen den Build nie.
# Exit 0 = Status ohne ERROR und WARNING, 1 = ERROR, WARNING oder Build-Fehler, 2 = Infrastruktur.
# Die netzabhängigen CRAN-Incoming-Prüfungen sind lokal aus (_R_CHECK_CRAN_INCOMING_REMOTE_=false),
# damit das Gate ohne Netz deterministisch bleibt; die CI prüft sie weiterhin.
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
command -v R >/dev/null 2>&1 || { echo "r-check: R fehlt" >&2; exit 2; }
[ -f "$REPO_ROOT/DESCRIPTION" ] || { echo "r-check: DESCRIPTION fehlt in $REPO_ROOT" >&2; exit 2; }

work="$(mktemp -d "${TMPDIR:-/tmp}/harness-r-check.XXXXXX")" \
  || { echo "r-check: temporäres Verzeichnis nicht anlegbar" >&2; exit 2; }
case "$work" in "$REPO_ROOT"|"$REPO_ROOT"/*) echo "r-check: Arbeitsverzeichnis liegt im Repo: $work" >&2; exit 2 ;; esac
[ "${R_CHECK_KEEP:-0}" = 1 ] || trap 'rm -rf -- "$work"' EXIT

mkdir -p "$work/src"
(
  cd "$REPO_ROOT" || exit 2
  git ls-files -z | while IFS= read -r -d '' path; do
    [ -e "$path" ] && printf '%s\0' "$path"
  done | tar --null -T - -cf -
) | tar -xf - -C "$work/src" || { echo "r-check: Export der versionierten Dateien fehlgeschlagen" >&2; exit 2; }

run_limited() {
  if command -v timeout >/dev/null 2>&1; then timeout "${R_CHECK_TIMEOUT:-3600}" "$@"; else "$@"; fi
}

cd "$work" || exit 2
if ! run_limited R CMD build --no-manual src > build.log 2>&1; then
  cat build.log
  echo "r-check: fail — R CMD build fehlgeschlagen"
  exit 1
fi
cat build.log
tarball="$(find . -maxdepth 1 -name '*.tar.gz' -print -quit)"
[ -n "$tarball" ] || { echo "r-check: R CMD build erzeugte kein Archiv" >&2; exit 2; }

export _R_CHECK_CRAN_INCOMING_REMOTE_="${_R_CHECK_CRAN_INCOMING_REMOTE_:-false}"
run_limited R CMD check --as-cran --no-manual "$tarball" > check.log 2>&1
check_rc=$?
cat check.log
for failed_tests in ./*.Rcheck/tests/*.Rout.fail; do
  [ -f "$failed_tests" ] || continue
  echo "# ${failed_tests#./} (Ende)"
  tail -n 60 "$failed_tests"
done

status="$(grep -E '^Status: ' check.log | tail -n 1)"
if [ "$check_rc" = 124 ]; then
  echo "r-check: fail — R CMD check nach ${R_CHECK_TIMEOUT:-3600}s abgebrochen"
  exit 1
fi
if [ -z "$status" ]; then
  echo "r-check: fail — R CMD check ohne Status-Zeile beendet (rc=$check_rc)"
  exit 1
fi
if grep -Eq 'ERROR|WARNING' <<<"$status" || [ "$check_rc" != 0 ]; then
  echo "r-check: fail — $status"
  exit 1
fi
echo "r-check: pass — $status"
