#!/usr/bin/env bash
# Deklarative Toolchain-Installation/-Prüfung nach Vertrag v1.
set -uo pipefail

cd "$(dirname "$0")/../.."
REPO_ROOT="$PWD"
TOOLCHAIN_FILE="${TOOLCHAIN_FILE:-$REPO_ROOT/toolchain.json}"
[ -f "$TOOLCHAIN_FILE" ] || TOOLCHAIN_FILE="$REPO_ROOT/toolchain.json.example"

command -v jq >/dev/null 2>&1 || { echo "toolchain: jq fehlt" >&2; exit 2; }
jq -e '
  .contract==1 and (.runtimes|type=="array") and (.manifests|type=="array") and
  all(.runtimes[];
    (.name|type=="string" and length>0) and
    (.command|type=="string" and length>0) and
    (.versionCommand|type=="string" and length>0) and
    (.versionRegex|type=="string" and length>0) and
    ((.installCommand // "")|type=="string") and
    ((.updateCommand // "")|type=="string")) and
  all(.manifests[];
    (.path|type=="string" and length>0) and
    (.installCommand|type=="string" and length>0) and
    ((.updateCommand // "")|type=="string"))
' "$TOOLCHAIN_FILE" >/dev/null || { echo "toolchain: ungültiger Vertrag: $TOOLCHAIN_FILE" >&2; exit 2; }

safe_relative_path() {
  case "$1" in ''|/*|*..*) return 1 ;; *) return 0 ;; esac
}

runtime_ok() {
  local row="$1" command_name version_cmd version_regex output
  command_name="$(jq -r '.command' <<<"$row")"
  version_cmd="$(jq -r '.versionCommand' <<<"$row")"
  version_regex="$(jq -r '.versionRegex' <<<"$row")"
  command -v "$command_name" >/dev/null 2>&1 || return 1
  output="$(bash -c "$version_cmd" 2>&1)" || return 1
  grep -Eq -- "$version_regex" <<<"$output"
}

verify_all() {
  local row name path failed=0 output
  while IFS= read -r row; do
    name="$(jq -r '.name' <<<"$row")"
    if runtime_ok "$row"; then
      output="$(bash -c "$(jq -r '.versionCommand' <<<"$row")" 2>&1 | head -n 1)"
      echo "toolchain: runtime $name ok — $output"
    else
      echo "toolchain: runtime $name fehlt oder Version weicht ab" >&2
      failed=1
    fi
  done < <(jq -c '.runtimes[]' "$TOOLCHAIN_FILE")

  while IFS= read -r row; do
    path="$(jq -r '.path' <<<"$row")"
    if ! safe_relative_path "$path" || [ ! -f "$REPO_ROOT/$path" ]; then
      echo "toolchain: Manifest fehlt/unsicher: $path" >&2
      failed=1
    else
      echo "toolchain: manifest $path vorhanden"
    fi
  done < <(jq -c '.manifests[]' "$TOOLCHAIN_FILE")
  [ "$failed" = 0 ]
}

install_all() {
  local update="$1" row name command_to_run path
  while IFS= read -r row; do
    name="$(jq -r '.name' <<<"$row")"
    if [ "$update" = 0 ] && runtime_ok "$row"; then
      echo "toolchain: runtime $name bereits passend"
      continue
    fi
    if [ "$update" = 1 ]; then
      command_to_run="$(jq -r 'if ((.updateCommand // "")|length)>0 then .updateCommand else (.installCommand // "") end' <<<"$row")"
    else
      command_to_run="$(jq -r '.installCommand // ""' <<<"$row")"
    fi
    [ -n "$command_to_run" ] || { echo "toolchain: kein Installationskommando für $name" >&2; return 2; }
    echo "toolchain: installiere/aktualisiere runtime $name"
    bash -c "$command_to_run" || return 2
  done < <(jq -c '.runtimes[]' "$TOOLCHAIN_FILE")

  while IFS= read -r row; do
    path="$(jq -r '.path' <<<"$row")"
    safe_relative_path "$path" && [ -f "$REPO_ROOT/$path" ] \
      || { echo "toolchain: Manifest fehlt/unsicher: $path" >&2; return 2; }
    if [ "$update" = 1 ]; then
      command_to_run="$(jq -r 'if ((.updateCommand // "")|length)>0 then .updateCommand else .installCommand end' <<<"$row")"
    else
      command_to_run="$(jq -r '.installCommand' <<<"$row")"
    fi
    echo "toolchain: installiere frozen aus $path"
    bash -c "$command_to_run" || return 2
  done < <(jq -c '.manifests[]' "$TOOLCHAIN_FILE")
  verify_all
}

versions_json() {
  local result='{}' row name output
  while IFS= read -r row; do
    name="$(jq -r '.name' <<<"$row")"
    if runtime_ok "$row"; then
      output="$(bash -c "$(jq -r '.versionCommand' <<<"$row")" 2>&1 | head -n 1)"
    else
      output="missing-or-mismatch"
    fi
    result="$(jq -c --arg name "$name" --arg value "$output" '. + {($name):$value}' <<<"$result")"
  done < <(jq -c '.runtimes[]' "$TOOLCHAIN_FILE")
  printf '%s\n' "$result"
}

case "${1:-verify}" in
  verify) verify_all ;;
  install) install_all 0 ;;
  update) install_all 1 ;;
  versions-json) versions_json ;;
  *) echo "Aufruf: $0 verify|install|update|versions-json" >&2; exit 2 ;;
esac
