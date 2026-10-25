# U6: rebuild.sh --check (the build itself is verified by a real run + screenshot).

REBUILD="$REPO/konsole/rebuild.sh"

check() { "$REBUILD" --check; }

test_patched_and_current() {
  export SHIM_PACMAN_INSTALLED=26.08.2-1.90 SHIM_PACMAN_REPO=26.08.2-1.1 SHIM_PACMAN_EXTRA=26.08.2-1
  local out
  out=$(check) && assert_contains "$out" "patched and current"
}

test_new_version_available() {
  export SHIM_PACMAN_INSTALLED=26.08.2-1.90 SHIM_PACMAN_REPO=26.08.3-1.1 SHIM_PACMAN_EXTRA=26.08.3-1
  local out
  if out=$(check); then fail "expected non-zero"; return 1; fi
  assert_contains "$out" "new Konsole available (26.08.3-1.1"
}

test_unpatched_installed() {
  export SHIM_PACMAN_INSTALLED=26.08.2-1.1 SHIM_PACMAN_REPO=26.08.2-1.1 SHIM_PACMAN_EXTRA=26.08.2-1
  local out
  if out=$(check); then fail "expected non-zero"; return 1; fi
  assert_contains "$out" "unpatched"
}
