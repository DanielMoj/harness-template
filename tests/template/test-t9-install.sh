#!/usr/bin/env bash
# T-9: tools/install-into.sh setzt das Harness in bestehende Repos ein, ohne Projektdateien
# zu überschreiben, und trägt ausführbare Dateien auch bei core.filemode=false mit 100755 ein.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

CASE_ROOT="$(new_case_root)"
trap 'cleanup_case "$CASE_ROOT"' EXIT

TEMPLATE="$CASE_ROOT/template"
materialize_tree "$TEMPLATE"
init_fixture_repo "$TEMPLATE"
INSTALL="$TEMPLATE/tools/install-into.sh"

# Bestehendes R-Paket mit eigener Identität, docs/ in .gitignore und pkgdown nach docs/.
PKG="$CASE_ROOT/paket"
mkdir -p "$PKG/R" "$PKG/.github/workflows"
printf '# eigenes Paket\n' > "$PKG/README.md"
printf 'MIT License, Projekt\n' > "$PKG/LICENSE"
printf '# MIT License (Projekt)\n' > "$PKG/LICENSE.md"
printf 'cff-version: 1.2.0\ntitle: eigenes Paket\n' > "$PKG/CITATION.cff"
printf '{"title": "eigenes Paket"}\n' > "$PKG/.zenodo.json"
printf '# Eigene Agentenregeln des Projekts\n' > "$PKG/AGENTS.md"
printf 'Package: eigenespaket\nVersion: 0.1.0\n' > "$PKG/DESCRIPTION"
printf 'export(f)\n' > "$PKG/NAMESPACE"
printf 'f <- function() 1\n' > "$PKG/R/f.R"
printf '.Rhistory\ndocs/\n*.tar.gz\n' > "$PKG/.gitignore"
printf '*.rda binary\n' > "$PKG/.gitattributes"
printf '^docs$\n^\\.github$\n' > "$PKG/.Rbuildignore"
printf 'url: https://example.org/eigenespaket/\n' > "$PKG/_pkgdown.yml"
cat > "$PKG/.github/workflows/pkgdown.yaml" <<'EOF'
jobs:
  pkgdown:
    steps:
      - name: Build site
        run: pkgdown::build_site_github_pages(new_process = FALSE, install = FALSE)
        shell: Rscript {0}
      - name: Deploy to GitHub pages
        uses: JamesIves/github-pages-deploy-action@v4.5.0
        with:
          branch: gh-pages
          folder: docs
EOF
init_fixture_repo "$PKG"
git -C "$PKG" config core.filemode false
mkdir -p "$CASE_ROOT/originals"
for file in README.md LICENSE LICENSE.md CITATION.cff .zenodo.json AGENTS.md .gitignore .gitattributes .Rbuildignore; do
  cp "$PKG/$file" "$CASE_ROOT/originals/$file"
done
printf '# Quellenkatalog (Fixture)\n' > "$CASE_ROOT/KATALOG.md"

# Probelauf ändert nichts.
set +e
bash "$INSTALL" --dry-run --katalog "$CASE_ROOT/KATALOG.md" "$PKG" > "$CASE_ROOT/dry.log" 2>&1
dry_rc=$?
set -e
[ "$dry_rc" = 3 ]
grep -F 'Probelauf, nichts geändert' "$CASE_ROOT/dry.log" >/dev/null
test -z "$(git -C "$PKG" status --porcelain --untracked-files=all)"
test ! -e "$PKG/orchestrator"

set +e
bash "$INSTALL" --katalog "$CASE_ROOT/KATALOG.md" "$PKG" > "$CASE_ROOT/install.log" 2>&1
install_rc=$?
set -e
[ "$install_rc" = 3 ] || { cat "$CASE_ROOT/install.log" >&2; echo "T-9 FAIL: rc=$install_rc" >&2; exit 1; }
for file in README.md LICENSE LICENSE.md CITATION.cff .zenodo.json AGENTS.md; do
  cmp -s "$CASE_ROOT/originals/$file" "$PKG/$file" || { echo "T-9 FAIL: $file verändert" >&2; exit 1; }
done
grep -F 'Konflikt: AGENTS.md existiert im Zielrepo mit anderem Inhalt' "$CASE_ROOT/install.log" >/dev/null
# Zusammengeführt: alte Zeilen bleiben, Harness-Zeilen kommen als Block dazu.
head -n "$(wc -l < "$CASE_ROOT/originals/.gitignore")" "$PKG/.gitignore" | cmp -s - "$CASE_ROOT/originals/.gitignore"
grep -Fx 'reference/quellen/' "$PKG/.gitignore" >/dev/null
grep -Fx 'orchestrator/secrets.env' "$PKG/.gitignore" >/dev/null
grep -Fx '*.tar.gz' "$PKG/.gitignore" >/dev/null
test "$(grep -cFx 'docs/' "$PKG/.gitignore")" = 1
git -C "$PKG" check-ignore -q reference/quellen/text/probe.txt
grep -Fx '*.rda binary' "$PKG/.gitattributes" >/dev/null
grep -Fx '*.sh text eol=lf' "$PKG/.gitattributes" >/dev/null
for pattern in '^orchestrator$' '^projektierung$' '^reference$' '^contracts$' '^tests/acceptance$' \
    '^tests/e2e$' '^tests/fuzz$' '^AGENTS\.md$' '^CLAUDE\.md$' '^BACKLOG\.md$' '^PROGRESS\.md$' \
    '^STATUS\.md$' '^RUNBOOK\.md$' '^IMPLEMENTATION-RULES\.md$' '^bootstrap\.sh$' '^start\.sh$' \
    '^config\.env\.example$' '^toolchain\.json'; do
  grep -Fx -- "$pattern" "$PKG/.Rbuildignore" >/dev/null || { echo "T-9 FAIL: .Rbuildignore ohne $pattern" >&2; exit 1; }
done
test "$(grep -cFx '^docs$' "$PKG/.Rbuildignore")" = 1
# Katalog versioniert, Template-Interna nicht kopiert.
git -C "$PKG" ls-files --error-unmatch reference/QUELLENKATALOG.md >/dev/null
test ! -e "$PKG/tests/template" && test ! -e "$PKG/docs/template" && test ! -e "$PKG/tools/install-into.sh"
grep -Fx '_Noch keine Einträge._' "$PKG/PROGRESS.md" >/dev/null
# docs/ ist ignoriert: Dateien liegen da, sind aber nicht eingetragen; der Bericht nennt die Lösung.
test -f "$PKG/docs/decisions/ADR-000-vorlage.md"
! git -C "$PKG" ls-files --error-unmatch docs/decisions/ADR-000-vorlage.md >/dev/null 2>&1
grep -F 'docs/ ist im Zielrepo ignoriert' "$CASE_ROOT/install.log" >/dev/null
grep -F '.github/workflows/pkgdown.yaml: pkgdown baut mit build_site_github_pages() nach docs/' "$CASE_ROOT/install.log" >/dev/null
grep -F '.github/workflows/pkgdown.yaml: Deploy-Schritt veröffentlicht folder: docs' "$CASE_ROOT/install.log" >/dev/null
grep -F '_pkgdown.yml: kein destination-Eintrag' "$CASE_ROOT/install.log" >/dev/null
grep -F 'build_site_github_pages(dest_dir = "pkgdown-site", ...)' "$CASE_ROOT/install.log" >/dev/null

# Ausführungsrechte: jede 100755-Datei des Templates steht mit 100755 im Index des Ziels.
checked=0
while IFS= read -r -d '' record; do
  mode="${record%% *}"
  path="${record#*$'\t'}"
  [ "$mode" = 100755 ] || continue
  case "$path" in tests/template/*|tools/*|docs/template/*) continue ;; esac
  actual="$(git -C "$PKG" ls-files -s -- "$path" | awk '{print $1}')"
  [ "$actual" = 100755 ] || { echo "T-9 FAIL: $path hat Modus '${actual:-fehlt}'" >&2; exit 1; }
  checked=$((checked+1))
done < <(git -C "$TEMPLATE" ls-files -s -z)
[ "$checked" -ge 10 ]
git -C "$PKG" ls-files -s orchestrator/orchestrate.sh orchestrator/status.sh orchestrator/notify.sh \
  orchestrator/lib/toolchain.sh orchestrator/lib/r-check.sh > "$CASE_ROOT/modes.txt"
! grep -v '^100755 ' "$CASE_ROOT/modes.txt"
# Gegenprobe: ein gewöhnliches git add landet bei core.filemode=false als 100644.
CONTROL="$CASE_ROOT/control"
mkdir -p "$CONTROL"
git -C "$CONTROL" init -q -b main
git -C "$CONTROL" config core.filemode false
printf '#!/usr/bin/env bash\necho probe\n' > "$CONTROL/probe.sh"
chmod +x "$CONTROL/probe.sh"
git -C "$CONTROL" add probe.sh
control_mode="$(git -C "$CONTROL" ls-files -s probe.sh | awk '{print $1}')"
[ "$control_mode" = 100644 ]

# Nach dem Betreiber-Commit sind die Skripte in einem frischen Klon ausführbar.
git -C "$PKG" commit -qm 'harness: einsetzen'
git clone -q "$PKG" "$CASE_ROOT/klon"
for script in orchestrator/orchestrate.sh orchestrator/status.sh orchestrator/notify.sh \
    orchestrator/lib/toolchain.sh orchestrator/verifier.sh bootstrap.sh start.sh; do
  test -x "$CASE_ROOT/klon/$script" || { echo "T-9 FAIL: $script im Klon nicht ausführbar" >&2; exit 1; }
done

# Wiederholung: nichts doppelt, gleiche offene Punkte.
set +e
bash "$INSTALL" --katalog "$CASE_ROOT/KATALOG.md" "$PKG" > "$CASE_ROOT/again.log" 2>&1
again_rc=$?
set -e
[ "$again_rc" = 3 ]
grep -F 'install-into: neu 0,' "$CASE_ROOT/again.log" >/dev/null
test "$(grep -cFx 'reference/quellen/' "$PKG/.gitignore")" = 1
test "$(grep -cFx '^orchestrator$' "$PKG/.Rbuildignore")" = 1
test -z "$(git -C "$PKG" status --porcelain)"

# Ein Repo ohne Konflikte: Exit 0, keine R-Einträge, Harness lauffähig eingetragen.
PLAIN="$CASE_ROOT/plain"
mkdir -p "$PLAIN"
printf '# anderes Projekt\n' > "$PLAIN/README.md"
init_fixture_repo "$PLAIN"
git -C "$PLAIN" config core.filemode false
bash "$INSTALL" "$PLAIN" > "$CASE_ROOT/plain.log" 2>&1
test ! -e "$PLAIN/.Rbuildignore"
git -C "$PLAIN" ls-files -s orchestrator/orchestrate.sh | grep -q '^100755 '
grep -Fx 'reference/quellen/' "$PLAIN/.gitignore" >/dev/null
test -z "$(git -C "$PLAIN" check-ignore docs/00-vision.md || true)"

# Zustandsfehler: nicht committete Änderungen verhindern das Einsetzen.
printf 'lokal geändert\n' >> "$PLAIN/README.md"
set +e
bash "$INSTALL" "$PLAIN" > "$CASE_ROOT/dirty.log" 2>&1
dirty_rc=$?
set -e
[ "$dirty_rc" = 2 ]
grep -F 'nicht committete Änderungen' "$CASE_ROOT/dirty.log" >/dev/null

printf 'T-9 evidence install: %s\n' "$(grep -m1 -F 'install-into: neu' "$CASE_ROOT/install.log")"
printf 'T-9 evidence modes: %s executables 100755, control git add -> %s\n' "$checked" "$control_mode"
printf 'T-9 evidence docs: %s\n' "$(grep -m1 -F 'docs/ ist im Zielrepo ignoriert' "$CASE_ROOT/install.log" | sed 's/^ *//')"
echo 'T-9 PASS: project-files=untouched merge=gitignore,gitattributes,Rbuildignore quellen=ignored katalog=versioned exec-bits=100755(filemode=false) fresh-clone=executable docs-conflict=reported dry-run=no-change idempotent=yes dirty=FATAL'
