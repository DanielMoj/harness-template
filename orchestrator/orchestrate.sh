#!/usr/bin/env bash
# Generischer Drei-Rollen-Orchestrator — Vertrag: contracts/PROTOCOLS.md
set -Eeuo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
ORCH="$REPO_ROOT/orchestrator"
CONFIG="$ORCH/config.env"
MILESTONES="$ORCH/milestones.json"
mkdir -p "$ORCH/logs" "$ORCH/state" "$ORCH/handoff"

if [ ! -f "$CONFIG" ]; then
  echo "FATAL: $CONFIG fehlt; zuerst bootstrap.sh ausführen und Rollen konfigurieren." >&2
  exit 2
fi

# shellcheck disable=SC1090
source "$CONFIG"

TS() { date +%Y%m%d-%H%M%S; }
log() { printf '[%s] %s\n' "$(TS)" "$*" | tee -a "$ORCH/logs/orchestrate.log"; }

CURRENT_MS=""
CURRENT_PHASE="preflight"
LOCK_HELD=0
PARKED_LIST=""
HALT_REQUESTED=0
PHASE_COUNT=0
OWNERSHIP_SNAPSHOT=""
ACTIVE_MODEL_LOG=""
declare -A OWNERSHIP_BEFORE=()
declare -A OWNERSHIP_ARTIFACT_BEFORE=()
declare -a OWNERSHIP_REMOVE=()
declare -a MODEL_ENV=()
VERDICT_VALUE=""

# Neue Werte werden nur als Defaults gesetzt; config.env gewinnt einzeln.
AUTONOMY_LEVEL="${AUTONOMY_LEVEL:-2}"
case "$AUTONOMY_LEVEL" in
  0)
    : "${MAX_MS_PER_RUN:=1}"; : "${LADDER_ENABLED:=0}"
    : "${NOTIFY_ENABLED:=0}"; PHASES_PER_RUN=1
    ;;
  1)
    : "${MAX_MS_PER_RUN:=1}"; : "${LADDER_ENABLED:=0}"
    : "${NOTIFY_ENABLED:=0}"; PHASES_PER_RUN=999999
    ;;
  2)
    : "${MAX_MS_PER_RUN:=4}"; : "${LADDER_ENABLED:=1}"
    : "${NOTIFY_ENABLED:=1}"; PHASES_PER_RUN=999999
    ;;
  3)
    : "${MAX_MS_PER_RUN:=999}"; : "${LADDER_ENABLED:=1}"
    : "${NOTIFY_ENABLED:=1}"; PHASES_PER_RUN=999999
    ;;
  *) echo "FATAL: AUTONOMY_LEVEL muss 0, 1, 2 oder 3 sein." >&2; exit 2 ;;
esac

PHASE_TIMEOUT="${PHASE_TIMEOUT:-3600}"
MAX_ROUNDS_PLAN="${MAX_ROUNDS_PLAN:-2}"
MAX_ROUNDS_REWORK="${MAX_ROUNDS_REWORK:-8}"
REBUILD_ROUND="${REBUILD_ROUND:-4}"
ARBITER_EXTRA_ROUNDS="${ARBITER_EXTRA_ROUNDS:-2}"
RETRY_MAX="${RETRY_MAX:-2}"
RETRY_SLEEP="${RETRY_SLEEP:-120}"
GATE_ERROR_RETRIES="${GATE_ERROR_RETRIES:-2}"
QA_REQUIRED_FROM="${QA_REQUIRED_FROM-M3}"
QA_ENABLED="${QA_ENABLED:-$([ -n "${QA_CMD:-}" ] && echo 1 || echo 0)}"
QA_PROBE_STRICT="${QA_PROBE_STRICT:-1}"
QA_PROBE_RETRIES="${QA_PROBE_RETRIES:-3}"
QA_PROBE_TIMEOUT="${QA_PROBE_TIMEOUT:-180}"
QA_PROBE_SLEEP="${QA_PROBE_SLEEP:-300}"
REBUILD_PATHS="${REBUILD_PATHS:-src tools tests/unit tests/properties}"
ROLE_GUARDS="${ROLE_GUARDS:-on}"
ARTIFACT_ALLOWLIST="$ORCH/artifact-paths.allowlist"

notify_event() {
  "$ORCH/notify.sh" "$@" >> "$ORCH/logs/orchestrate.log" 2>&1 || true
}

refresh_status() {
  local reason="${1:-}" exit_code="${2:-null}" needs="${3:-false}"
  STATUS_NEEDS_HUMAN="$needs" \
    "$ORCH/status.sh" "$CURRENT_MS" "$CURRENT_PHASE" "$reason" "$exit_code" \
    >/dev/null 2>&1 || true
}

fatal() {
  local reason="$*"
  log "FATAL: $reason"
  CURRENT_PHASE="fatal"
  refresh_status "$reason" 2 true
  notify_event FATAL "$reason"
  exit 2
}

release_lock() {
  if [ -n "$OWNERSHIP_SNAPSHOT" ] && [ -d "$OWNERSHIP_SNAPSHOT" ]; then
    rm -rf -- "$OWNERSHIP_SNAPSHOT"
    OWNERSHIP_SNAPSHOT=""
  fi
  [ "$LOCK_HELD" = 1 ] || return 0
  if [ -f "$ORCH/.lock/pid" ] && [ "$(cat "$ORCH/.lock/pid" 2>/dev/null)" = "$$" ]; then
    rm -f "$ORCH/.lock/pid"
    rmdir "$ORCH/.lock" 2>/dev/null || true
  fi
  LOCK_HELD=0
}
trap release_lock EXIT INT TERM

acquire_lock() {
  local lock="$ORCH/.lock" candidate oldpid="" foreign=""
  while :; do
    candidate="$(mktemp -d "$ORCH/.lock-candidate.XXXXXX")" \
      || fatal "Lock-Kandidat kann nicht angelegt werden."
    printf '%s\n' "$$" > "$candidate/pid" \
      || { rm -rf -- "$candidate"; fatal "PID kann nicht in Lock-Kandidat geschrieben werden."; }
    if mv -T -- "$candidate" "$lock" 2>/dev/null; then
      LOCK_HELD=1
      return 0
    fi
    rm -rf -- "$candidate"
    [ -d "$lock" ] || continue

    oldpid="$(cat "$lock/pid" 2>/dev/null || true)"
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
      printf 'FATAL: Orchestrator läuft bereits (PID %s).\n' "$oldpid" >&2
      exit 2
    fi
    foreign="$(find "$lock" -mindepth 1 -maxdepth 1 ! -name pid -print -quit 2>/dev/null || true)"
    if [ -n "$foreign" ]; then
      fatal "verwaister Lock enthält Fremdinhalt: $foreign. Aufräumen: PID prüfen, dann gezielt '$lock' entfernen."
    fi
    log "WARN: verwaister Lock (PID ${oldpid:-unbekannt}) — wird atomar übernommen"
    rm -f -- "$lock/pid" || fatal "verwaiste Lock-PID kann nicht entfernt werden: $lock/pid"
    rmdir -- "$lock" 2>/dev/null || continue
  done
}

stop_check() {
  [ ! -f "$ORCH/STOP" ] || fatal "STOP-Datei gefunden — vor der nächsten Phase angehalten."
}

require_uint() {
  local name="$1" value="$2"
  case "$value" in ''|*[!0-9]*) fatal "$name muss eine nichtnegative Ganzzahl sein (ist '$value')." ;; esac
}

validate_manifest() {
  [ -f "$MILESTONES" ] || fatal "$MILESTONES fehlt; aus milestones.json.example erzeugen."
  jq -e '
    type=="array" and length>0 and
    all(.[];
      (.id|type=="string" and test("^[A-Za-z][A-Za-z0-9_-]*$")) and
      (.title|type=="string" and length>0) and
      (.criteriaRef|type=="array" and length>0 and all(.[]; type=="string" and test("^[A-Za-z0-9._-]+$"))) and
      ((has("deps")|not) or (.deps|type=="array" and all(.[]; type=="string"))) and
      (.effort=="low" or .effort=="high" or .effort=="max")
    ) and
    ([.[].id] | length == (unique|length)) and
    ([.[] | .deps[]?] - [.[].id] | length==0) and
    all(.[]; (.id as $id | all(.deps[]?; . != $id)))
  ' "$MILESTONES" >/dev/null || fatal "Meilensteinmanifest verletzt contracts/PROTOCOLS.md §2."
  jq -e '
    . as $manifest
    | def acyclic($id; $seen):
        if ($seen | index($id)) != null then false
        else all(($manifest[] | select(.id==$id) | .deps[]?); acyclic(.; $seen + [$id]))
        end;
      all(.[]; .id as $id | acyclic($id; []))
  ' "$MILESTONES" >/dev/null || fatal "Meilensteinmanifest enthält einen deps-Zyklus."
}

expand_role_cmd() {
  local role="$1" cmd="$2" expanded remainder
  remainder="${cmd//\$\{PROMPT_FILE\}/}"
  remainder="${remainder//\$PROMPT_FILE/}"
  [[ "$remainder" != *'$'* ]] \
    || fatal "$role-CMD enthält eine nicht erlaubte \$-Referenz; nur \$PROMPT_FILE ist zulässig."
  expanded="${cmd//\$\{PROMPT_FILE\}/\/tmp\/harness-prompt.md}"
  expanded="${expanded//\$PROMPT_FILE/\/tmp\/harness-prompt.md}"
  EXPANDED_ROLE_CMD="$expanded"
}

validate_role_cli() {
  local role="$1" cmd="$2" help_cmd="$3" required="$4" safe_pattern="$5"
  [ -n "$cmd" ] || fatal "$role-CMD ist leer."
  [ -n "$help_cmd" ] || fatal "$role-HELP_CMD ist leer."
  local help_out expanded
  if ! help_out="$(bash -c "$help_cmd" 2>&1)"; then
    fatal "$role: reales --help-Kommando fehlgeschlagen: $help_cmd"
  fi
  expand_role_cmd "$role" "$cmd"
  expanded="$EXPANDED_ROLE_CMD"
  if [ "$ROLE_GUARDS" = off ]; then
    return 0
  fi
  [ -n "$required" ] || fatal "$role-REQUIRED_FLAGS ist leer; nur ROLE_GUARDS=off darf Rollenwächter abschalten."
  [ -n "$safe_pattern" ] || fatal "$role-SAFE_MODE_PATTERN ist leer; nur ROLE_GUARDS=off darf Rollenwächter abschalten."
  local flag
  for flag in $required; do
    grep -Fq -- "$flag" <<<"$help_out" || fatal "$role: Flag '$flag' fehlt im echten --help."
  done
  grep -Eq -- "$safe_pattern" <<<"$expanded" \
    || fatal "$role: konfigurierter Sandbox-/Permission-Modus fehlt."
}

require_contract_paths() {
  local path
  for path in \
    prompts/10-acceptance.md prompts/20-plan.md prompts/30-plan-review.md \
    prompts/40-build.md prompts/45-qa.md prompts/50-code-review.md \
    prompts/60-rework.md prompts/62-rebuild.md prompts/70-arbiter.md \
    handoff/SCHEMA.md status.sh verifier.sh; do
    [ -f "$ORCH/$path" ] || fatal "Vertragspfad fehlt: orchestrator/$path"
  done
  for path in gates.d state; do
    [ -d "$ORCH/$path" ] || fatal "Vertragspfad fehlt: orchestrator/$path/"
  done
  [ -f "$REPO_ROOT/contracts/PROTOCOLS.md" ] || fatal "Vertragspfad fehlt: contracts/PROTOCOLS.md"
  [ -d "$REPO_ROOT/reference/anchors" ] || fatal "Vertragspfad fehlt: reference/anchors/"
  [ -f "$ARTIFACT_ALLOWLIST" ] || fatal "Vertragspfad fehlt: orchestrator/artifact-paths.allowlist"
}

preflight() {
  command -v git >/dev/null 2>&1 || fatal "git fehlt"
  command -v jq >/dev/null 2>&1 || fatal "jq fehlt"
  command -v bash >/dev/null 2>&1 || fatal "bash fehlt"
  validate_manifest
  require_contract_paths

  [ -n "$(git config user.name 2>/dev/null || true)" ] \
    || fatal "git user.name fehlt; vor dem Lauf mit 'git config user.name <Name>' setzen."
  [ -n "$(git config user.email 2>/dev/null || true)" ] \
    || fatal "git user.email fehlt; vor dem Lauf mit 'git config user.email <Adresse>' setzen."

  require_uint PHASE_TIMEOUT "$PHASE_TIMEOUT"
  require_uint MAX_ROUNDS_PLAN "$MAX_ROUNDS_PLAN"
  require_uint MAX_ROUNDS_REWORK "$MAX_ROUNDS_REWORK"
  require_uint REBUILD_ROUND "$REBUILD_ROUND"
  require_uint RETRY_MAX "$RETRY_MAX"
  require_uint GATE_ERROR_RETRIES "$GATE_ERROR_RETRIES"
  require_uint MAX_MS_PER_RUN "$MAX_MS_PER_RUN"

  case "$ROLE_GUARDS" in on|off) ;; *) fatal "ROLE_GUARDS muss on oder off sein." ;; esac
  if [ -n "$QA_REQUIRED_FROM" ]; then
    jq -e --arg id "$QA_REQUIRED_FROM" 'any(.[]; .id==$id)' "$MILESTONES" >/dev/null \
      || fatal "QA_REQUIRED_FROM ist keine Meilenstein-ID des Manifests: $QA_REQUIRED_FROM"
  fi

  local builder_expanded reviewer_expanded qa_expanded="" all_cmds
  expand_role_cmd BUILDER "${BUILDER_CMD:-}"
  builder_expanded="$EXPANDED_ROLE_CMD"
  expand_role_cmd REVIEWER "${REVIEWER_CMD:-}"
  reviewer_expanded="$EXPANDED_ROLE_CMD"
  if [ "$QA_ENABLED" = 1 ]; then
    expand_role_cmd QA "${QA_CMD:-}"
    qa_expanded="$EXPANDED_ROLE_CMD"
  fi
  all_cmds="$builder_expanded $reviewer_expanded $qa_expanded"
  # Resume: Flags und Unterkommandos wie "codex exec resume|fork".
  local banned
  banned="$(grep -Eoi -- '--continue|--resume|--session([ =]|$)|--session-file|(^|[[:space:]])(resume|fork)([[:space:]]|$)' <<<"$all_cmds" | head -n 1 || true)"
  [ -z "$banned" ] \
    || fatal "Resume-/Session-Flags sind verboten; jede Phase ist eine frische Session: ${banned# }"
  # Bypass, Full Access, Yolo und Klassifikator-Freigaben (auto); auto_edit und auto-edit bleiben erlaubt.
  banned="$(grep -Eoi -- 'dangerously[-_ ]?(skip|bypass|disable)[[:alnum:]_-]*|bypassPermissions|--yolo|full[-_ ]?access|--approve-for-me|--approval-mode[[:space:]=]+[^[:alnum:]]?(yolo|auto([^[:alnum:]_-]|$))|--permission-mode[[:space:]=]+[^[:alnum:]]?auto([^[:alnum:]_-]|$)' <<<"$all_cmds" | head -n 1 || true)"
  [ -z "$banned" ] \
    || fatal "gefährlicher Bypass-/Full-Access-/Auto-Freigabe-Modus in Rollenkommando gefunden: $banned"

  validate_role_cli BUILDER "${BUILDER_CMD:-}" "${BUILDER_HELP_CMD:-}" \
    "${BUILDER_REQUIRED_FLAGS:-}" "${BUILDER_SAFE_MODE_PATTERN:-}"
  validate_role_cli REVIEWER "${REVIEWER_CMD:-}" "${REVIEWER_HELP_CMD:-}" \
    "${REVIEWER_REQUIRED_FLAGS:-}" "${REVIEWER_SAFE_MODE_PATTERN:-}"
  if [ "$QA_ENABLED" = 1 ]; then
    validate_role_cli QA "${QA_CMD:-}" "${QA_HELP_CMD:-}" \
      "${QA_REQUIRED_FLAGS:-}" "${QA_SAFE_MODE_PATTERN:-}"
  fi

  if [ -x "$ORCH/lib/toolchain.sh" ]; then
    "$ORCH/lib/toolchain.sh" verify || fatal "Toolchain-Versionen stimmen nicht."
  fi

  local dirty
  dirty="$(git status --porcelain --untracked-files=all | awk '{print substr($0,4)}' \
    | grep -vE '^(STATUS\.md|orchestrator/STOP|orchestrator/state/summary\.json|orchestrator/\.lock(/.*)?)$' || true)"
  [ -z "$dirty" ] || fatal "Arbeitsbaum vor Lauf nicht sauber: $dirty"

  CURRENT_PHASE=preflight
  refresh_status
  log "CONFIG: AUTONOMY=$AUTONOMY_LEVEL PLAN<=$MAX_ROUNDS_PLAN REWORK<=$MAX_ROUNDS_REWORK REBUILD@r$REBUILD_ROUND ARBITER+$ARBITER_EXTRA_ROUNDS TIMEOUT=$PHASE_TIMEOUT RETRY=${RETRY_MAX}x/${RETRY_SLEEP}s GATE_ERROR_RETRIES=$GATE_ERROR_RETRIES MAX_MS=$MAX_MS_PER_RUN QA=$QA_ENABLED(ab ${QA_REQUIRED_FROM:-nie}) ROLE_GUARDS=$([ "$ROLE_GUARDS" = off ] && echo OFF || echo on) NOTIFY=$([ "$NOTIFY_ENABLED" = 1 ] && [ -n "${NOTIFY_URL:-}" ] && echo an || echo aus) BUILDER=${BUILDER_CMD%% *} REVIEWER=${REVIEWER_CMD%% *}"

  if [ "$QA_ENABLED" = 1 ] && [ "$QA_PROBE_STRICT" = 1 ]; then
    local attempt=1 probe_file probe_log probe_out rc
    while [ "$attempt" -le "$QA_PROBE_RETRIES" ]; do
      probe_file="$ORCH/logs/qa-probe-$(TS)-$attempt.md"
      probe_log="${probe_file%.md}.log"
      printf '%s\n' "Antworte nur: OK" > "$probe_file"
      build_model_env QA "$probe_file"
      if command -v timeout >/dev/null 2>&1; then
        if probe_out="$(timeout "$QA_PROBE_TIMEOUT" env -i "${MODEL_ENV[@]}" bash -c "$QA_CMD" 2>&1)"; then rc=0; else rc=$?; fi
      else
        if probe_out="$(env -i "${MODEL_ENV[@]}" bash -c "$QA_CMD" 2>&1)"; then rc=0; else rc=$?; fi
      fi
      # Die CLI-Ausgabe belegt die Ursache, etwa eine stille Rückstufung des Freigabemodus.
      printf '%s\n' "$probe_out" > "$probe_log"
      if [ "$rc" = 0 ] && grep -q 'OK' <<<"$probe_out"; then
        log "QA-Routenprobe bestanden (${QA_MODEL:-}); Ausgabe: ${probe_log#"$REPO_ROOT/"}"
        break
      fi
      log "WARN: QA-Routenprobe $attempt/$QA_PROBE_RETRIES fehlgeschlagen (rc=$rc); Ausgabe: ${probe_log#"$REPO_ROOT/"}"
      [ "$attempt" -ge "$QA_PROBE_RETRIES" ] && fatal "QA-Routenprobe strict fehlgeschlagen."
      sleep "$QA_PROBE_SLEEP"
      attempt=$((attempt+1))
    done
  fi
}

render_prompt() {
  local prompt="$1" ms="$2" round="$3" dispute_phase="${4:-code}" criteria
  criteria="$(jq -er --arg id "$ms" '.[] | select(.id==$id) | .criteriaRef | join(" ")' "$MILESTONES")" \
    || return 1
  sed \
    -e "s#{{MS}}#$ms#g" \
    -e "s#{{ROUND}}#$round#g" \
    -e "s#{{CRITERIA}}#$criteria#g" \
    -e "s#{{DISPUTE_PHASE}}#$dispute_phase#g" \
    "$ORCH/prompts/$prompt" \
    || return 1
  printf '\n%s\n' "Git-Hinweis: Der Orchestrator committet nach der Territoriumsprüfung. Führe selbst keine Git-Kommandos aus."
}

transport_error() {
  local rc="$1" log_file="$2"
  case "$rc" in 124|137) return 0 ;; esac
  tail -c 4000 "$log_file" 2>/dev/null | grep -Eqi \
    'rate[ -]?limit|too many requests|status(:| code)? 5[0-9][0-9]|HTTP/[0-9.]+ 5[0-9][0-9]|502 Bad Gateway|503|504|overloaded|ECONNRESET|ECONNREFUSED|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|socket hang ?up|quota|temporar(il)?y unavailable|connection (reset|closed|refused)'
}

rollback_attempt() {
  local base="$1"
  git reset --hard "$base" -q || fatal "Rollback auf $base fehlgeschlagen."
  git clean -qfd -e config.env -e secrets.env -e toolchain.json -e orchestrator/logs/ -e orchestrator/.lock/ \
    || fatal "Bereinigung nach Modellversuch fehlgeschlagen."
}

path_fingerprint() {
  local path="$1"
  if [ -L "$path" ]; then
    printf 'link:%s:%s\n' "$(stat -c '%a' -- "$path")" "$(readlink -- "$path")"
  elif [ -f "$path" ]; then
    printf 'file:%s:%s\n' "$(stat -c '%a' -- "$path")" "$(sha256sum -- "$path" | awk '{print $1}')"
  elif [ -d "$path" ]; then
    printf 'dir:%s\n' "$(stat -c '%a' -- "$path")"
  else
    echo missing
  fi
}

artifact_path_allowed() {
  local path="$1"
  grep -Eq -f "$ARTIFACT_ALLOWLIST" <<<"$path"
}

all_untracked_paths() {
  git ls-files --others -z
}

changed_paths() {
  local path
  while IFS= read -r -d '' path; do
    case "$path" in orchestrator/logs/*) continue ;; esac
    artifact_path_allowed "$path" && continue
    printf '%s\0' "$path"
  done < <({ git diff --name-only -z HEAD; all_untracked_paths; } | sort -zu)
}

tree_manifest() {
  local root="$1" exclude="${2:-}" path rel
  [ -d "$root" ] || return 0
  while IFS= read -r -d '' path; do
    [ "$path" != "$exclude" ] || continue
    rel="${path#"$root"/}"
    printf '%s\t%s\n' "$rel" "$(path_fingerprint "$path")"
  done < <(find "$root" \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
}

snapshot_phase_logs() {
  local active="$1" backup="$OWNERSHIP_SNAPSHOT/protected-logs"
  rm -rf -- "$backup"
  mkdir -p "$backup"
  if [ -d "$ORCH/logs" ]; then
    cp -a "$ORCH/logs/." "$backup/"
  fi
  rm -f -- "$backup/${active#"$ORCH/logs/"}"
  tree_manifest "$backup" > "$OWNERSHIP_SNAPSHOT/protected-logs.sha256"
}

phase_logs_intact() {
  local current="$OWNERSHIP_SNAPSHOT/current-logs.sha256"
  tree_manifest "$ORCH/logs" "$ACTIVE_MODEL_LOG" > "$current"
  cmp -s "$OWNERSHIP_SNAPSHOT/protected-logs.sha256" "$current"
}

restore_phase_logs() {
  local backup="$OWNERSHIP_SNAPSHOT/protected-logs" saved="" rel=""
  [ -d "$backup" ] || return 0
  if [ -n "$ACTIVE_MODEL_LOG" ] && [ -f "$ACTIVE_MODEL_LOG" ]; then
    saved="$OWNERSHIP_SNAPSHOT/active-model.log"
    cp -a -- "$ACTIVE_MODEL_LOG" "$saved"
    rel="${ACTIVE_MODEL_LOG#"$ORCH/logs/"}"
  fi
  rm -rf -- "$ORCH/logs"
  mkdir -p "$ORCH/logs"
  cp -a "$backup/." "$ORCH/logs/"
  if [ -n "$saved" ]; then
    mkdir -p "$(dirname "$ACTIVE_MODEL_LOG")"
    cp -a -- "$saved" "$ACTIVE_MODEL_LOG"
  fi
}

snapshot_worktree() {
  local path
  [ -z "$OWNERSHIP_SNAPSHOT" ] || rm -rf -- "$OWNERSHIP_SNAPSHOT"
  OWNERSHIP_SNAPSHOT="$(mktemp -d /tmp/harness-model-baseline.XXXXXX)"
  mkdir -p "$OWNERSHIP_SNAPSHOT/files"
  OWNERSHIP_BEFORE=()
  OWNERSHIP_ARTIFACT_BEFORE=()
  OWNERSHIP_REMOVE=()
  while IFS= read -r -d '' path; do
    OWNERSHIP_BEFORE["$path"]="$(path_fingerprint "$path")"
    if [ -e "$path" ] || [ -L "$path" ]; then
      cp -a --parents -- "$path" "$OWNERSHIP_SNAPSHOT/files"
    fi
  done < <(changed_paths)
  while IFS= read -r -d '' path; do
    artifact_path_allowed "$path" || continue
    OWNERSHIP_ARTIFACT_BEFORE["$path"]=1
  done < <(all_untracked_paths)
  for path in orchestrator/config.env orchestrator/secrets.env toolchain.json; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    if [ -z "${OWNERSHIP_BEFORE[$path]+set}" ]; then
      OWNERSHIP_BEFORE["$path"]="$(path_fingerprint "$path")"
      cp -a --parents -- "$path" "$OWNERSHIP_SNAPSHOT/files"
    fi
  done
}

restore_worktree() {
  local base="$1" path saved
  rollback_attempt "$base"
  for path in "${OWNERSHIP_REMOVE[@]}"; do
    [ -n "$path" ] || continue
    rm -f -- "$path"
  done
  while IFS= read -r -d '' path; do
    artifact_path_allowed "$path" || continue
    [ -n "${OWNERSHIP_ARTIFACT_BEFORE[$path]+set}" ] || rm -f -- "$path"
  done < <(all_untracked_paths)
  for path in "${!OWNERSHIP_BEFORE[@]}"; do
    saved="$OWNERSHIP_SNAPSHOT/files/$path"
    if [ -e "$saved" ] || [ -L "$saved" ]; then
      mkdir -p "$(dirname "$path")"
      cp -a -- "$saved" "$path"
    else
      rm -f -- "$path"
    fi
  done
  restore_phase_logs
}

clear_worktree_snapshot() {
  [ -z "$OWNERSHIP_SNAPSHOT" ] || rm -rf -- "$OWNERSHIP_SNAPSHOT"
  OWNERSHIP_SNAPSHOT=""
  ACTIVE_MODEL_LOG=""
  OWNERSHIP_BEFORE=()
  OWNERSHIP_ARTIFACT_BEFORE=()
  OWNERSHIP_REMOVE=()
}

path_allowed() {
  local role="$1" phase="$2" ms="$3" path="$4"
  case "$role:$phase:$path" in
    reviewer:10-acceptance:tests/acceptance/*|reviewer:10-acceptance:reference/anchors/*|reviewer:10-acceptance:orchestrator/handoff/"$ms"/*) return 0 ;;
    builder:20-plan:orchestrator/handoff/"$ms"/*) return 0 ;;
    reviewer:30-plan-review:orchestrator/handoff/"$ms"/*|reviewer:30-plan-review:contracts/PROTOCOLS.md|reviewer:30-plan-review:IMPLEMENTATION-RULES.md|reviewer:30-plan-review:docs/decisions/*) return 0 ;;
    qa:45-qa:tests/e2e/*|qa:45-qa:tests/fuzz/*|qa:45-qa:orchestrator/handoff/"$ms"/QA.md|qa:45-qa:BACKLOG.md) return 0 ;;
    reviewer:50-code-review:orchestrator/handoff/"$ms"/*|reviewer:50-code-review:tests/acceptance/*|reviewer:50-code-review:reference/anchors/*|reviewer:50-code-review:BACKLOG.md|reviewer:50-code-review:IMPLEMENTATION-RULES.md|reviewer:50-code-review:contracts/PROTOCOLS.md|reviewer:50-code-review:docs/decisions/*) return 0 ;;
    reviewer:70-arbiter:orchestrator/handoff/"$ms"/*|reviewer:70-arbiter:docs/decisions/*) return 0 ;;
  esac

  if [ "$role" = builder ] && [[ "$phase" =~ ^(40-build|60-rework|62-rebuild)$ ]]; then
    case "$path" in
      src/*|tools/*|tests/unit/*|tests/properties/*|public/assets/*|contracts/api/*|PROGRESS.md|docs/decisions/*|orchestrator/handoff/"$ms"/REVIEW-INPUT.md|orchestrator/handoff/"$ms"/REWORK-NOTES.md|orchestrator/handoff/"$ms"/MUT-EQUIV.json) return 0 ;;
      package.json|pnpm-lock.yaml|package-lock.json|yarn.lock|pyproject.toml|poetry.lock|uv.lock|requirements.txt|requirements.lock|renv.lock) return 0 ;;
    esac
    if [ -n "${BUILDER_EXTRA_PATHS_REGEX:-}" ] && grep -Eq -- "$BUILDER_EXTRA_PATHS_REGEX" <<<"$path"; then
      return 0
    fi
  fi
  if [ "$role" = reviewer ] && [ -n "${REVIEWER_EXTRA_PATHS_REGEX:-}" ] \
      && grep -Eq -- "$REVIEWER_EXTRA_PATHS_REGEX" <<<"$path"; then
    return 0
  fi
  if [ "$role" = qa ] && [ -n "${QA_EXTRA_PATHS_REGEX:-}" ] \
      && grep -Eq -- "$QA_EXTRA_PATHS_REGEX" <<<"$path"; then
    return 0
  fi
  return 1
}

ownership_check() {
  local role="$1" phase="$2" ms="$3" round="$4" base="$5" config_hash="$6"
  local path before now
  declare -A candidates=()
  OWNERSHIP_BAD=""
  if [ "$(git rev-parse HEAD)" != "$base" ]; then
    OWNERSHIP_BAD="git history (Modelle dürfen nicht committen)"
    restore_worktree "$base"
    return 1
  fi
  if [ "$(sha256sum "$CONFIG" | awk '{print $1}')" != "$config_hash" ]; then
    OWNERSHIP_BAD="orchestrator/config.env"
    restore_worktree "$base"
    return 1
  fi
  if ! phase_logs_intact; then
    OWNERSHIP_BAD="orchestrator/logs/** (Hash-Manifest)"
    restore_worktree "$base"
    return 1
  fi

  for path in "${!OWNERSHIP_BEFORE[@]}"; do candidates["$path"]=1; done
  while IFS= read -r -d '' path; do candidates["$path"]=1; done < <(changed_paths)
  for path in "${!candidates[@]}"; do
    before="${OWNERSHIP_BEFORE[$path]:-__clean__}"
    now="$(path_fingerprint "$path")"
    [ "$before" != __clean__ ] && [ "$before" = "$now" ] && continue
    if ! path_allowed "$role" "$phase" "$ms" "$path"; then
      OWNERSHIP_BAD="${OWNERSHIP_BAD}${OWNERSHIP_BAD:+ }$path"
      [ "$before" != __clean__ ] || OWNERSHIP_REMOVE+=("$path")
    fi
  done

  if [ -n "$OWNERSHIP_BAD" ]; then
    restore_worktree "$base"
    return 1
  fi
  clear_worktree_snapshot
  mkdir -p "$ORCH/state/$ms"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date --iso-8601=seconds)" "$role" "$phase" "$round" "$base" \
    > "$ORCH/state/$ms/territory-ok"
  return 0
}

build_model_env() {
  local role="$1" prompt="$2" names="" name value
  MODEL_ENV=(
    "PROMPT_FILE=$prompt"
    "PATH=${PATH:-/usr/local/bin:/usr/bin:/bin}"
    "HOME=${HOME:-/tmp}"
    "LANG=${LANG:-C.UTF-8}"
  )
  case "$role" in
    BUILDER|builder) names="${BUILDER_ENV_ALLOWLIST:-}" ;;
    REVIEWER|reviewer) names="${REVIEWER_ENV_ALLOWLIST:-}" ;;
    QA|qa) names="${QA_ENV_ALLOWLIST:-}" ;;
    *) fatal "unbekannte Rolle für Umgebungs-Allowlist: $role" ;;
  esac
  for name in $names; do
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
      || fatal "$role-ENV_ALLOWLIST enthält ungültigen Variablennamen: $name"
    if [[ "$name" =~ (API_KEY|TOKEN|SECRET|PASSWORD|PRIVATE_KEY) ]]; then
      fatal "$role-ENV_ALLOWLIST darf keine Geheimnisvariable enthalten: $name"
    fi
    if [[ -v "$name" ]]; then
      value="${!name}"
      MODEL_ENV+=("$name=$value")
    fi
  done
}

run_model() {
  local role="$1" prompt="$2" phase="$3" ms="$4" round="${5:-1}" dispute="${6:-code}"
  stop_check
  local cmd stamp log_file base config_hash try=0 territory_retry=0 attempt=0 sleep_s="$RETRY_SLEEP" rc
  case "$role" in
    builder) cmd="$BUILDER_CMD" ;;
    reviewer) cmd="$REVIEWER_CMD" ;;
    qa) cmd="$QA_CMD" ;;
    *) fatal "unbekannte Rolle: $role" ;;
  esac

  stamp="$(TS)"
  PROMPT_FILE="$ORCH/logs/$ms-$phase-r$round-$stamp-prompt.md"
  if ! render_prompt "$prompt" "$ms" "$round" "$dispute" > "$PROMPT_FILE"; then
    rm -f -- "$PROMPT_FILE"
    fatal "Prompt $prompt kann nicht nach $PROMPT_FILE gerendert werden."
  fi
  base="$(git rev-parse HEAD)" || fatal "Basis-SHA vor $role/$phase kann nicht bestimmt werden."
  config_hash="$(sha256sum "$CONFIG" | awk '{print $1}')"
  snapshot_worktree

  while :; do
    stop_check
    attempt=$((attempt+1))
    log_file="$ORCH/logs/$ms-$phase-r$round-a$attempt-$(TS).log"
    ACTIVE_MODEL_LOG="$log_file"
    log "RUN $role $phase ($ms r$round, Versuch $attempt) -> $log_file"
    snapshot_phase_logs "$log_file"
    build_model_env "$role" "$PROMPT_FILE"
    if command -v timeout >/dev/null 2>&1; then
      if timeout "$PHASE_TIMEOUT" env -i "${MODEL_ENV[@]}" bash -c "$cmd" > "$log_file" 2>&1; then rc=0; else rc=$?; fi
    else
      if env -i "${MODEL_ENV[@]}" bash -c "$cmd" > "$log_file" 2>&1; then rc=0; else rc=$?; fi
    fi

    if ! phase_logs_intact; then
      OWNERSHIP_BAD="orchestrator/logs/** (Hash-Manifest)"
      restore_worktree "$base"
      if [ "$territory_retry" = 0 ]; then
        territory_retry=1
        log "WARN: $role verletzt Territorium: $OWNERSHIP_BAD — genau ein Retry mit Hinweis"
        printf '\nWICHTIG: Der vorige Versuch wurde wegen Territoriumsverletzung verworfen: %s. Wiederhole die Phase ohne diese Pfade; eine benötigte fremde Änderung wird im Handoff dokumentiert.\n' "$OWNERSHIP_BAD" >> "$PROMPT_FILE"
        continue
      fi
      clear_worktree_snapshot
      fatal "$role verletzt Territorium wiederholt: $OWNERSHIP_BAD"
    fi

    if [ "$rc" -ne 0 ]; then
      if transport_error "$rc" "$log_file" && [ "$try" -lt "$RETRY_MAX" ]; then
        restore_worktree "$base"
        try=$((try+1))
        log "WARN: Transportfehler $role/$phase rc=$rc — Retry $try/$RETRY_MAX in ${sleep_s}s; keine Runde verbraucht"
        sleep "$sleep_s"
        sleep_s=$((sleep_s*2))
        continue
      fi
      restore_worktree "$base"
      clear_worktree_snapshot
      fatal "$role/$phase rc=$rc; siehe $log_file"
    fi

    if ownership_check "$role" "$phase" "$ms" "$round" "$base" "$config_hash"; then
      break
    fi
    if [ "$territory_retry" = 0 ]; then
      territory_retry=1
      log "WARN: $role verletzt Territorium: $OWNERSHIP_BAD — genau ein Retry mit Hinweis"
      printf '\nWICHTIG: Der vorige Versuch wurde wegen Territoriumsverletzung verworfen: %s. Wiederhole die Phase ohne diese Pfade; eine benötigte fremde Änderung wird im Handoff dokumentiert.\n' "$OWNERSHIP_BAD" >> "$PROMPT_FILE"
      continue
    fi
    fatal "$role verletzt Territorium wiederholt: $OWNERSHIP_BAD"
  done
}

commit_phase() {
  local ms="$1" phase="$2" message="$3"
  local diff_rc
  CURRENT_MS="$ms"
  CURRENT_PHASE="$phase"
  mkdir -p "$ORCH/state/$ms"
  printf '%s\n' "$phase" > "$ORCH/state/$ms/current-phase" \
    || fatal "Phasenstatus kann nicht geschrieben werden: $ms/$phase"
  refresh_status
  git add -A -- . ':(exclude)orchestrator/.lock' ':(exclude)orchestrator/.lock/**' \
    || fatal "git add für Phase $ms/$phase fehlgeschlagen."
  if git diff --cached --quiet; then
    :
  else
    diff_rc=$?
    [ "$diff_rc" = 1 ] || fatal "Index-Prüfung für Phase $ms/$phase fehlgeschlagen (rc=$diff_rc)."
    git commit -qm "$message" || fatal "Phasen-Commit fehlgeschlagen: $message"
  fi
  PHASE_COUNT=$((PHASE_COUNT+1))
  if [ "$PHASE_COUNT" -ge "$PHASES_PER_RUN" ]; then
    HALT_REQUESTED=1
    log "AUTONOMY_LEVEL=0: Halt nach Phase $phase"
  fi
  stop_check
}

model_phase() {
  local role="$1" prompt="$2" phase="$3" ms="$4" round="$5" marker="${6:-}" dispute="${7:-code}" phase_marker
  run_model "$role" "$prompt" "$phase" "$ms" "$round" "$dispute"
  if [ -n "$marker" ]; then
    mkdir -p "$ORCH/state/$ms"
    for phase_marker in $marker; do
      touch "$ORCH/state/$ms/$phase_marker.done" \
        || fatal "Phasenmarker kann nicht geschrieben werden: $ms/$phase_marker"
    done
  fi
  commit_phase "$ms" "$phase" "orch($ms): $role $phase r$round"
}

verdict() {
  local ms="$1" phase="$2" round="$3" marker="$4" file="$ORCH/handoff/$1/verdict-$2.json" rel found rerun
  rel="${file#"$REPO_ROOT/"}"
  rerun="Nach Sichtung des Reviewer-Logs git rm orchestrator/state/$ms/$marker.done, committen und neu starten; die Review-Phase läuft dann erneut"
  [ -f "$file" ] || fatal "Verdict fehlt: $rel (erwartet: Runde $round). $rerun."
  jq -e --arg ms "$ms" --arg phase "$phase" '
    .milestone==$ms and .phase==$phase and
    (.round|type=="number") and
    (.verdict=="PASS" or .verdict=="REWORK" or .verdict=="ESCALATE") and
    (.blocking|type=="array") and (.nonblocking|type=="array") and
    all(.blocking[]?; (.id|type=="string" and length>0) and (.ref|type=="string" and length>0)) and
    (.verdict!="PASS" or (.blocking|length)==0)
  ' "$file" >/dev/null || fatal "Verdict-Schema ungültig: $file"
  # Ein Verdict gilt nur für seine Runde; ein liegengebliebenes darf nie über neuen Code entscheiden.
  found="$(jq -r '.round' "$file")"
  if ! jq -e --argjson round "$round" '.round == $round' "$file" >/dev/null; then
    if jq -e --argjson round "$round" '.round < $round' "$file" >/dev/null; then
      fatal "Verdict veraltet: $rel stammt aus Runde $found, erwartet Runde $round; die Review-Phase hat kein neues Verdict geschrieben. $rerun."
    fi
    fatal "Verdict passt nicht zur Runde: $rel nennt Runde $found, erwartet Runde $round. $rerun."
  fi
  VERDICT_VALUE="$(jq -r '.verdict' "$file")"
}

phase_done() { [ -f "$ORCH/state/$1/$2.done" ]; }

tag_once() {
  local tag="$1" message="$2" tagged head
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    tagged="$(git rev-list -n 1 "$tag")" || fatal "Tag-Ziel kann nicht gelesen werden: $tag"
    head="$(git rev-parse HEAD)" || fatal "HEAD kann für Tag $tag nicht gelesen werden."
    [ "$tagged" = "$head" ] \
      || fatal "Tag $tag existiert bereits auf einem anderen Commit; Tags werden nie verschoben."
    return 0
  fi
  git tag -a "$tag" -m "$message" || fatal "Tag kann nicht angelegt werden: $tag"
}

qa_required() {
  local current required
  [ -n "$QA_REQUIRED_FROM" ] || return 1
  current="$(jq -er --arg id "$1" 'to_entries[] | select(.value.id==$id) | .key' "$MILESTONES")" \
    || fatal "Meilenstein-ID für QA-Vergleich fehlt: $1"
  required="$(jq -er --arg id "$QA_REQUIRED_FROM" 'to_entries[] | select(.value.id==$id) | .key' "$MILESTONES")" \
    || fatal "QA_REQUIRED_FROM ist keine Meilenstein-ID: $QA_REQUIRED_FROM"
  [ "$current" -ge "$required" ]
}

run_gates() {
  local ms="$1" round="$2" marker="$3" rc
  stop_check
  CURRENT_MS="$ms"; CURRENT_PHASE="gates"
  if ROUND="$round" "$ORCH/verifier.sh" "$ms"; then rc=0; else rc=$?; fi
  mkdir -p "$ORCH/state/$ms"
  touch "$ORCH/state/$ms/$marker.done" || fatal "Gate-Marker kann nicht geschrieben werden: $marker"
  commit_phase "$ms" gates "orch($ms): gates r$round (rc=$rc)"
  LAST_GATE_RC="$rc"
}

ensure_project_assets() {
  [ "${BOOTSTRAP_AUTO:-0}" = 1 ] || return 0
  [ -n "${ASSETS_BUILD_CMD:-}" ] || return 0
  local ms="$1" log_file="$ORCH/logs/$1-assets-bootstrap-$(TS).log"
  if ! bash -c "$ASSETS_BUILD_CMD" > "$log_file" 2>&1; then
    mkdir -p "$ORCH/state/$ms"
    cp "$log_file" "$ORCH/state/$ms/gate-bootstrap.log"
    log "WARN: Projekt-Asset-Bootstrap fehlgeschlagen; gate-bootstrap.log belegt die Infrastrukturursache."
  fi
}

park() {
  local ms="$1" reason="$2" diff_rc
  CURRENT_MS="$ms"; CURRENT_PHASE=parked
  mkdir -p "$ORCH/state/$ms" "$ORCH/handoff/$ms"
  printf '%s\n' "$reason" > "$ORCH/state/$ms/parked"
  printf '%s\n' "$reason" > "$ORCH/state/$ms/reason"
  {
    echo "# ESCALATION $ms"
    echo
    echo "$reason"
    echo
    echo "Handoff: \`orchestrator/handoff/$ms/\`"
    echo
    echo "Fortsetzen: Ursache beheben, dann \`git rm orchestrator/state/$ms/parked\`, committen und neu starten (der Marker ist versioniert; ein bloßes rm lässt den Arbeitsbaum für den PREFLIGHT unsauber)."
  } > "$ORCH/ESCALATION-$ms.md"
  cp "$ORCH/ESCALATION-$ms.md" "$ORCH/ESCALATION.md"
  refresh_status "$reason" 3 true
  git add -A -- . ':(exclude)orchestrator/.lock' ':(exclude)orchestrator/.lock/**' \
    || fatal "git add beim Parken von $ms fehlgeschlagen."
  if git diff --cached --quiet; then
    :
  else
    diff_rc=$?
    [ "$diff_rc" = 1 ] || fatal "Index-Prüfung beim Parken von $ms fehlgeschlagen (rc=$diff_rc)."
    git commit -qm "orch($ms): park milestone" || fatal "Park-Commit für $ms fehlgeschlagen."
  fi
  notify_event NEEDS_HUMAN "$ms: $reason"
  notify_event PARKED "$ms: $reason"
  log "PARKED $ms: $reason — Lauf prüft weitere freie Meilensteine"
  PARKED_LIST="${PARKED_LIST}${PARKED_LIST:+ }$ms"
}

arbiter() {
  local ms="$1" dispute_phase="$2" round="$3" verdict_file="$ORCH/handoff/$1/verdict-arbiter.json"
  if [ -f "$ORCH/state/$ms/arbiter-granted" ]; then
    log "Arbiter für $ms wurde bereits verbraucht."
    return 1
  fi
  mkdir -p "$ORCH/handoff/$ms" "$ORCH/state/$ms"
  {
    echo "# ARBITER-REQUEST $ms"
    echo
    echo "Phase: $dispute_phase · Runde: $round"
    echo
    echo "Entscheide ausschließlich die referenzierten blocking-Punkte nach Spec > Reviewer > Builder."
  } > "$ORCH/handoff/$ms/ARBITER-REQUEST.md"
  CURRENT_MS="$ms"; CURRENT_PHASE=70-arbiter-request
  commit_phase "$ms" 70-arbiter-request "orch($ms): request arbiter for $dispute_phase r$round"
  [ "$HALT_REQUESTED" = 0 ] || return 2
  notify_event ARBITER "$ms: $dispute_phase r$round"
  model_phase reviewer 70-arbiter.md 70-arbiter "$ms" "$round" "" "$dispute_phase"
  [ "$HALT_REQUESTED" = 0 ] || return 2
  if [ ! -f "$verdict_file" ]; then
    fatal "Arbiter-Verdict fehlt: $verdict_file"
  fi
  if jq -e --arg ms "$ms" --arg phase "$dispute_phase" '
      .milestone==$ms and .phase==$phase and
      (.verdict=="RESOLVE" or .verdict=="HUMAN") and
      (.directive|type=="string" and length>0)
    ' "$verdict_file" >/dev/null; then
    if [ "$(jq -r '.verdict' "$verdict_file")" = RESOLVE ]; then
      touch "$ORCH/state/$ms/arbiter-granted"
      commit_phase "$ms" 70-arbiter-resolved "orch($ms): accept arbiter directive"
      log "ARBITER $ms: RESOLVE; $ARBITER_EXTRA_ROUNDS Zusatzrunden"
      return 0
    fi
    notify_event NEEDS_HUMAN "$ms: Arbiter meldet HUMAN"
    return 1
  fi
  fatal "Arbiter-Verdict ungültig: $verdict_file"
}

rebuild_reset() {
  local ms="$1" round="$2" path
  log "REBUILD $ms: Builder-Territorium zurück auf plan/$ms"
  for path in $REBUILD_PATHS; do
    case "$path" in /*|*..*) fatal "unsicherer REBUILD_PATHS-Eintrag: $path" ;; esac
    git rm -rq --ignore-unmatch -- "$path" >/dev/null 2>&1 \
      || fatal "Rebuild kann Builder-Pfad nicht entfernen: $path"
    if git cat-file -e "plan/$ms:$path" 2>/dev/null; then
      git checkout "plan/$ms" -- "$path" || fatal "Rebuild kann $path nicht aus plan/$ms wiederherstellen."
    fi
  done
  {
    echo "# REBUILD-BRIEF $ms"
    echo
    echo "Der bisherige Implementierungspfad wurde verworfen; Builder-Territorium steht wieder auf \`plan/$ms\`."
    echo
    echo "## Blocking-Befunde"
    jq -r '.blocking[]? | "- [\(.id)] ref=\(.ref) — \(.note // \"\")"' "$ORCH/handoff/$ms/verdict-code.json" 2>/dev/null || echo "_Kein gültiges Code-Verdict._"
    echo
    echo "## Letztes Review"
    sed -n '1,240p' "$ORCH/handoff/$ms/REVIEW.md" 2>/dev/null || echo "_Fehlt._"
    echo
    echo "## Letzte Gates"
    jq '.' "$ORCH/state/$ms/gates.json" 2>/dev/null || echo "_Fehlen._"
  } > "$ORCH/handoff/$ms/REBUILD-BRIEF.md"
  touch "$ORCH/state/$ms/5c-rebuild.done"
  touch "$ORCH/state/$ms/rebuild-reset-r$round.done"
  commit_phase "$ms" 62-rebuild-reset "orch($ms): reset builder territory for rebuild"
}

deps_met() {
  local ms="$1" dep previous
  DEPS_WAIT=""
  if jq -e --arg id "$ms" '.[] | select(.id==$id) | has("deps")' "$MILESTONES" >/dev/null; then
    while IFS= read -r dep; do
      [ -n "$dep" ] || continue
      phase_done "$dep" 8-done || DEPS_WAIT="${DEPS_WAIT}${DEPS_WAIT:+ }$dep"
    done < <(jq -r --arg id "$ms" '.[] | select(.id==$id) | .deps[]?' "$MILESTONES")
  else
    previous="$(jq -r --arg id "$ms" 'to_entries as $e | ($e[] | select(.value.id==$id) | .key) as $i | if $i>0 then $e[$i-1].value.id else empty end' "$MILESTONES")"
    [ -z "$previous" ] || phase_done "$previous" 8-done || DEPS_WAIT="$previous"
  fi
  [ -z "$DEPS_WAIT" ]
}

gate_rc_from_state() {
  local ms="$1" result
  result="$(jq -er '.result' "$ORCH/state/$ms/gates.json")" \
    || fatal "Gate-Ergebnis fehlt oder ist ungültig: $ms"
  case "$result" in
    pass) LAST_GATE_RC=0 ;;
    fail) LAST_GATE_RC=1 ;;
    error) LAST_GATE_RC=2 ;;
    *) fatal "unbekanntes Gate-Ergebnis für $ms: $result" ;;
  esac
}

run_ms() {
  local ms="$1" round verdict_value gate_rc max_rounds arb_rc diff_rc
  local infra_attempt gate_marker review_marker qa_marker postqa_marker pure_error
  RUN_MS_RC=0
  CURRENT_MS="$ms"
  mkdir -p "$ORCH/handoff/$ms" "$ORCH/state/$ms"
  log "=== $ms start ==="

  if ! phase_done "$ms" 1-acceptance; then
    model_phase reviewer 10-acceptance.md 10-acceptance "$ms" 1 1-acceptance
    if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi
  fi

  if ! phase_done "$ms" 3-plan-approved; then
    round="$(cat "$ORCH/state/$ms/plan-round" 2>/dev/null || echo 1)"
    while :; do
      if ! phase_done "$ms" "plan-r$round-planned"; then
        model_phase builder 20-plan.md 20-plan "$ms" "$round" "plan-r$round-planned"
        if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi
      fi
      if ! phase_done "$ms" "plan-r$round-reviewed"; then
        model_phase reviewer 30-plan-review.md 30-plan-review "$ms" "$round" "plan-r$round-reviewed"
        if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi
      fi
      verdict "$ms" plan "$round" "plan-r$round-reviewed"
      verdict_value="$VERDICT_VALUE"
      if [ "$verdict_value" = PASS ]; then break; fi
      if [ "$verdict_value" = ESCALATE ] || [ "$round" -ge "$MAX_ROUNDS_PLAN" ]; then
        if arbiter "$ms" plan "$round"; then arb_rc=0; else arb_rc=$?; fi
        if [ "$arb_rc" = 2 ]; then RUN_MS_RC=10; return 0; fi
        if [ "$arb_rc" != 0 ]; then
          park "$ms" "Plan nicht auflösbar; Arbiter benötigt HUMAN."
          RUN_MS_RC=3
          return 0
        fi
      fi
      round=$((round+1))
      printf '%s\n' "$round" > "$ORCH/state/$ms/plan-round" \
        || fatal "Planrunde kann nicht gespeichert werden: $ms r$round"
    done
    touch "$ORCH/state/$ms/3-plan-approved.done" \
      || fatal "Planfreigabe-Marker kann nicht geschrieben werden: $ms"
    commit_phase "$ms" 30-plan-approved "orch($ms): approve plan"
    tag_once "plan/$ms" "plan approved for $ms"
    if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi
  fi

  round="$(cat "$ORCH/state/$ms/round" 2>/dev/null || echo 1)"
  if phase_done "$ms" "rebuild-reset-r$round" && ! phase_done "$ms" "rebuild-r$round"; then
    model_phase builder 62-rebuild.md 62-rebuild "$ms" "$round" "rebuild-r$round"
    if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi
  fi
  if ! phase_done "$ms" 5-built; then
    model_phase builder 40-build.md 40-build "$ms" "$round" 5-built
    if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi
  fi

  if [ "$QA_ENABLED" != 1 ] && qa_required "$ms" && ! phase_done "$ms" 5b-qa; then
    park "$ms" "QA-Route inaktiv, aber QA ist ab $QA_REQUIRED_FROM Pflicht; keine Rework-Runde wird verbraucht."
    RUN_MS_RC=3
    return 0
  fi

  max_rounds="$MAX_ROUNDS_REWORK"
  [ ! -f "$ORCH/state/$ms/arbiter-granted" ] || max_rounds=$((MAX_ROUNDS_REWORK+ARBITER_EXTRA_ROUNDS))
  infra_attempt="$(cat "$ORCH/state/$ms/gate-error-attempt" 2>/dev/null || echo 0)"
  while :; do
    ensure_project_assets "$ms"
    gate_marker="gates-r$round-infra$infra_attempt"
    if ! phase_done "$ms" "$gate_marker"; then
      run_gates "$ms" "$round" "$gate_marker"
      gate_rc="$LAST_GATE_RC"
    else
      gate_rc_from_state "$ms"
      gate_rc="$LAST_GATE_RC"
    fi
    pure_error=0
    [ "$gate_rc" != 2 ] || pure_error=1
    if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi

    if [ "$pure_error" = 0 ] && [ "$QA_ENABLED" = 1 ] \
        && { ! phase_done "$ms" 5b-qa || [ -f "$ORCH/state/$ms/qa-requested" ]; }; then
      qa_marker="qa-r$round"
      postqa_marker="gates-r$round-infra$infra_attempt-postqa"
      rm -f "$ORCH/state/$ms/$postqa_marker.done"
      model_phase qa 45-qa.md 45-qa "$ms" "$round" "5b-qa $qa_marker"
      rm -f "$ORCH/state/$ms/qa-requested"
      if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi
    fi

    if [ "$pure_error" = 0 ] && [ "$QA_ENABLED" = 1 ] && phase_done "$ms" "qa-r$round"; then
      postqa_marker="gates-r$round-infra$infra_attempt-postqa"
      if ! phase_done "$ms" "$postqa_marker"; then
        run_gates "$ms" "$round" "$postqa_marker"
        gate_rc="$LAST_GATE_RC"
      else
        gate_rc_from_state "$ms"
        gate_rc="$LAST_GATE_RC"
      fi
      pure_error=0
      [ "$gate_rc" != 2 ] || pure_error=1
      if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi
    fi

    review_marker="code-review-r$round-infra$infra_attempt"
    if ! phase_done "$ms" "$review_marker"; then
      model_phase reviewer 50-code-review.md 50-code-review "$ms" "$round" "$review_marker"
      if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi
    fi
    verdict "$ms" code "$round" "$review_marker"
    verdict_value="$VERDICT_VALUE"

    if [ "$pure_error" = 1 ]; then
      if [ "$infra_attempt" -lt "$GATE_ERROR_RETRIES" ]; then
        infra_attempt=$((infra_attempt+1))
        printf '%s\n' "$infra_attempt" > "$ORCH/state/$ms/gate-error-attempt" \
          || fatal "Gate-error-Zähler kann nicht geschrieben werden: $ms"
        log "Gate error für $ms: Infrastruktur-Wiederholung $infra_attempt/$GATE_ERROR_RETRIES in Runde $round; keine Runde verbraucht"
        continue
      fi
      park "$ms" "Infrastruktur (Gate error) nach $GATE_ERROR_RETRIES Wiederholungen in Runde $round."
      RUN_MS_RC=3
      return 0
    fi
    rm -f "$ORCH/state/$ms/gate-error-attempt"

    if [ "$verdict_value" = PASS ] && [ "$gate_rc" = 0 ]; then
      break
    fi

    if [ "$verdict_value" = ESCALATE ] || [ "$round" -ge "$max_rounds" ]; then
      if arbiter "$ms" code "$round"; then arb_rc=0; else arb_rc=$?; fi
      if [ "$arb_rc" = 2 ]; then RUN_MS_RC=10; return 0; fi
      if [ "$arb_rc" != 0 ]; then
        park "$ms" "Codepfad festgefahren (Gates rc=$gate_rc, Verdict=$verdict_value); Arbiter benötigt HUMAN."
        RUN_MS_RC=3
        return 0
      fi
      max_rounds=$((MAX_ROUNDS_REWORK+ARBITER_EXTRA_ROUNDS))
    fi

    round=$((round+1))
    infra_attempt=0
    printf '%s\n' "$round" > "$ORCH/state/$ms/round" \
      || fatal "Rework-Runde kann nicht gespeichert werden: $ms r$round"
    if [ "$LADDER_ENABLED" = 1 ] && [ "$round" -ge "$REBUILD_ROUND" ] && ! phase_done "$ms" 5c-rebuild; then
      rebuild_reset "$ms" "$round"
      if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi
      model_phase builder 62-rebuild.md 62-rebuild "$ms" "$round" "rebuild-r$round"
    else
      model_phase builder 60-rework.md 60-rework "$ms" "$round" "rework-r$round"
    fi
    if [ "$HALT_REQUESTED" != 0 ]; then RUN_MS_RC=10; return 0; fi
  done

  if git diff --quiet "plan/$ms"..HEAD -- PROGRESS.md; then
    fatal "$ms kann nicht DONE werden: PROGRESS.md wurde seit plan/$ms nicht aktualisiert."
  else
    diff_rc=$?
    [ "$diff_rc" = 1 ] || fatal "PROGRESS-Prüfung für $ms fehlgeschlagen (rc=$diff_rc)."
  fi
  touch "$ORCH/state/$ms/8-done.done" || fatal "DONE-Marker kann nicht geschrieben werden: $ms"
  commit_phase "$ms" done "orch($ms): complete milestone"
  tag_once "done/$ms" "milestone $ms done"
  refresh_status "" 0 false
  notify_event DONE "$ms abgeschlossen"
  log "=== $ms DONE ==="
  if [ "${PUSH_REMOTE:-0}" = 1 ] && git remote get-url origin >/dev/null 2>&1; then
    git push --follow-tags || log "WARN: push fehlgeschlagen"
  fi
  return 0
}

acquire_lock
preflight

TARGET="${1:-}"
if [ -n "$TARGET" ] && ! jq -e --arg id "$TARGET" 'any(.[]; .id==$id)' "$MILESTONES" >/dev/null; then
  fatal "unbekannter Ziel-Meilenstein: $TARGET"
fi

COUNT=0
RAN=0
while IFS= read -r ms; do
  [ -z "$TARGET" ] || [ "$ms" = "$TARGET" ] || continue
  if phase_done "$ms" 8-done; then
    log "$ms bereits fertig"
    continue
  fi
  if [ -f "$ORCH/state/$ms/parked" ]; then
    log "$ms geparkt — übersprungen"
    PARKED_LIST="${PARKED_LIST}${PARKED_LIST:+ }$ms"
    continue
  fi
  if ! deps_met "$ms"; then
    log "$ms wartet auf: $DEPS_WAIT"
    if [ -n "$TARGET" ]; then
      fatal "$ms kann nicht gestartet werden; offene Abhängigkeiten: $DEPS_WAIT"
    fi
    continue
  fi
  COUNT=$((COUNT+1))
  [ "$COUNT" -le "$MAX_MS_PER_RUN" ] || { log "MAX_MS_PER_RUN=$MAX_MS_PER_RUN erreicht"; break; }
  RAN=$((RAN+1))
  RUN_MS_RC=0
  run_ms "$ms"
  rc="$RUN_MS_RC"
  case "$rc" in
    0) ;;
    3) ;;
    10) HALT_REQUESTED=1; break ;;
    *) fatal "run_ms $ms rc=$rc" ;;
  esac
  [ -z "$TARGET" ] || break
done < <(jq -r '.[].id' "$MILESTONES")

if [ "$HALT_REQUESTED" = 1 ]; then
  refresh_status
  exit 0
fi
if [ "$RAN" = 0 ] && [ -z "$PARKED_LIST" ] && [ -z "$TARGET" ]; then
  # Entweder alles fertig oder ein ungültiger/cyclischer Dependency-Stand.
  all_done=1
  while IFS= read -r ms; do
    phase_done "$ms" 8-done || all_done=0
  done < <(jq -r '.[].id' "$MILESTONES")
  if [ "$all_done" = 1 ]; then
    CURRENT_MS=""; CURRENT_PHASE=done; refresh_status "" 0 false
    log "Alle Meilensteine des Manifests abgeschlossen."
    exit 0
  fi
  fatal "kein ausführbarer Meilenstein; Dependency-Graph oder Zustand prüfen."
fi
if [ -n "$PARKED_LIST" ]; then
  CURRENT_PHASE=parked
  refresh_status "geparkt: $PARKED_LIST" 3 true
  log "Lauf beendet — geparkt: $PARKED_LIST"
  exit 3
fi

CURRENT_MS=""; CURRENT_PHASE=done
refresh_status "" 0 false
log "Lauf beendet."
exit 0
