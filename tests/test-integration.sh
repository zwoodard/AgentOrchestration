#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Integration Test ==="
echo "This test uses a local bare git repo as a mock remote."
echo ""

# Setup
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Create a bare repo to serve as "remote"
REMOTE="$TEST_DIR/mock-remote.git"
git init --bare "$REMOTE" 2>/dev/null
WORK="$TEST_DIR/work"
git clone "$REMOTE" "$WORK" 2>/dev/null
cd "$WORK"
git checkout -b main 2>/dev/null
echo "# Mock Project" > README.md
echo "console.log('hello')" > index.js
git add .
git commit -m "initial commit" 2>/dev/null
git push -u origin main 2>/dev/null
cd "$PROJECT_ROOT"

# Create test config pointing to mock remote
TEST_POOL="$TEST_DIR/pool"
TEST_WORKTREES="$TEST_DIR/worktrees"
TEST_LOGS="$TEST_DIR/logs"
mkdir -p "$TEST_POOL" "$TEST_WORKTREES" "$TEST_LOGS"

TEST_REPOS="$TEST_DIR/repos.yaml"
cat > "$TEST_REPOS" <<YAML
repos:
  mock-project:
    url: $REMOTE
    platform: github
    default_branch: main
    pre_clone: true
    max_worktrees: 3
    permission_mode: managed
    autonomy: medium
    allowed_tools:
      - "Read"
      - "Edit"
      - "Bash(git *)"
YAML

TEST_DEFAULTS="$TEST_DIR/defaults.yaml"
cat > "$TEST_DEFAULTS" <<YAML
defaults:
  permission_mode: managed
  autonomy: medium
  max_worktrees: 3
  default_branch: main
  allowed_tools:
    - "Read"
    - "Edit"
YAML

PASS=0
FAIL=0

check() {
    local desc="$1"
    if [[ $? -eq 0 ]]; then
        echo "  PASS: $desc"
        ((PASS++)) || true
    else
        echo "  FAIL: $desc"
        ((FAIL++)) || true
    fi
}

# --- Test 1: Clone repo into pool ---
echo "-- 1. Pool clone --"
"$PROJECT_ROOT/scripts/pool-manage.sh" clone mock-project \
    --repos-yaml "$TEST_REPOS" --pool-dir "$TEST_POOL" 2>/dev/null
[[ -d "$TEST_POOL/mock-project/.git" ]]
check "repo cloned into pool"

# --- Test 2: Create worktree ---
echo "-- 2. Worktree create --"
wt_path=$("$PROJECT_ROOT/scripts/pool-manage.sh" worktree-create mock-project bd-test1 fix-readme \
    --pool-dir "$TEST_POOL" --worktrees-dir "$TEST_WORKTREES" --repos-yaml "$TEST_REPOS" --defaults-yaml "$TEST_DEFAULTS" 2>/dev/null)
[[ -d "$TEST_WORKTREES/mock-project--bd-test1--fix-readme" ]]
check "worktree created"
[[ -f "$TEST_WORKTREES/mock-project--bd-test1--fix-readme/README.md" ]]
check "worktree has repo files"

# --- Test 3: Build agent prompt ---
echo "-- 3. Agent prompt --"
prompt=$("$PROJECT_ROOT/scripts/dispatch.sh" --build-prompt \
    --task-id "bd-test1" --repo "mock-project" --brief "Update the README" \
    --template "$PROJECT_ROOT/config/agent-template.md" \
    --repos-yaml "$TEST_REPOS" --defaults-yaml "$TEST_DEFAULTS" 2>&1)
echo "$prompt" | grep -q "bd-test1"
check "prompt contains task ID"
echo "$prompt" | grep -q "Update the README"
check "prompt contains brief"

# --- Test 4: Build permission flags ---
echo "-- 4. Permission flags --"
flags=$("$PROJECT_ROOT/scripts/dispatch.sh" --build-flags \
    --repo "mock-project" --repos-yaml "$TEST_REPOS" --defaults-yaml "$TEST_DEFAULTS" 2>&1)
echo "$flags" | grep -q "permission-mode"
check "managed mode produces permission flags"

# --- Test 5: Monitor pattern detection ---
echo "-- 5. Monitor patterns --"
blocked=$("$PROJECT_ROOT/scripts/monitor.sh" --parse-line "BLOCKED: Should I refactor?")
echo "$blocked" | grep -q "BLOCKED"
check "detects BLOCKED pattern"

done_msg=$("$PROJECT_ROOT/scripts/monitor.sh" --parse-line "DONE: Finished. Branch: bd-test1/fix")
echo "$done_msg" | grep -q "DONE"
check "detects DONE pattern"

# --- Test 6: Build continue command ---
echo "-- 6. Continue command --"
cmd=$("$PROJECT_ROOT/scripts/continue.sh" --build-command \
    --task-id "bd-test1" --message "Yes, go ahead" \
    --worktrees-dir "$TEST_WORKTREES" --repos-yaml "$TEST_REPOS" --defaults-yaml "$TEST_DEFAULTS" 2>&1)
echo "$cmd" | grep -q "continue"
check "continue command includes --continue"

# --- Test 7: Pool status ---
echo "-- 7. Pool status --"
status=$("$PROJECT_ROOT/scripts/pool-manage.sh" status \
    --pool-dir "$TEST_POOL" --worktrees-dir "$TEST_WORKTREES" 2>&1)
echo "$status" | grep -q "mock-project"
check "status shows repo"

# --- Test 8: Worktree cleanup ---
echo "-- 8. Worktree cleanup --"
"$PROJECT_ROOT/scripts/pool-manage.sh" worktree-remove mock-project mock-project--bd-test1--fix-readme \
    --pool-dir "$TEST_POOL" --worktrees-dir "$TEST_WORKTREES" 2>/dev/null
[[ ! -d "$TEST_WORKTREES/mock-project--bd-test1--fix-readme" ]]
check "worktree removed"
[[ -d "$TEST_POOL/mock-project" ]]
check "pool clone still exists"

# --- Test 9: Notification dry-run ---
echo "-- 9. Notifications --"
notif=$("$PROJECT_ROOT/scripts/notify.sh" --dry-run "Test" "Hello" 2>&1)
echo "$notif" | grep -q "Test"
check "notification dry-run works"

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
