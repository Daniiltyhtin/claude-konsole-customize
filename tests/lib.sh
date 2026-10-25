# Shared helpers for test files; sourced by tests/run.sh.

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KTAB="$REPO/plugin/bin/ktab"

setup() {
  T=$(mktemp -d)
  export XDG_STATE_HOME="$T/state"
  export SHIM_DIR="$T/shim"
  export SHIM_LOG="$T/calls.log"
  mkdir -p "$SHIM_DIR"
  : >"$SHIM_LOG"
  export PATH="$REPO/tests/shims:$ORIG_PATH"
  export KONSOLE_DBUS_SERVICE=":1.99"
  export KONSOLE_DBUS_SESSION="/Sessions/7"
  # Hooks must not see the real claude session that may be running these tests.
  export KTAB_SCAN_STOP_PID=$$
  unset KTAB_COLOR KTAB_NAME_SET KTAB_NESTED CLAUDE_PLUGIN_OPTION_AUTO_MODE CLAUDE_PLUGIN_OPTION_AUTO_ATTEMPTS
}

teardown() {
  rm -rf "$T"
}

fail() {
  echo "    FAIL: $*" >&2
  return 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]${3:+ ($3)}"
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected to contain [$2], got [$1]"
}

assert_not_contains() {
  [[ "$1" != *"$2"* ]] || fail "expected NOT to contain [$2], got [$1]"
}

# Calls recorded by the qdbus6/claude shims, one per line.
calls() {
  cat "$SHIM_LOG"
}

# Session state field; session id defaults to sess-1.
st() { "$KTAB" state-get "${2:-sess-1}" "$1"; }

# Simulated current tab colour as Konsole would report it.
set_tab_color() {
  printf '%s' "$1" >"$SHIM_DIR/tab_color"
}
