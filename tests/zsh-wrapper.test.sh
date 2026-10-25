# U2: -C/--color in the claude launcher.

# Runs ktab_claude in a clean zsh with the shims on PATH; stderr goes to $T/stderr.
launch() {
  zsh -fc 'source "$1"; shift; ktab_claude "$@"' _ "$REPO/shell/claude-konsole.zsh" "$@" 2>"$T/stderr"
}

claude_line() { grep '^claude' "$SHIM_LOG"; }
env_line() { grep '^env' "$SHIM_LOG"; }
set_calls() { grep 'setTabColor' "$SHIM_LOG"; }

test_name_and_colour_flags() {
  launch -n extension-fix -C purple &&
    assert_eq "$(claude_line)" "claude [-n] [extension-fix]" &&
    assert_contains "$(env_line)" "KTAB_COLOR=#8e44ad" &&
    assert_contains "$(env_line)" "KTAB_NAME_SET=1" &&
    assert_eq "$(set_calls)" $'qdbus6 :1.99 /Sessions/7 setTabColor #8e44ad\nqdbus6 :1.99 /Sessions/7 setTabColor '
}

test_long_and_equals_forms() {
  launch --color=red fix && assert_eq "$(claude_line)" "claude [fix]" &&
    assert_contains "$(env_line)" "KTAB_COLOR=#c0392b" &&
    : >"$SHIM_LOG" &&
    launch --color red && assert_contains "$(env_line)" "KTAB_COLOR=#c0392b" &&
    : >"$SHIM_LOG" &&
    launch -C=red && assert_contains "$(env_line)" "KTAB_COLOR=#c0392b"
}

test_name_forms_set_flag() {
  local f
  for f in --name=x '-nx'; do
    : >"$SHIM_LOG"
    launch "$f" && assert_contains "$(env_line)" "KTAB_NAME_SET=1" || return 1
  done
  : >"$SHIM_LOG"
  launch --name x && assert_contains "$(env_line)" "KTAB_NAME_SET=1"
}

test_no_flags_leaves_env_unset_and_restores_colour() {
  set_tab_color "#27ae60"
  launch hello &&
    assert_eq "$(claude_line)" "claude [hello]" &&
    assert_contains "$(env_line)" "KTAB_COLOR=<unset>" &&
    assert_contains "$(env_line)" "KTAB_NAME_SET=<unset>" &&
    assert_eq "$(set_calls)" "qdbus6 :1.99 /Sessions/7 setTabColor #27ae60"
}

test_uncoloured_tab_is_reset_with_empty_string() {
  launch hello &&
    assert_eq "$(set_calls)" "qdbus6 :1.99 /Sessions/7 setTabColor "
}

test_unknown_colour_warns_and_still_launches() {
  launch -C notacolor hi &&
    assert_eq "$(claude_line)" "claude [hi]" &&
    assert_contains "$(env_line)" "KTAB_COLOR=<unset>" &&
    assert_eq "$(wc -l <"$T/stderr")" "1" &&
    assert_contains "$(cat "$T/stderr")" "notacolor"
}

test_outside_konsole_warns_and_skips_dbus() {
  unset KONSOLE_DBUS_SESSION
  launch -C purple &&
    assert_eq "$(claude_line)" "claude" &&
    assert_eq "$(grep -c qdbus6 "$SHIM_LOG")" "0" &&
    assert_eq "$(wc -l <"$T/stderr")" "1"
}

test_args_after_double_dash_and_flag_values_untouched() {
  launch -p "-C purple" -- -C red &&
    assert_eq "$(claude_line)" "claude [-p] [-C purple] [--] [-C] [red]" &&
    assert_contains "$(env_line)" "KTAB_COLOR=<unset>"
}

test_exit_code_preserved_and_colour_restored() {
  export SHIM_CLAUDE_RC=3
  launch -C red
  assert_eq "$?" "3" &&
    assert_eq "$(set_calls | tail -1)" "qdbus6 :1.99 /Sessions/7 setTabColor "
}

# R3: an account switch like the one in ~/.zshrc keeps working on top of the launcher.
ZSHRC_CLAUDE_FIXTURE='claude() {
  local flags=(--allow-dangerously-skip-permissions)
  local run=(command claude)
  (( $+functions[ktab_claude] )) && run=(ktab_claude)
  case "$PWD/" in
    "$HOME"/work/*) CLAUDE_CONFIG_DIR="$HOME/.claude-work" "${run[@]}" "${flags[@]}" "$@" ;;
    *) "${run[@]}" "${flags[@]}" "$@" ;;
  esac
}'

test_zshrc_function_keeps_account_selection() {
  local fn=$ZSHRC_CLAUDE_FIXTURE
  mkdir -p "$T/home/work/proj"
  (cd "$T/home/work/proj" && HOME="$T/home" zsh -fc "source '$REPO/shell/claude-konsole.zsh'; $fn; claude -C red x" 2>/dev/null) &&
    assert_eq "$(claude_line)" "claude [--allow-dangerously-skip-permissions] [x]" &&
    assert_contains "$(env_line)" "CLAUDE_CONFIG_DIR=$T/home/.claude-work" &&
    assert_contains "$(env_line)" "KTAB_COLOR=#c0392b"
}
