# U3: SessionStart hook.

HOOK="$REPO/plugin/scripts/session-start.sh"

start() { # start <source> [session_title] -> stdout of the hook
  jq -nc --arg s "$1" --arg t "${2:-}" \
    '{session_id: "sess-1", hook_event_name: "SessionStart", source: $s} + (if $t == "" then {} else {session_title: $t} end)' |
    "$HOOK"
}

test_startup_records_manual_colour_and_name() {
  export KTAB_COLOR="#8e44ad" KTAB_NAME_SET=1
  local out
  out=$(start startup extension-fix) &&
    assert_eq "$out" "" &&
    assert_eq "$(st color)" "#8e44ad" &&
    assert_eq "$(st color_source)" "manual" &&
    assert_eq "$(st name_source)" "manual" &&
    assert_eq "$(calls)" "qdbus6 :1.99 /Sessions/7 setTabColor #8e44ad"
}

test_resume_restores_saved_colour() {
  "$KTAB" state-set sess-1 color='#c0392b' color_source=auto stage=titled title_applied=true slug=fix-crash
  local out
  out=$(start resume fix-crash) &&
    assert_eq "$out" "" &&
    assert_eq "$(calls)" "qdbus6 :1.99 /Sessions/7 setTabColor #c0392b"
}

test_resume_emits_pending_slug_as_title_only_json() {
  "$KTAB" state-set sess-1 color='#27ae60' color_source=auto stage=done slug=csv-report-export
  local out
  out=$(start resume) &&
    assert_eq "$out" '{"hookSpecificOutput":{"hookEventName":"SessionStart","sessionTitle":"csv-report-export"}}' &&
    assert_eq "$(st title_applied)" "true" &&
    assert_eq "$(start resume)" "" "title is emitted once"
}

test_resume_with_manual_colour_overrides_saved() {
  "$KTAB" state-set sess-1 color='#c0392b' color_source=auto
  export KTAB_COLOR="#2980b9"
  start resume >/dev/null &&
    assert_eq "$(st color)" "#2980b9" &&
    assert_eq "$(st color_source)" "manual" &&
    assert_eq "$(calls)" "qdbus6 :1.99 /Sessions/7 setTabColor #2980b9"
}

test_resume_of_named_session_without_state_marks_name_manual() {
  local out
  out=$(start resume "my old name") &&
    assert_eq "$out" "" &&
    assert_eq "$(st name_source)" "manual"
}

test_resume_with_renamed_session_does_not_emit_slug() {
  "$KTAB" state-set sess-1 stage=done slug=csv-report-export
  assert_eq "$(start resume "renamed by user")" "" &&
    assert_eq "$(st name_source)" "manual"
}

test_clear_without_manual_colour_leaves_tab_alone() {
  assert_eq "$(start clear)" "" &&
    assert_eq "$(calls)" ""
}

test_bad_input_and_no_konsole_are_silent() {
  local out
  out=$(echo 'not json' | "$HOOK") && assert_eq "$out" "" || return 1
  out=$(echo '{"source":"resume"}' | "$HOOK") && assert_eq "$out" "" || return 1
  out=$(echo '{"session_id":"../x","source":"resume"}' | "$HOOK") && assert_eq "$out" "" || return 1
  unset KONSOLE_DBUS_SESSION
  "$KTAB" state-set sess-1 color='#c0392b'
  out=$(start resume) && assert_eq "$out" ""
}

test_nested_guard_does_nothing() {
  export KTAB_NESTED=1 KTAB_COLOR="#c0392b"
  assert_eq "$(start startup)" "" &&
    assert_eq "$(calls)" "" &&
    assert_eq "$(st color)" ""
}
