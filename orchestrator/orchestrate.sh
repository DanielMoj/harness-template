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

set -a
# shellcheck disable=SC1090
source "$CONFIG"
set +a

TS() { date +%Y%m%d-%H%M%S; }
log() { printf '[%s] %s\n' "$(TS)" "$*" | tee -a "$ORCH/logs/orchestrate.log"; }

CURRENT_MS=""
CURRENT_PHASE="preflight"
LOCK_HELD=0
PARKED_LIST=""
HALT_REQUESTED=0
PHASE_COUNT=0

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
QA_REQUIRED_FROM="${QA_REQUIRED_FROM:-M0}"
QA_ENABLED="${QA_ENABLED:-$([ -n "${QA_CMD:-}" ] && echo 1 || echo 0)}"
QA_PROBE_STRICT="${QA_PROBE_STRICT:-1}"
QA_PROBE_RETRIES="${QA_PROBE_RETRIES:-3}"
QA_PROBE_TIMEOUT="${QA_PROBE_TIMEOUT:-180}"
QA_PROBE_SLEEP="${QA_PROBE_SLEEP:-300}"
REBUILD_PATHS="${REBUILD_PATHS:-src tools tests/unit tests/properties}"

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
  [ "$LOCK_HELD" = 1 ] || return 0
  if [ -f "$ORCH/.lock/pid" ] && [ "$(cat "$ORCH/.lock/pid" 2>/dev/null)" = "$$" ]; then
    rm -f "$ORCH/.lock/pid"
    rmdir "$ORCH/.lock" 2>/dev/null || true
  fi
  LOCK_HELD=0
}
trap release_lock EXIT INT TERM

acquire_lock() {
  local lock="$ORCH/.lock" oldpid=""
  if mkdir "$lock" 2>/dev/null; then
    printf '%s\n' "$$" > "$lock/pid"
    LOCK_HELD=1
    return 0
  fi
  oldpid="$(cat "$lock/pid" 2>/dev/null || true)"
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    fatal "Orchestrator läuft bereits (PID $oldpid)."
  fi
  log "WARN: verwaister Lock (PID ${oldpid:-unbekannt}) — wird übernommen"
  rm -f "$lock/pid"
  rmdir "$lock" 2>/dev/null || fatal "verwaister Lock ist nicht leer: $lock"
  mkdir "$lock" || fatal "Lock kann nicht angelegt werden: $lock"
  printf '%s\n' "$$" > "$lock/pid"
  LOCK_HELD=1
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
      (.criteriaRef|type=="array" and length>0 and all(.[]; type=="string" and length>0)) and
      ((has("deps")|not) or (.deps|type=="array" and all(.[]; type=="string"))) and
      (.effort=="low" or .effort=="high" or .effort=="max")
    ) and
    ([.[].id] | length == (unique|length)) and
    ([.[] | .deps[]?] - [.[].id] | length==0) and
    all(.[]; (.id as $id | all(.deps[]?; . != $id)))
  ' "$MILESTONES" >/dev/null || fatal "Meilensteinmanifest verletzt contracts/PROTOCOLS.md §2."
}

validate_role_cli() {
  local role="$1" cmd="$2" help_cmd="$3" required="$4" safe_pattern="$5"
  [ -n "$cmd" ] || fatal "$role-CMD ist leer."
  [ -n "$help_cmd" ] || fatal "$role-HELP_CMD ist leer."
  local help_out
  if ! help_out="$(bash -c "$help_cmd" 2>&1)"; then
    fatal "$role: reales --help-Kommando fehlgeschlagen: $help_cmd"
  fi
  local flag
  for flag in $required; do
    grep -Fq -- "$flag" <<<"$help_out" || fatal "$role: Flag '$flag' fehlt im echten --help."
  done
  [ -z "$safe_pattern" ] || grep -Eq -- "$safe_pattern" <<<"$cmd" \
    || fatal "$role: konfigurierter Sandbox-/Permission-Modus fehlt."
}

preflight() {
  command -v git >/dev/null 2>&1 || fatal "git fehlt"
  command -v jq >/dev/null 2>&1 || fatal "jq fehlt"
  command -v bash >/dev/null 2>&1 || fatal "bash fehlt"
  validate_manifest

  require_uint PHASE_TIMEOUT "$PHASE_TIMEOUT"
  require_uint MAX_ROUNDS_PLAN "$MAX_ROUNDS_PLAN"
  require_uint MAX_ROUNDS_REWORK "$MAX_ROUNDS_REWORK"
  require_uint REBUILD_ROUND "$REBUILD_ROUND"
  require_uint RETRY_MAX "$RETRY_MAX"
  require_uint MAX_MS_PER_RUN "$MAX_MS_PER_RUN"

  local all_cmds="${BUILDER_CMD:-} ${REVIEWER_CMD:-} ${QA_CMD:-}"
  if grep -Eqi -- '--continue|--resume|--session([ =]|$)' <<<"$all_cmds"; then
    fatal "Resume-/Session-Flags sind verboten; jede Phase ist eine frische Session."
  fi
  if grep -Eqi -- '--dangerously-skip-permissions|bypassPermissions|--yolo|full[-_ ]?access|dangerously[-_ ]?disable' <<<"$all_cmds"; then
    fatal "gefährlicher Bypass-/Full-Access-Modus in Rollenkommando gefunden."
  fi

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
    | grep -vE '^(STATUS\.md|orchestrator/STOP|orchestrator/state/summary\.json)$' || true)"
  [ -z "$dirty" ] || fatal "Arbeitsbaum vor Lauf nicht sauber: $dirty"

  CURRENT_PHASE=preflight
  refresh_status
  log "CONFIG: AUTONOMY=$AUTONOMY_LEVEL PLAN<=$MAX_ROUNDS_PLAN REWORK<=$MAX_ROUNDS_REWORK REBUILD@r$REBUILD_ROUND ARBITER+$ARBITER_EXTRA_ROUNDS TIMEOUT=$PHASE_TIMEOUT RETRY=${RETRY_MAX}x/${RETRY_SLEEP}s MAX_MS=$MAX_MS_PER_RUN QA=$QA_ENABLED(ab $QA_REQUIRED_FROM) NOTIFY=$([ "$NOTIFY_ENABLED" = 1 ] && [ -n "${NOTIFY_URL:-}" ] && echo an || echo aus) BUILDER=${BUILDER_CMD%% *} REVIEWER=${REVIEWER_CMD%% *}"

  if [ "$QA_ENABLED" = 1 ] && [ "$QA_PROBE_STRICT" = 1 ]; then
    local attempt=1 probe_file probe_out rc
    while [ "$attempt" -le "$QA_PROBE_RETRIES" ]; do
      probe_file="$ORCH/logs/qa-probe-$(TS)-$attempt.md"
      printf '%s\n' "Antworte nur: OK" > "$probe_file"
      export PROMPT_FILE="$probe_file"
      set +e
      if command -v timeout >/dev/null 2>&1; then
        probe_out="$(timeout "$QA_PROBE_TIMEOUT" bash -c "$QA_CMD" 2>&1)"; rc=$?
      else
        probe_out="$(bash -c "$QA_CMD" 2>&1)"; rc=$?
      fi
      set -e
      if [ "$rc" = 0 ] && grep -q 'OK' <<<"$probe_out"; then
        log "QA-Routenprobe bestanden ($QA_MODEL)"
        break
      fi
      log "WARN: QA-Routenprobe $attempt/$QA_PROBE_RETRIES fehlgeschlagen (rc=$rc)"
      [ "$attempt" -ge "$QA_PROBE_RETRIES" ] && fatal "QA-Routenprobe strict fehlgeschlagen."
      sleep "$QA_PROBE_SLEEP"
      attempt=$((attempt+1))
    done
  fi
}

render_prompt() {
  local prompt="$1" ms="$2" round="$3" dispute_phase="${4:-code}" criteria
  criteria="$(jq -r --arg id "$ms" '.[] | select(.id==$id) | .criteriaRef | join(" ")' "$MILESTONES")"
  sed \
    -e "s|{{MS}}|$ms|g" \
    -e "s|{{ROUND}}|$round|g" \
    -e "s|{{CRITERIA}}|$criteria|g" \
    -e "s|{{DISPUTE_PHASE}}|$dispute_phase|g" \
    "$ORCH/prompts/$prompt"
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
  git reset --hard "$base" -q
  git clean -qfd -e config.env -e toolchain.json -e orchestrator/logs/ -e orchestrator/.lock/
}

path_allowed() {
  local role="$1" phase="$2" ms="$3" path="$4"
  case "$role:$phase:$path" in
    reviewer:10-acceptance:tests/acceptance/*|reviewer:10-acceptance:reference/anchors/*|reviewer:10-acceptance:orchestrator/handoff/"$ms"/*) return 0 ;;
    builder:20-plan:orchestrator/handoff/"$ms"/*) return 0 ;;
    reviewer:30-plan-review:orchestrator/handoff/"$ms"/*|reviewer:30-plan-review:contracts/PROTOCOLS.md|reviewer:30-plan-review:IMPLEMENTATION-RULES.md|reviewer:30-plan-review:docs/decisions/*) return 0 ;;
    reviewer:30-plan-review:.dependency-cruiser.*|reviewer:30-plan-review:dependency-cruiser.*) return 0 ;;
    qa:45-qa:tests/e2e/*|qa:45-qa:tests/fuzz/*|qa:45-qa:orchestrator/handoff/"$ms"/QA.md|qa:45-qa:BACKLOG.md) return 0 ;;
    reviewer:50-code-review:orchestrator/handoff/"$ms"/*|reviewer:50-code-review:tests/acceptance/*|reviewer:50-code-review:reference/anchors/*|reviewer:50-code-review:BACKLOG.md|reviewer:50-code-review:IMPLEMENTATION-RULES.md|reviewer:50-code-review:contracts/PROTOCOLS.md|reviewer:50-code-review:docs/decisions/*) return 0 ;;
    reviewer:50-code-review:.dependency-cruiser.*|reviewer:50-code-review:dependency-cruiser.*) return 0 ;;
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
  return 1
}

ownership_check() {
  local role="$1" phase="$2" ms="$3" base="$4" config_hash="$5"
  OWNERSHIP_BAD=""
  if [ "$(git rev-parse HEAD)" != "$base" ]; then
    OWNERSHIP_BAD="git history (Modelle dürfen nicht committen)"
    rollback_attempt "$base"
    return 1
  fi
  if [ "$(sha256sum "$CONFIG" | awk '{print $1}')" != "$config_hash" ]; then
    OWNERSHIP_BAD="orchestrator/config.env"
    rollback_attempt "$base"
    return 1
  fi

  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if ! path_allowed "$role" "$phase" "$ms" "$path"; then
      OWNERSHIP_BAD="${OWNERSHIP_BAD}${OWNERSHIP_BAD:+ }$path"
    fi
  done < <({ git diff --name-only "$base"; git status --porcelain --untracked-files=all | awk '{print substr($0,4)}'; } | sort -u)

  if [ -n "$OWNERSHIP_BAD" ]; then
    rollback_attempt "$base"
    return 1
  fi
  mkdir -p "$ORCH/state/$ms"
  printf '%s\t%s\t%s\n' "$(date --iso-8601=seconds)" "$role" "$phase" > "$ORCH/state/$ms/territory-ok"
  return 0
}

run_model() {
  local role="$1" prompt="$2" phase="$3" ms="$4" round="${5:-1}" dispute="${6:-code}"
  stop_check
  local cmd stamp log_file base config_hash try=0 territory_retry=0 sleep_s="$RETRY_SLEEP" rc
  case "$role" in
    builder) cmd="$BUILDER_CMD" ;;
    reviewer) cmd="$REVIEWER_CMD" ;;
    qa) cmd="$QA_CMD" ;;
    *) fatal "unbekannte Rolle: $role" ;;
  esac

  stamp="$(TS)"
  export PROMPT_FILE="$ORCH/logs/$ms-$phase-r$round-$stamp-prompt.md"
  render_prompt "$prompt" "$ms" "$round" "$dispute" > "$PROMPT_FILE"
  log_file="$ORCH/logs/$ms-$phase-r$round-$stamp.log"
  base="$(git rev-parse HEAD)"
  config_hash="$(sha256sum "$CONFIG" | awk '{print $1}')"

  while :; do
    stop_check
    log "RUN $role $phase ($ms r$round, Versuch $((try+1))) -> $log_file"
    set +e
    if command -v timeout >/dev/null 2>&1; then
      timeout "$PHASE_TIMEOUT" bash -c "$cmd" > "$log_file" 2>&1; rc=$?
    else
      bash -c "$cmd" > "$log_file" 2>&1; rc=$?
    fi
    set -e

    if [ "$rc" -ne 0 ]; then
      if transport_error "$rc" "$log_file" && [ "$try" -lt "$RETRY_MAX" ]; then
        rollback_attempt "$base"
        try=$((try+1))
        log "WARN: Transportfehler $role/$phase rc=$rc — Retry $try/$RETRY_MAX in ${sleep_s}s; keine Runde verbraucht"
        sleep "$sleep_s"
        sleep_s=$((sleep_s*2))
        log_file="$ORCH/logs/$ms-$phase-r$round-$(TS).log"
        continue
      fi
      fatal "$role/$phase rc=$rc; siehe $log_file"
    fi

    if ownership_check "$role" "$phase" "$ms" "$base" "$config_hash"; then
      break
    fi
    if [ "$territory_retry" = 0 ]; then
      territory_retry=1
      log "WARN: $role verletzt Territorium: $OWNERSHIP_BAD — genau ein Retry mit Hinweis"
      printf '\nWICHTIG: Der vorige Versuch wurde wegen Territoriumsverletzung verworfen: %s. Wiederhole die Phase ohne diese Pfade; eine benötigte fremde Änderung wird im Handoff dokumentiert.\n' "$OWNERSHIP_BAD" >> "$PROMPT_FILE"
      log_file="$ORCH/logs/$ms-$phase-r$round-$(TS).log"
      continue
    fi
    fatal "$role verletzt Territorium wiederholt: $OWNERSHIP_BAD"
  done
}

commit_phase() {
  local ms="$1" phase="$2" message="$3"
  CURRENT_MS="$ms"
  CURRENT_PHASE="$phase"
  mkdir -p "$ORCH/state/$ms"
  printf '%s\n' "$phase" > "$ORCH/state/$ms/current-phase"
  refresh_status
  git add -A
  git diff --cached --quiet || git commit -qm "$message"
  PHASE_COUNT=$((PHASE_COUNT+1))
  if [ "$PHASE_COUNT" -ge "$PHASES_PER_RUN" ]; then
    HALT_REQUESTED=1
    log "AUTONOMY_LEVEL=0: Halt nach Phase $phase"
  fi
  stop_check
}

model_phase() {
  local role="$1" prompt="$2" phase="$3" ms="$4" round="$5" marker="${6:-}" dispute="${7:-code}"
  run_model "$role" "$prompt" "$phase" "$ms" "$round" "$dispute"
  [ -z "$marker" ] || { mkdir -p "$ORCH/state/$ms"; touch "$ORCH/state/$ms/$marker.done"; }
  commit_phase "$ms" "$phase" "orch($ms): $role $phase r$round"
}

verdict() {
  local ms="$1" phase="$2" file="$ORCH/handoff/$1/verdict-$2.json"
  [ -f "$file" ] || fatal "Verdict fehlt: $file"
  jq -e --arg ms "$ms" --arg phase "$phase" '
    .milestone==$ms and .phase==$phase and
    (.round|type=="number") and
    (.verdict=="PASS" or .verdict=="REWORK" or .verdict=="ESCALATE") and
    (.blocking|type=="array") and (.nonblocking|type=="array") and
    all(.blocking[]?; (.id|type=="string" and length>0) and (.ref|type=="string" and length>0)) and
    (.verdict!="PASS" or (.blocking|length)==0)
  ' "$file" >/dev/null || fatal "Verdict-Schema ungültig: $file"
  jq -r '.verdict' "$file"
}

phase_done() { [ -f "$ORCH/state/$1/$2.done" ]; }

tag_once() {
  local tag="$1" message="$2"
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    [ "$(git rev-list -n 1 "$tag")" = "$(git rev-parse HEAD)" ] \
      || fatal "Tag $tag existiert bereits auf einem anderen Commit; Tags werden nie verschoben."
    return 0
  fi
  git tag -a "$tag" -m "$message"
}

milestone_number() {
  sed -E 's/^[^0-9]*([0-9]+).*$/\1/' <<<"$1"
}

qa_required() {
  local current required
  current="$(milestone_number "$1")"
  required="$(milestone_number "$QA_REQUIRED_FROM")"
  [ "$current" -ge "$required" ]
}

run_gates() {
  local ms="$1" round="$2" rc
  stop_check
  CURRENT_MS="$ms"; CURRENT_PHASE="gates"
  set +e
  ROUND="$round" "$ORCH/verifier.sh" "$ms"; rc=$?
  set -e
  commit_phase "$ms" gates "orch($ms): gates r$round (rc=$rc)"
  return "$rc"
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
  local ms="$1" reason="$2"
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
    echo "Fortsetzen: Ursache beheben, \`orchestrator/state/$ms/parked\` entfernen und neu starten."
  } > "$ORCH/ESCALATION-$ms.md"
  cp "$ORCH/ESCALATION-$ms.md" "$ORCH/ESCALATION.md"
  refresh_status "$reason" 3 true
  git add -A
  git diff --cached --quiet || git commit -qm "orch($ms): park milestone"
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
  local ms="$1" path
  log "REBUILD $ms: Builder-Territorium zurück auf plan/$ms"
  for path in $REBUILD_PATHS; do
    case "$path" in /*|*..*) fatal "unsicherer REBUILD_PATHS-Eintrag: $path" ;; esac
    git rm -rq --ignore-unmatch -- "$path" >/dev/null 2>&1 || true
    if git cat-file -e "plan/$ms:$path" 2>/dev/null; then
      git checkout "plan/$ms" -- "$path"
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

run_ms() {
  local ms="$1" round verdict_value gate_rc max_rounds arb_rc
  CURRENT_MS="$ms"
  mkdir -p "$ORCH/handoff/$ms" "$ORCH/state/$ms"
  log "=== $ms start ==="

  if ! phase_done "$ms" 1-acceptance; then
    model_phase reviewer 10-acceptance.md 10-acceptance "$ms" 1 1-acceptance
    [ "$HALT_REQUESTED" = 0 ] || return 10
  fi

  if ! phase_done "$ms" 3-plan-approved; then
    round="$(cat "$ORCH/state/$ms/plan-round" 2>/dev/null || echo 1)"
    while :; do
      model_phase builder 20-plan.md 20-plan "$ms" "$round"
      [ "$HALT_REQUESTED" = 0 ] || return 10
      model_phase reviewer 30-plan-review.md 30-plan-review "$ms" "$round"
      [ "$HALT_REQUESTED" = 0 ] || return 10
      verdict_value="$(verdict "$ms" plan)"
      if [ "$verdict_value" = PASS ]; then break; fi
      if [ "$verdict_value" = ESCALATE ] || [ "$round" -ge "$MAX_ROUNDS_PLAN" ]; then
        set +e; arbiter "$ms" plan "$round"; arb_rc=$?; set -e
        [ "$arb_rc" = 2 ] && return 10
        if [ "$arb_rc" != 0 ]; then park "$ms" "Plan nicht auflösbar; Arbiter benötigt HUMAN."; return 3; fi
      fi
      round=$((round+1))
      printf '%s\n' "$round" > "$ORCH/state/$ms/plan-round"
    done
    touch "$ORCH/state/$ms/3-plan-approved.done"
    CURRENT_PHASE=30-plan-approved
    commit_phase "$ms" 30-plan-approved "orch($ms): approve plan"
    tag_once "plan/$ms" "plan approved for $ms"
    [ "$HALT_REQUESTED" = 0 ] || return 10
  fi

  round="$(cat "$ORCH/state/$ms/round" 2>/dev/null || echo 1)"
  if ! phase_done "$ms" 5-built; then
    model_phase builder 40-build.md 40-build "$ms" "$round" 5-built
    [ "$HALT_REQUESTED" = 0 ] || return 10
  fi

  if [ "$QA_ENABLED" != 1 ] && qa_required "$ms" && ! phase_done "$ms" 5b-qa; then
    park "$ms" "QA-Route inaktiv, aber QA ist ab $QA_REQUIRED_FROM Pflicht; keine Rework-Runde wird verbraucht."
    return 3
  fi

  max_rounds="$MAX_ROUNDS_REWORK"
  [ ! -f "$ORCH/state/$ms/arbiter-granted" ] || max_rounds=$((MAX_ROUNDS_REWORK+ARBITER_EXTRA_ROUNDS))
  while :; do
    ensure_project_assets "$ms"
    set +e; run_gates "$ms" "$round"; gate_rc=$?; set -e
    [ "$HALT_REQUESTED" = 0 ] || return 10

    if [ "$QA_ENABLED" = 1 ] && { ! phase_done "$ms" 5b-qa || [ -f "$ORCH/state/$ms/qa-requested" ]; }; then
      model_phase qa 45-qa.md 45-qa "$ms" "$round" 5b-qa
      rm -f "$ORCH/state/$ms/qa-requested"
      [ "$HALT_REQUESTED" = 0 ] || return 10
      set +e; run_gates "$ms" "$round"; gate_rc=$?; set -e
      [ "$HALT_REQUESTED" = 0 ] || return 10
    fi

    model_phase reviewer 50-code-review.md 50-code-review "$ms" "$round"
    [ "$HALT_REQUESTED" = 0 ] || return 10
    verdict_value="$(verdict "$ms" code)"
    if [ "$verdict_value" = PASS ] && [ "$gate_rc" = 0 ]; then
      break
    fi

    if [ "$verdict_value" = ESCALATE ] || [ "$round" -ge "$max_rounds" ]; then
      set +e; arbiter "$ms" code "$round"; arb_rc=$?; set -e
      [ "$arb_rc" = 2 ] && return 10
      if [ "$arb_rc" != 0 ]; then
        park "$ms" "Codepfad festgefahren (Gates rc=$gate_rc, Verdict=$verdict_value); Arbiter benötigt HUMAN."
        return 3
      fi
      max_rounds=$((MAX_ROUNDS_REWORK+ARBITER_EXTRA_ROUNDS))
    fi

    round=$((round+1))
    printf '%s\n' "$round" > "$ORCH/state/$ms/round"
    if [ "$LADDER_ENABLED" = 1 ] && [ "$round" -ge "$REBUILD_ROUND" ] && ! phase_done "$ms" 5c-rebuild; then
      rebuild_reset "$ms"
      [ "$HALT_REQUESTED" = 0 ] || return 10
      model_phase builder 62-rebuild.md 62-rebuild "$ms" "$round"
    else
      model_phase builder 60-rework.md 60-rework "$ms" "$round"
    fi
    [ "$HALT_REQUESTED" = 0 ] || return 10
  done

  if git diff --quiet "plan/$ms"..HEAD -- PROGRESS.md; then
    fatal "$ms kann nicht DONE werden: PROGRESS.md wurde seit plan/$ms nicht aktualisiert."
  fi
  touch "$ORCH/state/$ms/8-done.done"
  CURRENT_PHASE=done
  refresh_status "" 0 false
  git add -A
  git diff --cached --quiet || git commit -qm "orch($ms): complete milestone"
  tag_once "done/$ms" "milestone $ms done"
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
    continue
  fi
  COUNT=$((COUNT+1))
  [ "$COUNT" -le "$MAX_MS_PER_RUN" ] || { log "MAX_MS_PER_RUN=$MAX_MS_PER_RUN erreicht"; break; }
  RAN=$((RAN+1))
  set +e; run_ms "$ms"; rc=$?; set -e
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
  if jq -e --arg dir "$ORCH/state" 'all(.[]; .id as $id | true)' "$MILESTONES" >/dev/null \
     && while IFS= read -r ms; do phase_done "$ms" 8-done || exit 1; done < <(jq -r '.[].id' "$MILESTONES"); then
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
