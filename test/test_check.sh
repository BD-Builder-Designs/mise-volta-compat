#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/bin/mise-volta-compat"
PASS=0
FAIL=0
TMPDIR_BASE="$(mktemp -d)"

cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

make_test_dir() {
  local dir="$TMPDIR_BASE/$1"
  mkdir -p "$dir"
  echo "$dir"
}

assert_silent() {
  local label="$1" dir="$2"
  local output
  output=$(cd "$dir" && "$SCRIPT" check 2>&1) || true
  if [[ -z "$output" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected silent, got: $output)"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local label="$1" dir="$2" expected="$3"
  local output
  output=$(cd "$dir" && "$SCRIPT" check 2>&1) || true
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
  local label="$1" dir="$2" expected="$3"
  local actual=0
  (cd "$dir" && "$SCRIPT" check) >/dev/null 2>&1 || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== check subcommand tests ==="

# jq not on PATH → silent exit 0
# Build a fake bin dir that has bash/env but no jq
dir=$(make_test_dir "no-jq")
no_jq_bin="$TMPDIR_BASE/no-jq-bin"
mkdir -p "$no_jq_bin"
ln -sf "$(command -v bash)" "$no_jq_bin/bash"
ln -sf "$(command -v env)"  "$no_jq_bin/env"
echo '{"name": "test", "volta": {"node": "20.0.0"}}' > "$dir/package.json"
output=$(cd "$dir" && PATH="$no_jq_bin" "$SCRIPT" check 2>&1) || true
if [[ -z "$output" ]]; then
  echo "  PASS: no jq with restricted PATH is silent"
  PASS=$((PASS + 1))
else
  echo "  FAIL: no jq with restricted PATH should be silent (got: $output)"
  FAIL=$((FAIL + 1))
fi

# No package.json → silent exit 0
dir=$(make_test_dir "no-pkg")
assert_silent "no package.json is silent" "$dir"
assert_exit_code "no package.json exits 0" "$dir" 0

# package.json without volta → silent exit 0
dir=$(make_test_dir "no-volta")
echo '{"name": "test"}' > "$dir/package.json"
assert_silent "no volta key is silent" "$dir"
assert_exit_code "no volta key exits 0" "$dir" 0

# package.json with volta, no .mise.toml → nudge
dir=$(make_test_dir "needs-migration")
echo '{"name": "test", "volta": {"node": "20.11.0"}}' > "$dir/package.json"
assert_output_contains "prints nudge when no .mise.toml" "$dir" "mise-volta-compat migrate"
assert_exit_code "nudge exits 0" "$dir" 0

# package.json with volta, .mise.toml exists → silent exit 0
dir=$(make_test_dir "already-migrated")
echo '{"name": "test", "volta": {"node": "20.11.0"}}' > "$dir/package.json"
printf '[tools]\nnode = "20.11.0"\n' > "$dir/.mise.toml"
assert_silent "already migrated is silent" "$dir"
assert_exit_code "already migrated exits 0" "$dir" 0

# Node >= 16 with MISE_ARCH override → warns it can be removed
dir=$(make_test_dir "stale-arch")
printf '[env]\nMISE_ARCH = "x86_64"\n\n[tools]\nnode = "20.11.0"\n' > "$dir/.mise.toml"
assert_output_contains "stale MISE_ARCH warns" "$dir" "override can be removed"
assert_exit_code "stale MISE_ARCH exits 0" "$dir" 0

# Node >= 16 with MISE_ARCH, no package.json at all → still warns
dir=$(make_test_dir "stale-arch-no-pkg")
printf '[env]\nMISE_ARCH = "x86_64"\n\n[tools]\nnode = "17.1.0"\n' > "$dir/.mise.toml"
assert_output_contains "stale MISE_ARCH warns without package.json" "$dir" "override can be removed"

# Node < 16 with MISE_ARCH override → silent (override is needed)
dir=$(make_test_dir "needed-arch")
printf '[env]\nMISE_ARCH = "x86_64"\n\n[tools]\nnode = "14.21.3"\n' > "$dir/.mise.toml"
assert_silent "needed MISE_ARCH is silent" "$dir"

# .mise.toml without MISE_ARCH, Node >= 16 → silent
dir=$(make_test_dir "no-arch-modern")
printf '[tools]\nnode = "20.11.0"\n' > "$dir/.mise.toml"
assert_silent "no arch override modern node is silent" "$dir"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
