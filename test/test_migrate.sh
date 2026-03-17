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

assert_file_contains() {
  local label="$1" file="$2" expected="$3"
  if grep -qF "$expected" "$file" 2>/dev/null; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected $file to contain: $expected"
    echo "    got: $(cat "$file" 2>/dev/null || echo '<file not found>')"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_contains() {
  local label="$1" file="$2" unexpected="$3"
  if ! grep -qF "$unexpected" "$file" 2>/dev/null; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected $file NOT to contain: $unexpected"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local label="$1" file="$2"
  if [[ -f "$file" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (file not found: $file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local label="$1" file="$2"
  if [[ ! -f "$file" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (file should not exist: $file)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== migrate subcommand tests ==="

# jq not on PATH → error with helpful message
# Build a fake bin dir that has bash/env but no jq
dir=$(make_test_dir "no-jq")
no_jq_bin="$TMPDIR_BASE/no-jq-bin"
mkdir -p "$no_jq_bin"
ln -sf "$(command -v bash)" "$no_jq_bin/bash"
ln -sf "$(command -v env)"  "$no_jq_bin/env"
echo '{"name": "test", "volta": {"node": "20.0.0"}}' > "$dir/package.json"
output=$(cd "$dir" && PATH="$no_jq_bin" "$SCRIPT" migrate 2>&1) && rc=0 || rc=$?
assert_contains "no jq shows error" "$output" "jq is required"
if [[ "$rc" -ne 0 ]]; then echo "  PASS: no jq exits non-zero"; PASS=$((PASS + 1)); else echo "  FAIL: no jq should exit non-zero"; FAIL=$((FAIL + 1)); fi

# No package.json → error
dir=$(make_test_dir "no-pkg")
output=$(cd "$dir" && "$SCRIPT" migrate 2>&1) && rc=0 || rc=$?
assert_contains "no package.json errors" "$output" "No package.json"
if [[ "$rc" -ne 0 ]]; then echo "  PASS: exits non-zero"; PASS=$((PASS + 1)); else echo "  FAIL: should exit non-zero"; FAIL=$((FAIL + 1)); fi

# No volta key → info message, no .mise.toml created
dir=$(make_test_dir "no-volta")
echo '{"name": "test"}' > "$dir/package.json"
output=$(cd "$dir" && "$SCRIPT" migrate 2>&1)
assert_contains "no volta key prints info" "$output" "No volta config"
assert_file_not_exists "no .mise.toml created" "$dir/.mise.toml"

# .mise.toml already exists → skip
dir=$(make_test_dir "already-exists")
echo '{"name": "test", "volta": {"node": "20.11.0"}}' > "$dir/package.json"
echo '[tools]' > "$dir/.mise.toml"
output=$(cd "$dir" && "$SCRIPT" migrate 2>&1)
assert_contains "existing .mise.toml skips" "$output" "already exists"

# Successful migration: node + yarn
dir=$(make_test_dir "basic-migration")
cat > "$dir/package.json" << 'PKGJSON'
{
  "name": "my-app",
  "version": "1.0.0",
  "volta": {
    "node": "20.11.0",
    "yarn": "1.22.19"
  }
}
PKGJSON
output=$(cd "$dir" && "$SCRIPT" migrate 2>&1)
assert_file_exists ".mise.toml created" "$dir/.mise.toml"
assert_file_contains ".mise.toml has [tools] header" "$dir/.mise.toml" "[tools]"
assert_file_contains ".mise.toml has node version" "$dir/.mise.toml" 'node = "20.11.0"'
assert_file_contains ".mise.toml has yarn version" "$dir/.mise.toml" 'yarn = "1.22.19"'
assert_file_not_contains "node 20 has no MISE_ARCH" "$dir/.mise.toml" "MISE_ARCH"
assert_file_contains "package.json unchanged" "$dir/package.json" '"volta"'
assert_contains "prints success" "$output" "Created .mise.toml"

# Migration with all four known keys
dir=$(make_test_dir "all-keys")
cat > "$dir/package.json" << 'PKGJSON'
{
  "name": "full-app",
  "volta": {
    "node": "22.0.0",
    "npm": "10.5.0",
    "yarn": "4.1.0",
    "pnpm": "9.0.0"
  }
}
PKGJSON
output=$(cd "$dir" && "$SCRIPT" migrate 2>&1)
assert_file_contains "has node" "$dir/.mise.toml" 'node = "22.0.0"'
assert_file_contains "has npm" "$dir/.mise.toml" 'npm = "10.5.0"'
assert_file_contains "has yarn" "$dir/.mise.toml" 'yarn = "4.1.0"'
assert_file_contains "has pnpm" "$dir/.mise.toml" 'pnpm = "9.0.0"'

# Node < 16 adds MISE_ARCH override
dir=$(make_test_dir "old-node")
cat > "$dir/package.json" << 'PKGJSON'
{
  "name": "legacy-app",
  "volta": {
    "node": "14.21.3",
    "yarn": "1.22.19"
  }
}
PKGJSON
output=$(cd "$dir" && "$SCRIPT" migrate 2>&1)
assert_file_contains "old node has [env] section" "$dir/.mise.toml" "[env]"
assert_file_contains "old node has MISE_ARCH" "$dir/.mise.toml" 'MISE_ARCH = "x86_64"'
assert_file_contains "old node has [tools] section" "$dir/.mise.toml" "[tools]"
assert_file_contains "old node has node version" "$dir/.mise.toml" 'node = "14.21.3"'
assert_contains "old node warns about arch" "$output" "ARM64"

# Node >= 16 does NOT add MISE_ARCH override
dir=$(make_test_dir "modern-node")
cat > "$dir/package.json" << 'PKGJSON'
{
  "name": "modern-app",
  "volta": {
    "node": "16.0.0"
  }
}
PKGJSON
output=$(cd "$dir" && "$SCRIPT" migrate 2>&1)
assert_file_not_contains "modern node has no MISE_ARCH" "$dir/.mise.toml" "MISE_ARCH"
assert_file_not_contains "modern node has no [env]" "$dir/.mise.toml" "[env]"

# Node 15.x (edge case, still < 16)
dir=$(make_test_dir "node-15")
cat > "$dir/package.json" << 'PKGJSON'
{
  "name": "node15-app",
  "volta": {
    "node": "15.14.0"
  }
}
PKGJSON
output=$(cd "$dir" && "$SCRIPT" migrate 2>&1)
assert_file_contains "node 15 has MISE_ARCH" "$dir/.mise.toml" 'MISE_ARCH = "x86_64"'

# Unknown key produces warning on stderr
dir=$(make_test_dir "unknown-key")
cat > "$dir/package.json" << 'PKGJSON'
{
  "name": "exotic",
  "volta": {
    "node": "20.0.0",
    "deno": "1.40.0"
  }
}
PKGJSON
output=$(cd "$dir" && "$SCRIPT" migrate 2>&1)
assert_contains "warns about unknown key" "$output" "deno"
assert_file_contains "unknown key still written" "$dir/.mise.toml" 'deno = "1.40.0"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
