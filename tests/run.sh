#!/usr/bin/env bash
# Runs every test_* function from tests/*.test.sh in an isolated subshell.
# Usage: tests/run.sh [file-pattern]

ORIG_PATH="$PATH"
export ORIG_PATH
DIR=$(cd "$(dirname "$0")" && pwd)
pass=0
failed=0
failures=()

for file in "$DIR"/*${1:-}*.test.sh; do
  [[ -e "$file" ]] || continue
  echo "== $(basename "$file")"
  if ! bash -n "$file"; then
    echo "  FAIL syntax error"
    failed=$((failed + 1))
    failures+=("$(basename "$file"):syntax")
    continue
  fi
  for fn in $(bash -c "source '$DIR/lib.sh'; source '$file'; declare -F" | awk '{print $3}' | grep '^test_'); do
    if (
      set -u
      source "$DIR/lib.sh"
      source "$file"
      setup
      trap teardown EXIT
      "$fn"
    ); then
      echo "  ok   $fn"
      pass=$((pass + 1))
    else
      echo "  FAIL $fn"
      failed=$((failed + 1))
      failures+=("$(basename "$file"):$fn")
    fi
  done
done

echo
echo "passed: $pass, failed: $failed"
if ((failed > 0)); then
  printf '  %s\n' "${failures[@]}"
  exit 1
fi
((pass > 0)) || { echo "no tests ran"; exit 1; }

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "$DIR/../plugin/bin/ktab" "$DIR"/../plugin/scripts/*.sh "$DIR"/../konsole/*.sh "$DIR/../install.sh" 2>/dev/null || exit 1
fi
