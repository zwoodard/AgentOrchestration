#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTINUE="$SCRIPT_DIR/../scripts/continue.sh"

PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        ((PASS++)) || true
    else
        echo "  FAIL: $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        ((FAIL++)) || true
    fi
}

assert_contains() {
    local desc="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -qF -- "$expected"; then
        echo "  PASS: $desc"
        ((PASS++)) || true
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: '$expected'"
        ((FAIL++)) || true
    fi
}

echo "=== continue tests ==="

# Create test worktrees dir
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

WORKTREES_DIR="$TEST_DIR/worktrees"
mkdir -p "$WORKTREES_DIR/product-a--bd-a1b2--fix-bug"

# Create test repos.yaml
cat > "$TEST_DIR/repos.yaml" <<YAML
repos:
  product-a:
    url: https://example.com/product-a
    permission_mode: managed
    allowed_tools:
      - "Read"
      - "Edit"
YAML

cat > "$TEST_DIR/defaults.yaml" <<YAML
defaults:
  permission_mode: managed
  allowed_tools:
    - "Read"
YAML

# Test: build-command (dry-run — shows what would be executed)
output=$("$CONTINUE" --build-command \
    --task-id "bd-a1b2" \
    --message "Yes, consolidate into middleware" \
    --worktrees-dir "$WORKTREES_DIR" \
    --repos-yaml "$TEST_DIR/repos.yaml" \
    --defaults-yaml "$TEST_DIR/defaults.yaml" 2>&1)
assert_contains "command has --continue" "--continue" "$output"
assert_contains "command has -p" "-p" "$output"
assert_contains "command has message" "Yes, consolidate into middleware" "$output"
assert_contains "command has permission flags" "--permission-mode" "$output"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
