# Shared by the hooks. Hooks print nothing except a sessionTitle JSON (KTD8)
# and always exit 0; diagnostics go to the ktab log.

[[ -n "${KTAB_NESTED:-}" ]] && exit 0

SCRIPTS_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
KTAB="$SCRIPTS_DIR/../bin/ktab"
LOG_DIR=$("$KTAB" state-dir)
if mkdir -p "$LOG_DIR" 2>/dev/null; then exec 2>>"$LOG_DIR/log"; else exec 2>/dev/null; fi

INPUT=$(cat)
field() { jq -r --arg k "$1" '.[$k] // empty' <<<"$INPUT" 2>/dev/null; }

SID=$(field session_id)
[[ "$SID" =~ ^[A-Za-z0-9_-]{1,128}$ ]] || exit 0
TITLE=$(field session_title)

parent_of() { local _ ppid; read -r _ _ _ ppid _ <"/proc/$1/stat" 2>/dev/null && echo "$ppid"; }

# Nearest process named claude at or above <pid>; KTAB_SCAN_STOP_PID bounds the walk in tests.
claude_ancestor() {
  local pid=$1 comm i
  for i in 1 2 3 4 5 6; do
    [[ -n "$pid" && "$pid" != 0 && "$pid" != "${KTAB_SCAN_STOP_PID:-}" ]] || return 0
    read -r comm <"/proc/$pid/comm" 2>/dev/null || return 0
    [[ "$comm" == claude ]] && { echo "$pid"; return 0; }
    pid=$(parent_of "$pid")
  done
}

print_mode() { tr '\0' '\n' <"/proc/$1/cmdline" 2>/dev/null | grep -qxE -- '-p|--print'; }

# The Claude process owning this tab. Print-mode runs (scripts, tool calls) and
# claude-inside-claude sessions must not touch the tab.
OWNER=$(claude_ancestor "$PPID")
if [[ -n "$OWNER" ]]; then
  print_mode "$OWNER" && exit 0
  [[ -z "$(claude_ancestor "$(parent_of "$OWNER")")" ]] || exit 0
fi

# The state file is read once per hook run and re-read after each write.
load_state() { STATE=$("$KTAB" state-get "$SID"); }
st() { jq -r --arg k "$1" '.[$k] // empty' <<<"${STATE:-"{}"}" 2>/dev/null; }
st_set() {
  "$KTAB" state-set "$SID" "$@" || "$KTAB" log "state-set failed for $SID: $*"
  load_state
}
load_state

# A launch-time -n, or a title that is not our slug (/rename, old session), wins.
mark_manual_name() {
  if [[ -n "${KTAB_NAME_SET:-}" ]] || [[ -n "$TITLE" && "$TITLE" != "$(st slug)" ]]; then
    [[ "$(st name_source)" == manual ]] || st_set name_source=manual
  fi
}

# Emits the chosen slug as the session title once, unless the name is manual.
emit_pending_title() { # emit_pending_title <HookEventName>
  local slug
  slug=$(st slug)
  [[ -n "$slug" && "$(st stage)" == done && "$(st title_applied)" != true && "$(st name_source)" != manual ]] || return 0
  st_set title_applied=true stage=titled
  jq -nc --arg e "$1" --arg t "$slug" '{hookSpecificOutput: {hookEventName: $e, sessionTitle: $t}}'
}

apply_manual_colour() {
  [[ -n "${KTAB_COLOR:-}" ]] || return 1
  st_set color="$KTAB_COLOR" color_source=manual
  "$KTAB" set "$KTAB_COLOR" || true
}
