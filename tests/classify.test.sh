# U4: background classifier.

CLASSIFY="$REPO/plugin/scripts/classify.sh"

run_classify() { # run_classify <prompt> -> runs synchronously like the detached child would
  local f="$T/prompt"
  printf '%s' "$1" >"$f"
  "$KTAB" state-set sess-1 stage=pending
  "$CLASSIFY" sess-1 "$f" </dev/null >/dev/null 2>&1
}

test_reply_wrapped_in_text_or_markdown_is_parsed() {
  export SHIM_CLAUDE_OUTPUT=$'Sure!\n```json\n{"type": "feature", "slug": "csv-report-export"}\n```'
  run_classify "добавь экспорт" &&
    assert_eq "$(st stage)" "done" &&
    assert_eq "$(st slug)" "csv-report-export" &&
    assert_eq "$(st type)" "feature" &&
    assert_eq "$(st color)" "#27ae60" &&
    assert_eq "$(st color_source)" "auto" &&
    assert_contains "$(calls)" "setTabColor #27ae60" &&
    [[ ! -e "$T/prompt" ]] || fail "prompt file not removed"
}

test_invalid_replies_fail_without_painting() {
  local reply
  for reply in '{"type":"weird","slug":"ok-slug"}' '{"type":"bug|feature","slug":"ok-slug"}' '{"type":"bug","slug":"Bad Slug!"}' \
    '{"type":"bug","slug":"one"}' 'no json at all' \
    '{"type":"bug","slug":"aaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbbbbbb"}'; do
    : >"$SHIM_LOG"
    export SHIM_CLAUDE_OUTPUT="$reply"
    run_classify "x"
    assert_eq "$(st stage)" "failed" "reply: $reply" || return 1
    assert_not_contains "$(calls)" "setTabColor" || return 1
  done
}

test_long_slug_is_cut_to_three_words() {
  export SHIM_CLAUDE_OUTPUT='{"type":"devops","slug":"docker-compose-local-setup"}'
  run_classify "настрой docker compose" &&
    assert_eq "$(st stage)" "done" &&
    assert_eq "$(st slug)" "docker-compose-local"
}

test_claude_failure_marks_failed() {
  export SHIM_CLAUDE_RC=1 SHIM_CLAUDE_OUTPUT='{"type":"bug","slug":"fix-it"}'
  run_classify "x" && assert_eq "$(st stage)" "failed" && assert_not_contains "$(calls)" "setTabColor"
}

test_timeout_marks_failed() {
  export SHIM_CLAUDE_SLEEP=3 KTAB_CLASSIFY_TIMEOUT=1 SHIM_CLAUDE_OUTPUT='{"type":"bug","slug":"fix-it"}'
  run_classify "x" && assert_eq "$(st stage)" "failed"
}

test_manual_colour_is_not_repainted() {
  export SHIM_CLAUDE_OUTPUT='{"type":"bug","slug":"fix-tab-crash"}'
  "$KTAB" state-set sess-1 color='#2980b9' color_source=manual
  run_classify "x" &&
    assert_eq "$(st slug)" "fix-tab-crash" &&
    assert_eq "$(st color)" "#2980b9" &&
    assert_not_contains "$(calls)" "setTabColor"
}

test_dead_owner_skips_paint_but_keeps_slug() {
  export SHIM_CLAUDE_OUTPUT='{"type":"bug","slug":"fix-tab-crash"}'
  sleep 0 &
  local dead=$!
  wait "$dead"
  "$KTAB" state-set sess-1 owner_pid="$dead"
  run_classify "x" &&
    assert_eq "$(st stage)" "done" &&
    assert_eq "$(st slug)" "fix-tab-crash" &&
    assert_not_contains "$(calls)" "setTabColor"
}

test_live_owner_allows_paint() {
  export SHIM_CLAUDE_OUTPUT='{"type":"refactor","slug":"split-parser-module"}'
  "$KTAB" state-set sess-1 owner_pid="$$"
  run_classify "x" && assert_contains "$(calls)" "setTabColor #2980b9"
}

test_devops_reply_paints_white_and_prompt_explains_types() {
  export SHIM_CLAUDE_OUTPUT='{"type":"devops","slug":"nginx-cert-renewal"}'
  run_classify "обнови сертификаты на сервере" &&
    assert_eq "$(st type)" "devops" &&
    assert_contains "$(calls)" "setTabColor #ffffff" &&
    assert_contains "$(cat "$SHIM_DIR/last_arg")" "- devops:"
}

test_nested_call_flags() {
  export SHIM_CLAUDE_OUTPUT='{"type":"bug","slug":"fix-it"}'
  run_classify "x" &&
    assert_contains "$(calls)" "[--model] [haiku]" &&
    assert_contains "$(calls)" "[--setting-sources] []" &&
    assert_contains "$(calls)" "KTAB_NESTED=1" &&
    assert_eq "$(cat "$SHIM_DIR/argc")" "$(grep '^claude' "$SHIM_LOG" | grep -o '\[' | wc -l)"
}
