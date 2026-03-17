#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/bin/mise-volta-compat"
PASS=0
FAIL=0

assert_contains() {
  local label="$1" output="$2" expected="$3"
  if echo "$output" | grep -qF "$expected"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected to contain: $expected"
    echo "    got: $output"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local label="$1" expected="$2"
  shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== CLI dispatch tests ==="

# No args shows help
output=$("$SCRIPT" 2>&1 || true)
assert_contains "no args shows usage" "$output" "Usage: mise-volta-compat"
assert_contains "no args shows check command" "$output" "check"
assert_contains "no args shows migrate command" "$output" "migrate"
assert_contains "no args shows version command" "$output" "version"

# Unknown subcommand shows help
output=$("$SCRIPT" nonsense 2>&1 || true)
assert_contains "unknown subcommand shows usage" "$output" "Usage: mise-volta-compat"

# Version subcommand
output=$("$SCRIPT" version 2>&1)
assert_contains "version prints something" "$output" "dev"

# Exit codes
assert_exit_code "no args exits 1" 1 "$SCRIPT"
assert_exit_code "unknown subcommand exits 1" 1 "$SCRIPT" nonsense
assert_exit_code "version exits 0" 0 "$SCRIPT" version

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
