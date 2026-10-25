#!/usr/bin/env bash
# Background classifier: asks haiku for a task type and slug, validates the
# reply (KTD7), paints the tab and records the result for the next prompt.
# Usage: classify.sh <session_id> <prompt_file>

set -u
SID="$1"
PROMPT_FILE="$2"
KTAB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/ktab"
trap 'rm -f "$PROMPT_FILE"' EXIT

st() { "$KTAB" state-get "$SID" "$1"; }
finish_failed() {
  "$KTAB" log "classify $SID: $*"
  "$KTAB" state-set "$SID" stage=failed
  exit 0
}

types=$("$KTAB" types | paste -sd '|')
instruction="Classify the developer task below. Reply with exactly one JSON object and nothing else:
{\"type\": \"<$types>\", \"slug\": \"<2-3 lowercase english words in kebab-case naming the task>\"}

Task:"

# --setting-sources "" keeps plugins (and this hook) out of the nested session (KTD6).
reply=$(KTAB_NESTED=1 timeout "${KTAB_CLASSIFY_TIMEOUT:-20}" claude -p \
  --model haiku --no-session-persistence --setting-sources "" --tools "" \
  --disable-slash-commands --strict-mcp-config \
  "$instruction
$(cat "$PROMPT_FILE")" 2>/dev/null) || finish_failed "claude call failed or timed out"

json=$(grep -o '{[^{}]*}' <<<"$reply" | head -1)
type=$(jq -r '.type // empty' <<<"$json" 2>/dev/null)
slug=$(jq -r '.slug // empty' <<<"$json" 2>/dev/null)

[[ "$type" =~ ^[a-z]+$ && "|$types|" == *"|$type|"* ]] || finish_failed "bad type [$type]"
[[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+){1,2}$ && ${#slug} -le 32 ]] || finish_failed "bad slug [$slug]"

if [[ "$(st color_source)" != manual ]]; then
  owner=$(st owner_pid)
  if [[ -z "$owner" ]] || kill -0 "$owner" 2>/dev/null; then
    hex=$("$KTAB" type-color "$type")
    "$KTAB" set "$hex" || "$KTAB" log "classify $SID: paint failed"
    "$KTAB" state-set "$SID" color="$hex" color_source=auto
  fi
fi

"$KTAB" state-set "$SID" type="$type" slug="$slug" stage=done
exit 0
