#!/usr/bin/env bash
# UserPromptSubmit: emit a ready slug as the session title, or start the
# background classifier on the first prompt when auto-mode is on (KTD5).

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mark_manual_name

title=$(emit_pending_title UserPromptSubmit)
if [[ -n "$title" ]]; then
  printf '%s\n' "$title"
  exit 0
fi

[[ "${CLAUDE_PLUGIN_OPTION_AUTO_MODE:-}" == true ]] || exit 0
# A failed pick (no network, login error) is retried on later prompts while attempts
# stay under the auto_attempts setting (1-5, default 1 = no retry). A pending pick
# older than 60s means the classifier died and counts as failed.
max_attempts=${CLAUDE_PLUGIN_OPTION_AUTO_ATTEMPTS:-1}
[[ "$max_attempts" =~ ^[1-5]$ ]] || max_attempts=1
attempts=$(st attempts)
attempts=${attempts:-0}
case "$(st stage)" in
  "") ;;
  failed) ((attempts < max_attempts)) || exit 0 ;;
  pending)
    pending_at=$(st pending_at)
    ((attempts < max_attempts && $(date +%s) - ${pending_at:-0} > 60)) || exit 0
    ;;
  *) exit 0 ;;
esac
if [[ "$(st name_source)" == manual ]] &&
  [[ -n "${KTAB_COLOR:-}" || "$(st color_source)" == manual ]]; then
  exit 0
fi

prompt=$(field prompt)
[[ -n "$prompt" ]] || exit 0

prompt_file=$(mktemp "$LOG_DIR/prompt.XXXXXX") || exit 0
printf '%s' "${prompt:0:2000}" >"$prompt_file"
# The classifier must not paint after the owning Claude exits.
st_set stage=pending owner_pid="$OWNER" attempts=$((attempts + 1)) pending_at="$(date +%s)"

# All three streams detached: an inherited pipe would keep Claude waiting on the hook.
setsid "$SCRIPTS_DIR/classify.sh" "$SID" "$prompt_file" \
  </dev/null >/dev/null 2>>"$LOG_DIR/log" &
exit 0
