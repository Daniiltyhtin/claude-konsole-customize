# U1: ktab core.

test_resolve_named_and_hex_to_same_hex() {
  assert_eq "$("$KTAB" resolve purple)" "#8e44ad" &&
    assert_eq "$("$KTAB" resolve Purple)" "#8e44ad" &&
    assert_eq "$("$KTAB" resolve '#8E44AD')" "#8e44ad"
}

test_resolve_rejects_unknown_and_black() {
  local c
  for c in notacolor '#12345' '' black '#000000' '#zzzzzz'; do
    if "$KTAB" resolve "$c" >/dev/null 2>&1; then fail "accepted [$c]"; return 1; fi
  done
}

test_set_calls_konsole_with_service_session_and_hex() {
  "$KTAB" set purple &&
    assert_eq "$(calls)" "qdbus6 :1.99 /Sessions/7 setTabColor #8e44ad"
}

test_set_outside_konsole_skips_dbus() {
  unset KONSOLE_DBUS_SESSION
  if "$KTAB" set purple 2>/dev/null; then fail "should fail outside Konsole"; return 1; fi
  assert_eq "$(calls)" ""
}

test_in_konsole_requires_dbus_vars() {
  "$KTAB" in-konsole || { fail "expected in Konsole"; return 1; }
  unset KONSOLE_DBUS_SERVICE
  if "$KTAB" in-konsole; then fail "expected not in Konsole"; return 1; fi
}

test_dbus_failure_returns_error_with_empty_stdout() {
  local out
  export SHIM_QDBUS_FAIL=1
  if out=$("$KTAB" set red 2>/dev/null); then fail "expected failure"; return 1; fi
  assert_eq "$out" ""
}

test_get_returns_hex_and_empty_for_no_colour() {
  assert_eq "$("$KTAB" get)" "" "no colour is #000000 in Konsole" &&
    set_tab_color "#27ae60" &&
    assert_eq "$("$KTAB" get)" "#27ae60"
}

test_reset_sends_empty_string_not_black() {
  "$KTAB" reset &&
    assert_eq "$(calls)" "qdbus6 :1.99 /Sessions/7 setTabColor "
}

test_type_color_mapping() {
  assert_eq "$("$KTAB" type-color bug)" "$("$KTAB" resolve red)" &&
    assert_eq "$("$KTAB" type-color feature)" "$("$KTAB" resolve green)" &&
    assert_eq "$("$KTAB" type-color refactor)" "$("$KTAB" resolve blue)" &&
    assert_eq "$("$KTAB" type-color research)" "$("$KTAB" resolve purple)" &&
    assert_eq "$("$KTAB" type-color devops)" "$("$KTAB" resolve white)" &&
    assert_eq "$("$KTAB" type-color other)" "$("$KTAB" resolve gray)" &&
    assert_eq "$("$KTAB" type-color weird)" "$("$KTAB" resolve gray)"
}

test_types_lists_every_type_with_a_colour() {
  assert_eq "$("$KTAB" types | paste -sd ' ')" "bug devops feature other refactor research"
}

test_white_is_in_the_palette() {
  assert_eq "$("$KTAB" resolve white)" "#ffffff"
}

test_type_hints_describe_every_type() {
  local t hints
  hints=$("$KTAB" type-hints)
  for t in $("$KTAB" types); do
    assert_contains "$hints" "- $t:" || return 1
  done
  assert_contains "$hints" "servers"
}

test_state_set_creates_and_merges() {
  "$KTAB" state-set s-1 color='#c0392b' color_source=manual &&
    "$KTAB" state-set s-1 slug=fix-tab-crash &&
    assert_eq "$("$KTAB" state-get s-1 color)" "#c0392b" &&
    assert_eq "$("$KTAB" state-get s-1 color_source)" "manual" &&
    assert_eq "$("$KTAB" state-get s-1 slug)" "fix-tab-crash" &&
    assert_eq "$(ls "$XDG_STATE_HOME/claude-konsole-customize/sessions")" "s-1.json"
}

test_state_get_missing_session_or_field_is_empty() {
  assert_eq "$("$KTAB" state-get nope color)" "" &&
    "$KTAB" state-set s-2 a=1 &&
    assert_eq "$("$KTAB" state-get s-2 missing)" ""
}

test_state_rejects_unsafe_session_id() {
  if "$KTAB" state-set ../evil a=1 2>/dev/null; then fail "accepted path traversal"; return 1; fi
  if "$KTAB" state-get 'a/b' a 2>/dev/null; then fail "accepted slash"; return 1; fi
}

test_state_values_with_quotes_survive() {
  "$KTAB" state-set s-3 'note=he said "hi" $(x)' &&
    assert_eq "$("$KTAB" state-get s-3 note)" 'he said "hi" $(x)'
}
