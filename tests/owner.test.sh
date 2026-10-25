# Owner detection: the hooks find the claude process above them and ignore
# print-mode (claude -p) and nested sessions.

# A fake "claude" process (comm=claude) that runs a command as its child and
# records its own pid; extra args land in its /proc cmdline.
make_fake_claude() {
  mkdir -p "$T/fake"
  cat >"$T/fake/claude" <<'EOF'
#!/bin/bash
echo $$ >>"$FAKE_PIDS"
"$FAKE_CMD" "${FAKE_ARGS[@]}" <"$FAKE_IN"
EOF
  chmod +x "$T/fake/claude"
  export FAKE_PIDS="$T/fake/pids" FAKE_IN="$T/fake/in.json"
}

hook_json() { # hook_json <event> <source-or-empty> <prompt>
  jq -nc --arg e "$1" --arg s "$2" --arg p "$3" \
    '{session_id: "sess-1", hook_event_name: $e, source: $s, prompt: $p}' >"$FAKE_IN"
}

test_interactive_owner_pid_is_recorded() {
  make_fake_claude
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true SHIM_CLAUDE_OUTPUT='{"type":"bug","slug":"fix-it"}'
  export FAKE_CMD="$REPO/plugin/scripts/prompt-submit.sh"
  hook_json UserPromptSubmit "" "почини"
  "$T/fake/claude" --allow-dangerously-skip-permissions || return 1
  assert_eq "$(st owner_pid)" "$(head -1 "$FAKE_PIDS")"
}

test_no_claude_ancestor_leaves_owner_empty() {
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true SHIM_CLAUDE_OUTPUT='{"type":"bug","slug":"fix-it"}'
  jq -nc '{session_id: "sess-1", prompt: "x"}' | "$REPO/plugin/scripts/prompt-submit.sh" &&
    assert_eq "$(st stage)" "pending" &&
    assert_eq "$(st owner_pid)" ""
}

test_print_mode_session_is_ignored() {
  make_fake_claude
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true KTAB_COLOR="#c0392b"
  export FAKE_CMD="$REPO/plugin/scripts/prompt-submit.sh"
  hook_json UserPromptSubmit "" "x"
  "$T/fake/claude" -p "x" || return 1
  export FAKE_CMD="$REPO/plugin/scripts/session-start.sh"
  hook_json SessionStart startup ""
  "$T/fake/claude" --print || return 1
  sleep 0.3
  assert_eq "$(st stage)" "" &&
    assert_eq "$(st color)" "" &&
    assert_eq "$(calls)" ""
}

test_nested_claude_session_is_ignored() {
  make_fake_claude
  export CLAUDE_PLUGIN_OPTION_AUTO_MODE=true KTAB_COLOR="#c0392b"
  # outer fake claude runs the inner fake claude, which runs the hook
  export FAKE_CMD="$T/fake/claude" FAKE_INNER="$REPO/plugin/scripts/session-start.sh"
  cat >"$T/fake/inner" <<'EOF'
#!/bin/bash
FAKE_CMD="$FAKE_INNER" exec "$(dirname "$0")/claude"
EOF
  chmod +x "$T/fake/inner"
  export FAKE_CMD="$T/fake/inner"
  hook_json SessionStart startup ""
  "$T/fake/claude" || return 1
  assert_eq "$(wc -l <"$FAKE_PIDS")" "2" "two fake claude levels ran" &&
    assert_eq "$(st color)" "" &&
    assert_eq "$(calls)" ""
}
