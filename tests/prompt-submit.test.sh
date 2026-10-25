# U4: UserPromptSubmit hook.

HOOK="$REPO/plugin/scripts/prompt-submit.sh"
GOOD='{"type":"feature","slug":"csv-report-export"}'

submit() { # submit <prompt> [session_title] [session_id] -> hook stdout+stderr
  jq -nc --arg p "$1" --arg t "${2:-}" --arg s "${3:-sess-1}" \
    '{session_id: $s, hook_event_name: "UserPromptSubmit", prompt: $p} + (if $t == "" then {} else {session_title: $t} end)' |
    "$HOOK" 2>&1
}

# Waits for the background classifier to leave the pending stage.
wait_classified() {
  local i
  for i in $(seq 50); do
    [[ "$(st stage "${1:-sess-1}")" != pending ]] && return 0
    sleep 0.1
  done
  fail "classifier still pending"
}

test_first_prompt_returns_fast_and_classifies_in_background() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true SHIM_CLAUDE_SLEEP=2 SHIM_CLAUDE_OUTPUT="$GOOD"
  local t0 ms out
  t0=$(date +%s%N)
  out=$(submit "добавь экспорт отчёта в CSV") # $( ) waits for stdout AND stderr writers
  ms=$((($(date +%s%N) - t0) / 1000000))
  assert_eq "$out" "" || return 1
  ((ms < 1000)) || { fail "hook took ${ms}ms (classifier sleeps 2s)"; return 1; }
  assert_eq "$(st stage)" "pending" &&
    wait_classified &&
    assert_eq "$(st stage)" "done" &&
    assert_eq "$(st slug)" "csv-report-export" &&
    assert_contains "$(calls)" "setTabColor #27ae60" &&
    assert_contains "$(calls)" "KTAB_NESTED=1"
}

test_second_prompt_emits_title_once() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true
  "$KTAB" state-set sess-1 stage=done slug=csv-report-export color='#27ae60' color_source=auto
  assert_eq "$(submit "next")" '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","sessionTitle":"csv-report-export"}}' &&
    assert_eq "$(submit "third")" "" &&
    assert_eq "$(st stage)" "titled"
}

test_manual_name_gets_colour_but_never_title() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true SHIM_CLAUDE_OUTPUT='{"type":"bug","slug":"fix-tab-crash"}'
  "$KTAB" state-set sess-1 name_source=manual
  assert_eq "$(submit "почини падение" extension-fix)" "" &&
    wait_classified &&
    assert_contains "$(calls)" "setTabColor #c0392b" &&
    assert_eq "$(submit "again" extension-fix)" ""
}

test_launch_name_flag_counts_as_manual() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true KTAB_NAME_SET=1 SHIM_CLAUDE_OUTPUT="$GOOD"
  submit "x" >/dev/null && wait_classified && assert_eq "$(submit "y")" ""
}

test_manual_colour_and_name_skip_classifier() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true KTAB_NAME_SET=1 KTAB_COLOR="#2980b9"
  assert_eq "$(submit "hi")" "" &&
    sleep 0.3 &&
    assert_not_contains "$(calls)" "claude"
}

test_auto_mode_off_or_unset_does_nothing() {
  assert_eq "$(submit "hi")" "" || return 1
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=false
  assert_eq "$(submit "hi")" "" &&
    sleep 0.3 &&
    assert_eq "$(calls)" "" &&
    assert_eq "$(st stage)" ""
}

test_by_default_a_failed_pick_is_not_retried() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true SHIM_CLAUDE_RC=1
  submit "x" >/dev/null && wait_classified && submit "y" >/dev/null &&
    sleep 0.3 &&
    assert_eq "$(st stage)" "failed" &&
    assert_eq "$(st attempts)" "1" &&
    assert_eq "$(grep -c '^claude' "$SHIM_LOG")" "1"
}

test_fresh_pending_or_exhausted_failure_does_not_relaunch() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true CLAUDE_PLUGIN_OPTION_AUTO_ATTEMPTS=3
  "$KTAB" state-set sess-1 stage=failed attempts=3
  "$KTAB" state-set sess-2 stage=pending attempts=1 pending_at="$(date +%s)"
  submit "hi" >/dev/null && submit "hi" "" sess-2 >/dev/null &&
    sleep 0.3 &&
    assert_eq "$(calls)" ""
}

test_failed_attempt_is_retried_when_attempts_allow() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true CLAUDE_PLUGIN_OPTION_AUTO_ATTEMPTS=3 SHIM_CLAUDE_OUTPUT="$GOOD"
  "$KTAB" state-set sess-1 stage=failed attempts=1
  submit "добавь экспорт" >/dev/null && wait_classified &&
    assert_eq "$(st stage)" "done" &&
    assert_eq "$(st attempts)" "2"
}

test_attempts_stop_at_the_configured_limit() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true CLAUDE_PLUGIN_OPTION_AUTO_ATTEMPTS=3 SHIM_CLAUDE_RC=1
  local i
  for i in 1 2 3 4; do
    submit "x" >/dev/null && wait_classified || return 1
  done
  assert_eq "$(st attempts)" "3" &&
    assert_eq "$(st stage)" "failed" &&
    assert_eq "$(grep -c '^claude' "$SHIM_LOG")" "3"
}

test_invalid_attempts_setting_falls_back_to_one() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true SHIM_CLAUDE_RC=1
  local v
  for v in 0 abc 99 -2; do
    : >"$SHIM_LOG"
    "$KTAB" state-set sess-1 stage=failed attempts=1
    CLAUDE_PLUGIN_OPTION_AUTO_ATTEMPTS=$v submit "x" >/dev/null
    sleep 0.3
    assert_eq "$(grep -c '^claude' "$SHIM_LOG")" "0" "setting [$v]" || return 1
  done
}

test_stale_pending_from_a_killed_classifier_is_retried() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true CLAUDE_PLUGIN_OPTION_AUTO_ATTEMPTS=2 SHIM_CLAUDE_OUTPUT="$GOOD"
  "$KTAB" state-set sess-1 stage=pending attempts=1 pending_at="$(($(date +%s) - 120))"
  submit "x" >/dev/null && wait_classified &&
    assert_eq "$(st stage)" "done"
}

test_rename_between_prompts_blocks_slug() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true
  "$KTAB" state-set sess-1 stage=done slug=csv-report-export
  assert_eq "$(submit "next" "renamed by user")" "" &&
    assert_eq "$(st name_source)" "manual"
}

test_new_session_after_clear_classifies_again() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true SHIM_CLAUDE_OUTPUT='{"type":"research","slug":"slow-build-cause"}'
  "$KTAB" state-set sess-1 stage=titled slug=csv-report-export
  submit "разберись, почему тормозит сборка" "" sess-9 >/dev/null &&
    wait_classified sess-9 &&
    assert_eq "$(st slug sess-9)" "slow-build-cause" &&
    assert_contains "$(calls)" "setTabColor #8e44ad"
}

test_prompt_is_one_argument_truncated_and_not_evaluated() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true SHIM_CLAUDE_OUTPUT="$GOOD"
  local long
  long="say \"hi\" \$(touch $T/pwned) \`id\`"$'\n'"line2 $(printf 'x%.0s' $(seq 10000))"
  submit "$long" >/dev/null && wait_classified || return 1
  local arg
  arg=$(cat "$SHIM_DIR/last_arg")
  [[ ! -e "$T/pwned" ]] || { fail "prompt was evaluated"; return 1; }
  assert_contains "$arg" 'say "hi" $(touch' &&
    assert_contains "$arg" "line2" &&
    (($(printf '%s' "$arg" | wc -m) < 2600)) || fail "prompt not truncated: $(printf '%s' "$arg" | wc -m) chars"
}

test_nested_guard_does_nothing() {
  export KTAB_NESTED=1 CLAUDE_PLUGIN_OPTION_AUTO_MODE=true
  "$KTAB" state-set sess-1 stage=done slug=csv-report-export
  assert_eq "$(submit "hi")" "" && sleep 0.3 && assert_eq "$(calls)" ""
}
