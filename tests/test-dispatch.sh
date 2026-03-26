#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH="$SCRIPT_DIR/../scripts/dispatch.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

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
        echo "    actual: '$actual'"
        ((FAIL++)) || true
    fi
}

echo "=== dispatch tests ==="

# Create test config
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

cat > "$TEST_DIR/repos.yaml" <<YAML
repos:
  product-a:
    url: https://example.com/product-a
    platform: github
    default_branch: main
    permission_mode: managed
    autonomy: medium
    allowed_tools:
      - "Read"
      - "Edit"
      - "Bash(npm *)"
    denied_tools:
      - "Bash(git push --force *)"
  product-b:
    url: https://example.com/product-b
    platform: github
    default_branch: main
    permission_mode: yolo
    autonomy: high
YAML

cat > "$TEST_DIR/defaults.yaml" <<YAML
defaults:
  permission_mode: managed
  autonomy: medium
  max_worktrees: 3
  default_branch: main
  allowed_tools:
    - "Read"
    - "Edit"
    - "Write"
    - "Bash(git *)"
YAML

cat > "$TEST_DIR/agent-template.md" <<'TMPL'
You are working on task {{TASK_ID}} in repo {{REPO_NAME}}.
## Task
{{TASK_BRIEF}}
## Autonomy Level: {{AUTONOMY}}
{{AUTONOMY_INSTRUCTIONS}}
TMPL

# Test: build-prompt (dry-run mode)
echo "-- build-prompt --"
output=$("$DISPATCH" --build-prompt \
    --task-id "bd-a1b2" \
    --repo "product-a" \
    --brief "Fix the billing bug" \
    --template "$TEST_DIR/agent-template.md" \
    --repos-yaml "$TEST_DIR/repos.yaml" \
    --defaults-yaml "$TEST_DIR/defaults.yaml" 2>&1)
assert_contains "prompt contains task ID" "bd-a1b2" "$output"
assert_contains "prompt contains repo name" "product-a" "$output"
assert_contains "prompt contains task brief" "Fix the billing bug" "$output"
assert_contains "prompt contains autonomy" "medium" "$output"

# Test: build-flags for managed mode
echo "-- build-flags managed --"
output=$("$DISPATCH" --build-flags \
    --repo "product-a" \
    --repos-yaml "$TEST_DIR/repos.yaml" \
    --defaults-yaml "$TEST_DIR/defaults.yaml" 2>&1)
assert_contains "managed mode has --permission-mode" "--permission-mode dontAsk" "$output"
assert_contains "managed mode has --allowedTools" "--allowedTools" "$output"
assert_contains "includes allowed tool" "Read" "$output"

# Test: build-flags for yolo mode
echo "-- build-flags yolo --"
output=$("$DISPATCH" --build-flags \
    --repo "product-b" \
    --repos-yaml "$TEST_DIR/repos.yaml" \
    --defaults-yaml "$TEST_DIR/defaults.yaml" 2>&1)
assert_contains "yolo mode has skip permissions" "--dangerously-skip-permissions" "$output"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
