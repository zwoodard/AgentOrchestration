#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POOL_MANAGE="$PROJECT_ROOT/scripts/pool-manage.sh"

# Use a temp directory for test isolation
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Create a bare git repo to use as a "remote"
REMOTE_REPO="$TEST_DIR/remote-repo.git"
git init --bare "$REMOTE_REPO" 2>/dev/null

# Create a working clone, add a commit so there's a branch
WORK_CLONE="$TEST_DIR/work-clone"
git clone "$REMOTE_REPO" "$WORK_CLONE" 2>/dev/null
cd "$WORK_CLONE"
git checkout -b main 2>/dev/null
echo "hello" > README.md
git add README.md
git commit -m "initial" 2>/dev/null
git push -u origin main 2>/dev/null
cd "$PROJECT_ROOT"

# Create test config
TEST_POOL="$TEST_DIR/pool"
TEST_WORKTREES="$TEST_DIR/worktrees"
mkdir -p "$TEST_POOL" "$TEST_WORKTREES"

TEST_REPOS_YAML="$TEST_DIR/repos.yaml"
cat > "$TEST_REPOS_YAML" <<YAML
repos:
  test-repo:
    url: $REMOTE_REPO
    platform: github
    default_branch: main
    pre_clone: true
    max_worktrees: 2
YAML

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

assert_dir_exists() {
    local desc="$1" dir="$2"
    if [[ -d "$dir" ]]; then
        echo "  PASS: $desc"
        ((PASS++)) || true
    else
        echo "  FAIL: $desc (directory not found: $dir)"
        ((FAIL++)) || true
    fi
}

assert_dir_not_exists() {
    local desc="$1" dir="$2"
    if [[ ! -d "$dir" ]]; then
        echo "  PASS: $desc"
        ((PASS++)) || true
    else
        echo "  FAIL: $desc (directory still exists: $dir)"
        ((FAIL++)) || true
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    if [[ -e "$file" ]]; then
        echo "  PASS: $desc"
        ((PASS++)) || true
    else
        echo "  FAIL: $desc (file not found: $file)"
        ((FAIL++)) || true
    fi
}

echo "=== pool-manage tests ==="

# Test: clone a repo into pool
echo "-- clone --"
"$POOL_MANAGE" clone test-repo \
    --repos-yaml "$TEST_REPOS_YAML" \
    --pool-dir "$TEST_POOL" 2>/dev/null
assert_dir_exists "clone creates pool dir" "$TEST_POOL/test-repo"
assert_dir_exists "clone creates .git dir" "$TEST_POOL/test-repo/.git"

# Test: fetch
echo "-- fetch --"
output=$("$POOL_MANAGE" fetch test-repo --pool-dir "$TEST_POOL" 2>&1)
assert_eq "fetch exits 0" "0" "$?"

# Test: worktree-create
echo "-- worktree-create --"
"$POOL_MANAGE" worktree-create test-repo bd-a1b2 fix-bug \
    --pool-dir "$TEST_POOL" \
    --worktrees-dir "$TEST_WORKTREES" 2>/dev/null
assert_dir_exists "worktree created" "$TEST_WORKTREES/test-repo--bd-a1b2--fix-bug"
assert_file_exists "worktree has files" "$TEST_WORKTREES/test-repo--bd-a1b2--fix-bug/README.md"

# Test: second worktree for same repo
echo "-- second worktree --"
"$POOL_MANAGE" worktree-create test-repo bd-c3d4 add-feature \
    --pool-dir "$TEST_POOL" \
    --worktrees-dir "$TEST_WORKTREES" 2>/dev/null
assert_dir_exists "second worktree created" "$TEST_WORKTREES/test-repo--bd-c3d4--add-feature"

# Test: worktree limit (max 2, this is the 3rd)
echo "-- worktree limit --"
set +e
"$POOL_MANAGE" worktree-create test-repo bd-e5f6 another \
    --pool-dir "$TEST_POOL" \
    --worktrees-dir "$TEST_WORKTREES" \
    --repos-yaml "$TEST_REPOS_YAML" 2>/dev/null
wt_limit_rc=$?
set -e
assert_eq "third worktree blocked by limit" "1" "$wt_limit_rc"

# Test: worktree-remove
echo "-- worktree-remove --"
"$POOL_MANAGE" worktree-remove test-repo test-repo--bd-a1b2--fix-bug \
    --pool-dir "$TEST_POOL" \
    --worktrees-dir "$TEST_WORKTREES" 2>/dev/null
assert_dir_not_exists "worktree removed" "$TEST_WORKTREES/test-repo--bd-a1b2--fix-bug"

# Test: status
echo "-- status --"
output=$("$POOL_MANAGE" status --pool-dir "$TEST_POOL" --worktrees-dir "$TEST_WORKTREES" 2>&1)
echo "$output" | grep -q "test-repo"
assert_eq "status shows repo" "0" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
