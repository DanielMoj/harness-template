#!/usr/bin/env bash
# Setzt die Harness-Teile dieses Templates in ein bestehendes Git-Repo ein.
# Grundsätze: Projektdateien werden nie überschrieben (README.md, LICENSE, LICENSE.md,
# CITATION.cff, .zenodo.json werden nicht angefasst, vorhandene Dateien mit anderem Inhalt
# bleiben und werden als Konflikt gemeldet). .gitignore und .gitattributes werden
# zusammengeführt, bei R-Paketen auch .Rbuildignore. Jede Datei mit Modus 100755 im Template
# wird mit `git add --chmod=+x` eingetragen, damit sie auch bei core.filemode=false ausführbar
# im Repo landet. Das Skript staged nur; den Commit macht der Betreiber.
#
# Exit 0 = eingesetzt ohne offene Punkte, 3 = eingesetzt mit offenen Punkten (Bericht),
# 2 = nichts geändert (Aufruf-, Repo- oder Zustandsfehler).
set -euo pipefail

TEMPLATE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=0
KATALOG=""
TARGET=""

usage() {
  echo "Aufruf: bash tools/install-into.sh [--dry-run] [--katalog <KATALOG.md>] <zielrepo>" >&2
  exit 2
}
fail() { echo "install-into: FATAL: $*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --katalog) [ "$#" -ge 2 ] || usage; KATALOG="$2"; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [ -z "$TARGET" ] || usage; TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || usage

[ -f "$TEMPLATE_ROOT/orchestrator/orchestrate.sh" ] || fail "kein harness-template unter $TEMPLATE_ROOT"
git -C "$TEMPLATE_ROOT" rev-parse --git-dir >/dev/null 2>&1 || fail "Template ist kein Git-Checkout: $TEMPLATE_ROOT"
TARGET="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null)" || fail "Ziel ist kein Git-Repo: $TARGET"
[ "$TARGET" != "$TEMPLATE_ROOT" ] || fail "Ziel ist das Template selbst"
[ -z "$(git -C "$TARGET" status --porcelain --untracked-files=no)" ] \
  || fail "Ziel hat nicht committete Änderungen an versionierten Dateien; zuerst committen oder verwerfen"
if [ -n "$KATALOG" ]; then
  [ -f "$KATALOG" ] || fail "Katalog fehlt: $KATALOG"
  KATALOG="$(cd "$(dirname "$KATALOG")" && pwd)/$(basename "$KATALOG")"
fi

declare -a COPIED=() UNCHANGED=() CONFLICTS=() OPEN=() MERGED=() EXEC_FIXED=()

act() {
  # Führt eine verändernde Aktion aus oder zeigt sie im Probelauf nur an.
  if [ "$DRY_RUN" = 1 ]; then
    printf 'probelauf:'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

stage_file() {
  local path="$1" mode="$2"
  if [ "$mode" = 100755 ]; then
    act git -C "$TARGET" add --chmod=+x -- "$path"
  else
    act git -C "$TARGET" add -- "$path"
  fi
}

target_index_mode() {
  git -C "$TARGET" ls-files -s -- "$1" | awk 'NR==1{print $1}'
}

excluded_from_payload() {
  case "$1" in
    README.md|LICENSE|LICENSE.md|CITATION.cff|.zenodo.json) return 0 ;;  # Projektidentität
    .gitignore|.gitattributes) return 0 ;;                               # werden zusammengeführt
    docs/template/*|tests/template/*|tools/*) return 0 ;;                # Template-intern
    PROGRESS.md|STATUS.md|orchestrator/state/summary.json) return 0 ;;   # Template-Verlauf, Laufzeit
  esac
  return 1
}

ignored_in_target() {
  git -C "$TARGET" check-ignore -q --no-index -- "$1" 2>/dev/null
}

# 1. Harness-Dateien aus dem Index des Templates (Inhalt und Modus wie versioniert).
while IFS= read -r -d '' record; do
  read -r mode object _stage <<<"${record%%$'\t'*}"
  path="${record#*$'\t'}"
  excluded_from_payload "$path" && continue
  case "$mode" in 100644|100755) ;; *) OPEN+=("Template-Eintrag mit Modus $mode übersprungen: $path"); continue ;; esac
  dest="$TARGET/$path"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ -f "$dest" ] && cmp -s <(git -C "$TEMPLATE_ROOT" cat-file blob "$object") "$dest"; then
      UNCHANGED+=("$path")
      if [ "$mode" = 100755 ] && [ "$(target_index_mode "$path")" != 100755 ] && ! ignored_in_target "$path"; then
        act chmod +x "$dest"
        stage_file "$path" "$mode"
        EXEC_FIXED+=("$path")
      fi
    else
      CONFLICTS+=("$path")
    fi
    continue
  fi
  act mkdir -p "$(dirname "$dest")"
  if [ "$DRY_RUN" = 1 ]; then
    echo "probelauf: schreibe $path ($mode)"
  else
    git -C "$TEMPLATE_ROOT" cat-file blob "$object" > "$dest"
    if [ "$mode" = 100755 ]; then chmod +x "$dest"; else chmod -x "$dest"; fi
  fi
  if ignored_in_target "$path"; then
    OPEN+=("$path ist im Zielrepo durch .gitignore ausgeschlossen und wurde nur kopiert, nicht eingetragen")
  else
    stage_file "$path" "$mode"
  fi
  COPIED+=("$path")
done < <(git -C "$TEMPLATE_ROOT" ls-files -s -z)

# 2. Gerüst für PROGRESS.md; der Verlauf des Templates gehört nicht ins Projekt.
if [ ! -e "$TARGET/PROGRESS.md" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    echo "probelauf: schreibe PROGRESS.md (Gerüst)"
  else
    printf '%s\n' '# PROGRESS — Langzeitgedächtnis des Builders' '' '_Noch keine Einträge._' > "$TARGET/PROGRESS.md"
  fi
  stage_file PROGRESS.md 100644
  COPIED+=("PROGRESS.md (Gerüst)")
fi

# 3. Zusammenführen: fehlende Zeilen als markierter Block anhängen, nie ersetzen.
merge_lines() {
  local file="$1" title="$2" line
  shift 2
  local -a missing=()
  for line in "$@"; do
    [ -n "$line" ] || continue
    if [ -f "$TARGET/$file" ] && grep -Fxq -- "$line" "$TARGET/$file"; then continue; fi
    missing+=("$line")
  done
  [ "${#missing[@]}" -gt 0 ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    echo "probelauf: ergänze $file um: ${missing[*]}"
  else
    {
      if [ -s "$TARGET/$file" ] && [ -n "$(tail -c 1 "$TARGET/$file")" ]; then echo; fi
      [ ! -s "$TARGET/$file" ] || echo
      echo "# $title"
      printf '%s\n' "${missing[@]}"
    } >> "$TARGET/$file"
  fi
  stage_file "$file" 100644
  MERGED+=("$file: ${#missing[@]} Zeile(n)")
}

mapfile -t gitignore_lines < <(git -C "$TEMPLATE_ROOT" show :.gitignore \
  | grep -vE '^[[:space:]]*(#|$)' | grep -vFx 'reference/patch-v2/')
grep -Fxq 'reference/quellen/' < <(printf '%s\n' "${gitignore_lines[@]}") || gitignore_lines+=('reference/quellen/')
merge_lines .gitignore 'harness-template (tools/install-into.sh): Laufzeit, Geheimnisse, Quellen' "${gitignore_lines[@]}"
mapfile -t gitattributes_lines < <(git -C "$TEMPLATE_ROOT" show :.gitattributes | grep -vE '^[[:space:]]*(#|$)')
merge_lines .gitattributes 'harness-template (tools/install-into.sh): LF für Skripte' "${gitattributes_lines[@]}"

R_PACKAGE=0
if [ -f "$TARGET/DESCRIPTION" ] && [ -f "$TARGET/NAMESPACE" ]; then
  R_PACKAGE=1
  # Liste nach projektierung/presets/r-paket/PRESET.md; ohne sie meldet R CMD check fremde Dateien.
  merge_lines .Rbuildignore 'harness-template (tools/install-into.sh): Harness-Dateien' \
    '^orchestrator$' '^projektierung$' '^reference$' '^contracts$' '^docs$' \
    '^tests/acceptance$' '^tests/e2e$' '^tests/fuzz$' '^reports$' \
    '^AGENTS\.md$' '^CLAUDE\.md$' '^BACKLOG\.md$' '^PROGRESS\.md$' '^STATUS\.md$' \
    '^RUNBOOK\.md$' '^IMPLEMENTATION-RULES\.md$' '^bootstrap\.sh$' '^start\.sh$' \
    '^config\.env\.example$' '^toolchain\.json'
fi

# 4. Quellenkatalog (versioniert); Texte und Rohdaten kopiert das Skript nicht.
if [ -n "$KATALOG" ]; then
  if [ -e "$TARGET/reference/QUELLENKATALOG.md" ]; then
    if cmp -s "$KATALOG" "$TARGET/reference/QUELLENKATALOG.md"; then
      UNCHANGED+=("reference/QUELLENKATALOG.md")
    else
      CONFLICTS+=("reference/QUELLENKATALOG.md")
    fi
  else
    act mkdir -p "$TARGET/reference"
    act cp "$KATALOG" "$TARGET/reference/QUELLENKATALOG.md"
    stage_file reference/QUELLENKATALOG.md 100644
    COPIED+=("reference/QUELLENKATALOG.md (aus $KATALOG)")
  fi
fi

# 5. Prüfungen am Ergebnis: Modi im Index, Zeilenenden, docs/-Konflikt mit pkgdown.
if [ "$DRY_RUN" = 0 ]; then
  while IFS= read -r -d '' record; do
    read -r mode _object _stage <<<"${record%%$'\t'*}"
    path="${record#*$'\t'}"
    [ "$mode" = 100755 ] || continue
    excluded_from_payload "$path" && continue
    [ -e "$TARGET/$path" ] || continue
    ignored_in_target "$path" && continue
    actual="$(target_index_mode "$path")"
    [ "$actual" = 100755 ] || OPEN+=("$path steht mit Modus ${actual:-fehlt} statt 100755 im Index")
  done < <(git -C "$TEMPLATE_ROOT" ls-files -s -z)
  while IFS= read -r crlf; do
    [ -n "$crlf" ] && OPEN+=("CRLF im Index, wird durch .gitattributes normalisiert: $crlf (git add --renormalize prüfen)")
  done < <(git -C "$TARGET" ls-files --eol | awk '$1=="i/crlf"{print $NF}')
fi

if git -C "$TARGET" check-ignore -q docs/00-vision.md 2>/dev/null; then
  OPEN+=("docs/ ist im Zielrepo ignoriert ($(git -C "$TARGET" check-ignore -v docs/00-vision.md | cut -f1)); Specs und ADRs unter docs/ würden nie versioniert")
fi
for workflow in "$TARGET"/.github/workflows/*.yml "$TARGET"/.github/workflows/*.yaml; do
  [ -f "$workflow" ] || continue
  grep -q 'build_site_github_pages' "$workflow" || continue
  rel="${workflow#"$TARGET"/}"
  grep -q 'dest_dir' "$workflow" || OPEN+=("$rel: pkgdown baut mit build_site_github_pages() nach docs/ (Vorgabe dest_dir = \"docs\", clean = TRUE)")
  grep -Eq 'folder:[[:space:]]*docs[[:space:]]*$' "$workflow" && OPEN+=("$rel: Deploy-Schritt veröffentlicht folder: docs")
done
if [ -f "$TARGET/_pkgdown.yml" ] && ! grep -Eq '^destination:' "$TARGET/_pkgdown.yml"; then
  OPEN+=("_pkgdown.yml: kein destination-Eintrag; lokales pkgdown::build_site() baut nach docs/")
fi
for path in "${CONFLICTS[@]}"; do
  OPEN+=("Konflikt: $path existiert im Zielrepo mit anderem Inhalt und bleibt unverändert; Harness-Fassung: $TEMPLATE_ROOT/$path")
done

# 6. Bericht.
echo "install-into: Ziel $TARGET$([ "$DRY_RUN" = 1 ] && echo ' (Probelauf, nichts geändert)')"
echo "install-into: neu ${#COPIED[@]}, unverändert ${#UNCHANGED[@]}, Konflikte ${#CONFLICTS[@]}, Ausführungsrechte nachgetragen ${#EXEC_FIXED[@]}"
for item in "${MERGED[@]}"; do echo "install-into: zusammengeführt $item"; done
[ "$R_PACKAGE" = 1 ] && echo "install-into: R-Paket erkannt; Preset projektierung/presets/r-paket/PRESET.md"
if [ "${#OPEN[@]}" -gt 0 ]; then
  echo "install-into: offene Punkte:"
  for item in "${OPEN[@]}"; do echo "  - $item"; done
  if printf '%s\n' "${OPEN[@]}" | grep -q 'docs/\|pkgdown\|_pkgdown'; then
    cat <<'EOF'
install-into: Lösung für docs/ und pkgdown (Preset r-paket, Abschnitt pkgdown):
  - .gitignore: Zeile docs/ entfernen, pkgdown-site/ ergänzen
  - .Rbuildignore: ^pkgdown-site$ ergänzen, ^docs$ bleibt
  - Workflow: pkgdown::build_site_github_pages(dest_dir = "pkgdown-site", ...) und folder: pkgdown-site
  - _pkgdown.yml: destination: pkgdown-site
  - danach die nur kopierten Dateien eintragen: git add docs/
  - Prüfung: git check-ignore docs/00-vision.md bleibt leer
EOF
  fi
fi
echo "install-into: weiter mit git status, git diff --cached --stat, danach bash bootstrap.sh --no-start --non-interactive"
[ "${#OPEN[@]}" -eq 0 ] || exit 3
