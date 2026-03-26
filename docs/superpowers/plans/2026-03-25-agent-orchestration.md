# Agent Orchestration System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-pane orchestration system that dispatches Claude Code sub-agents across a pool of git worktrees, with Beads for shared task state, cross-platform notifications, and self-modifying process evolution.

**Architecture:** A CLAUDE.md-driven Claude Code session (the orchestrator) manages 13-25 repos via a git worktree pool. Bash scripts handle process lifecycle (dispatch, monitor, continue, pool management). Beads (Dolt-backed) tracks task state shared between orchestrator and agents. Cross-platform OS notifications alert the user when agents need attention.

**Tech Stack:** Bash (cross-platform via Git Bash on Windows), Claude Code CLI, Beads/Dolt, Git worktrees, YAML configs, PowerShell (Windows notifications), osascript (macOS notifications)

**Spec:** `docs/superpowers/specs/2026-03-25-agent-orchestration-design.md`

---

## File Structure

```
AgentOrchestration/
├── CLAUDE.md                        # Orchestrator brain — all commands, workflows, context
├── config/
│   ├── repos.yaml                   # Repo registry (name, URL, platform, default branch, permissions)
│   ├── defaults.yaml                # Default autonomy, permission mode, allowed tools baseline
│   └── agent-template.md            # Template prompt for sub-agents with {{PLACEHOLDERS}}
├── scripts/
│   ├── pool-manage.sh               # Clone, fetch, worktree create/remove, GC, status
│   ├── notify.sh                    # Cross-platform notification helper (Windows/macOS)
│   ├── dispatch.sh                  # Build prompt, build permission flags, launch agent, attach monitor
│   ├── monitor.sh                   # Watch agent log for BLOCKED/DONE/crash, fire notifications
│   ├── continue.sh                  # Resume blocked agent with user's answer
│   └── parse-yaml.sh               # Minimal YAML parser for reading config (no external deps)
├── pool/                            # Pre-cloned repos (created by pool-manage.sh init)
├── worktrees/                       # Active git worktrees (created by pool-manage.sh worktree-create)
├── logs/                            # Per-task agent output logs
├── tests/
│   ├── test-parse-yaml.sh           # Tests for YAML parser
│   ├── test-pool-manage.sh          # Tests for pool management
│   ├── test-notify.sh               # Tests for notification dispatch
│   ├── test-dispatch.sh             # Tests for agent dispatch
│   ├── test-monitor.sh              # Tests for log monitoring
│   └── fixtures/                    # Test fixtures (sample configs, mock logs)
│       ├── repos-test.yaml
│       ├── defaults-test.yaml
│       ├── agent-template-test.md
│       └── sample-agent-output.log
└── .gitignore                       # Ignore pool/, worktrees/, logs/, .beads/
```

---

### Task 1: Project Scaffolding & Config Files

**Files:**
- Create: `.gitignore`
- Create: `config/repos.yaml`
- Create: `config/defaults.yaml`
- Create: `config/agent-template.md`

- [ ] **Step 1: Create .gitignore**

```gitignore
# Cloned repos (large, machine-specific)
pool/

# Active worktrees (ephemeral)
worktrees/

# Agent output logs
logs/

# Beads database
.beads/

# OS files
.DS_Store
Thumbs.db
```

- [ ] **Step 2: Create directory structure**

```bash
mkdir -p config scripts pool worktrees logs tests/fixtures
```

- [ ] **Step 3: Create config/defaults.yaml**

```yaml
# Default settings for new repos and agent behavior
defaults:
  permission_mode: managed
  autonomy: medium
  max_worktrees: 3
  default_branch: main
  pre_clone: false
  allowed_tools:
    - "Read"
    - "Edit"
    - "Write"
    - "Bash(git *)"
  denied_tools:
    - "Bash(git push --force *)"
```

- [ ] **Step 4: Create config/repos.yaml**

```yaml
# Repo registry — add repos here or via the orchestrator
# Each repo can override defaults from defaults.yaml
repos: {}
  # example-repo:
  #   url: https://github.com/org/example-repo
  #   platform: github
  #   default_branch: main
  #   pre_clone: true
  #   max_worktrees: 3
  #   permission_mode: managed
  #   autonomy: medium
  #   allowed_tools:
  #     - "Read"
  #     - "Edit"
  #     - "Write"
  #     - "Bash(git *)"
  #     - "Bash(npm *)"
  #   denied_tools:
  #     - "Bash(git push --force *)"
```

- [ ] **Step 5: Create config/agent-template.md**

```markdown
You are working on task {{TASK_ID}} in repo {{REPO_NAME}}.
Your working directory is: {{WORKTREE_PATH}}

## Task
{{TASK_BRIEF}}

## Additional Context
{{USER_CONTEXT}}

## Autonomy Level: {{AUTONOMY}}

{{AUTONOMY_INSTRUCTIONS}}

## Rules
- Work on branch: {{BRANCH_NAME}}
- Commit frequently with clear messages referencing {{TASK_ID}}
- When you need user input, output EXACTLY on its own line:
  BLOCKED: <your question>
  Then stop and wait for the next message.
- When you're done, output EXACTLY on its own line:
  DONE: <summary of what you did, branch name, files changed>
- Update your Beads task as you work:
  bd update {{TASK_ID}} -s in_progress
  bd update {{TASK_ID}} -s blocked
  bd close {{TASK_ID}} --reason "<summary>"

## Repo-Specific Instructions
{{REPO_CLAUDE_MD}}
```

- [ ] **Step 6: Commit**

```bash
git add .gitignore config/ tests/
git commit -m "feat: add project scaffolding and config files"
```

---

### Task 2: YAML Parser Utility

The scripts need to read `repos.yaml` and `defaults.yaml`. Rather than requiring `yq` or `python` as dependencies, a minimal bash YAML parser handles the flat/simple YAML structures used in this project.

**Files:**
- Create: `scripts/parse-yaml.sh`
- Create: `tests/test-parse-yaml.sh`
- Create: `tests/fixtures/repos-test.yaml`
- Create: `tests/fixtures/defaults-test.yaml`

- [ ] **Step 1: Create test fixture repos-test.yaml**

```yaml
repos:
  product-a:
    url: https://dev.azure.com/org/project/_git/product-a
    platform: azure-devops
    default_branch: main
    pre_clone: true
    max_worktrees: 3
    permission_mode: managed
    autonomy: medium
    allowed_tools:
      - "Read"
      - "Edit"
      - "Write"
      - "Bash(git *)"
      - "Bash(npm *)"
    denied_tools:
      - "Bash(git push --force *)"
  product-b:
    url: https://github.com/org/product-b
    platform: github
    default_branch: develop
    pre_clone: true
    max_worktrees: 2
    permission_mode: yolo
    autonomy: high
```

- [ ] **Step 2: Create test fixture defaults-test.yaml**

```yaml
defaults:
  permission_mode: managed
  autonomy: medium
  max_worktrees: 3
  default_branch: main
  pre_clone: false
  allowed_tools:
    - "Read"
    - "Edit"
    - "Write"
    - "Bash(git *)"
  denied_tools:
    - "Bash(git push --force *)"
```

- [ ] **Step 3: Write failing tests — tests/test-parse-yaml.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/parse-yaml.sh"

FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        ((FAIL++))
    fi
}

echo "=== parse-yaml tests ==="

# Test: list repo names
repos=$(yaml_list_repos "$FIXTURES/repos-test.yaml")
assert_eq "list repos" "product-a product-b" "$repos"

# Test: get scalar field
url=$(yaml_get_repo_field "$FIXTURES/repos-test.yaml" "product-a" "url")
assert_eq "get url" "https://dev.azure.com/org/project/_git/product-a" "$url"

platform=$(yaml_get_repo_field "$FIXTURES/repos-test.yaml" "product-a" "platform")
assert_eq "get platform" "azure-devops" "$platform"

branch=$(yaml_get_repo_field "$FIXTURES/repos-test.yaml" "product-b" "default_branch")
assert_eq "get default_branch" "develop" "$branch"

perm=$(yaml_get_repo_field "$FIXTURES/repos-test.yaml" "product-b" "permission_mode")
assert_eq "get permission_mode" "yolo" "$perm"

# Test: get list field (allowed_tools)
tools=$(yaml_get_repo_list "$FIXTURES/repos-test.yaml" "product-a" "allowed_tools")
assert_eq "get allowed_tools" "Read Edit Write Bash(git *) Bash(npm *)" "$tools"

denied=$(yaml_get_repo_list "$FIXTURES/repos-test.yaml" "product-a" "denied_tools")
assert_eq "get denied_tools" "Bash(git push --force *)" "$denied"

# Test: get default value
def_mode=$(yaml_get_default "$FIXTURES/defaults-test.yaml" "permission_mode")
assert_eq "get default permission_mode" "managed" "$def_mode"

def_autonomy=$(yaml_get_default "$FIXTURES/defaults-test.yaml" "autonomy")
assert_eq "get default autonomy" "medium" "$def_autonomy"

def_tools=$(yaml_get_default_list "$FIXTURES/defaults-test.yaml" "allowed_tools")
assert_eq "get default allowed_tools" "Read Edit Write Bash(git *)" "$def_tools"

# Test: missing field returns empty
missing=$(yaml_get_repo_field "$FIXTURES/repos-test.yaml" "product-a" "nonexistent")
assert_eq "missing field returns empty" "" "$missing"

# Test: missing repo returns empty
missing_repo=$(yaml_get_repo_field "$FIXTURES/repos-test.yaml" "nonexistent" "url")
assert_eq "missing repo returns empty" "" "$missing_repo"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
chmod +x tests/test-parse-yaml.sh
bash tests/test-parse-yaml.sh
```

Expected: FAIL — `scripts/parse-yaml.sh` does not exist yet.

- [ ] **Step 5: Implement scripts/parse-yaml.sh**

```bash
#!/usr/bin/env bash
# Minimal YAML parser for the flat structures used in repos.yaml and defaults.yaml.
# Not a general-purpose YAML parser — handles only the patterns this project uses.

# List all repo names under the "repos:" key
# Usage: yaml_list_repos <yaml_file>
yaml_list_repos() {
    local file="$1"
    local in_repos=false
    local repos=""
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        if [[ "$line" == "repos:" ]]; then
            in_repos=true
            continue
        fi
        if $in_repos; then
            # A top-level key (no leading whitespace) means we left repos section
            if [[ "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
            # A repo name is indented exactly 2 spaces and ends with ':'
            if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):$ ]]; then
                repos="${repos:+$repos }${BASH_REMATCH[1]}"
            fi
        fi
    done < "$file"
    echo "$repos"
}

# Get a scalar field for a specific repo
# Usage: yaml_get_repo_field <yaml_file> <repo_name> <field_name>
yaml_get_repo_field() {
    local file="$1" repo="$2" field="$3"
    local in_repo=false found_repos=false
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        if [[ "$line" == "repos:" ]]; then
            found_repos=true
            continue
        fi
        if $found_repos && [[ "$line" =~ ^[[:space:]]{2}${repo}:$ ]]; then
            in_repo=true
            continue
        fi
        if $in_repo; then
            # Another repo at indent level 2 means we passed our repo
            if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z] && ! "$line" =~ ^[[:space:]]{4} ]]; then
                break
            fi
            # Top-level key means we left repos entirely
            if [[ "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
            # Match "    field: value" (4-space indent, not a list item)
            if [[ "$line" =~ ^[[:space:]]{4}${field}:[[:space:]]+(.*) ]]; then
                local val="${BASH_REMATCH[1]}"
                # Strip surrounding quotes
                val="${val#\"}"
                val="${val%\"}"
                val="${val#\'}"
                val="${val%\'}"
                echo "$val"
                return
            fi
        fi
    done < "$file"
    echo ""
}

# Get a list field for a specific repo (returns space-separated values)
# Usage: yaml_get_repo_list <yaml_file> <repo_name> <field_name>
yaml_get_repo_list() {
    local file="$1" repo="$2" field="$3"
    local in_repo=false in_list=false found_repos=false
    local items=""
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" == "repos:" ]]; then
            found_repos=true
            continue
        fi
        if $found_repos && [[ "$line" =~ ^[[:space:]]{2}${repo}:$ ]]; then
            in_repo=true
            continue
        fi
        if $in_repo; then
            if [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z] && ! "$line" =~ ^[[:space:]]{4} ]]; then
                break
            fi
            if [[ "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
            # Found the field header
            if [[ "$line" =~ ^[[:space:]]{4}${field}:$ ]]; then
                in_list=true
                continue
            fi
            if $in_list; then
                # List item at 6-space indent
                if [[ "$line" =~ ^[[:space:]]{6}-[[:space:]]+(.*) ]]; then
                    local val="${BASH_REMATCH[1]}"
                    val="${val#\"}"
                    val="${val%\"}"
                    val="${val#\'}"
                    val="${val%\'}"
                    items="${items:+$items }$val"
                else
                    # Not a list item — list ended
                    in_list=false
                fi
            fi
        fi
    done < "$file"
    echo "$items"
}

# Get a scalar default value
# Usage: yaml_get_default <yaml_file> <field_name>
yaml_get_default() {
    local file="$1" field="$2"
    local in_defaults=false
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        if [[ "$line" == "defaults:" ]]; then
            in_defaults=true
            continue
        fi
        if $in_defaults; then
            if [[ "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
            if [[ "$line" =~ ^[[:space:]]{2}${field}:[[:space:]]+(.*) ]]; then
                local val="${BASH_REMATCH[1]}"
                val="${val#\"}"
                val="${val%\"}"
                echo "$val"
                return
            fi
        fi
    done < "$file"
    echo ""
}

# Get a list default value (returns space-separated values)
# Usage: yaml_get_default_list <yaml_file> <field_name>
yaml_get_default_list() {
    local file="$1" field="$2"
    local in_defaults=false in_list=false
    local items=""
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" == "defaults:" ]]; then
            in_defaults=true
            continue
        fi
        if $in_defaults; then
            if [[ "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
            if [[ "$line" =~ ^[[:space:]]{2}${field}:$ ]]; then
                in_list=true
                continue
            fi
            if $in_list; then
                if [[ "$line" =~ ^[[:space:]]{4}-[[:space:]]+(.*) ]]; then
                    local val="${BASH_REMATCH[1]}"
                    val="${val#\"}"
                    val="${val%\"}"
                    items="${items:+$items }$val"
                else
                    in_list=false
                fi
            fi
        fi
    done < "$file"
    echo "$items"
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
bash tests/test-parse-yaml.sh
```

Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/parse-yaml.sh tests/test-parse-yaml.sh tests/fixtures/repos-test.yaml tests/fixtures/defaults-test.yaml
git commit -m "feat: add minimal YAML parser with tests"
```

---

### Task 3: Pool Management Script

**Files:**
- Create: `scripts/pool-manage.sh`
- Create: `tests/test-pool-manage.sh`

- [ ] **Step 1: Write failing tests — tests/test-pool-manage.sh**

```bash
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
        ((PASS++))
    else
        echo "  FAIL: $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        ((FAIL++))
    fi
}

assert_dir_exists() {
    local desc="$1" dir="$2"
    if [[ -d "$dir" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc (directory not found: $dir)"
        ((FAIL++))
    fi
}

assert_dir_not_exists() {
    local desc="$1" dir="$2"
    if [[ ! -d "$dir" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc (directory still exists: $dir)"
        ((FAIL++))
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
assert_dir_exists "worktree has files" "$TEST_WORKTREES/test-repo--bd-a1b2--fix-bug/README.md"

# Test: second worktree for same repo
echo "-- second worktree --"
"$POOL_MANAGE" worktree-create test-repo bd-c3d4 add-feature \
    --pool-dir "$TEST_POOL" \
    --worktrees-dir "$TEST_WORKTREES" 2>/dev/null
assert_dir_exists "second worktree created" "$TEST_WORKTREES/test-repo--bd-c3d4--add-feature"

# Test: worktree limit (max 2, this is the 3rd)
echo "-- worktree limit --"
output=$("$POOL_MANAGE" worktree-create test-repo bd-e5f6 another \
    --pool-dir "$TEST_POOL" \
    --worktrees-dir "$TEST_WORKTREES" \
    --repos-yaml "$TEST_REPOS_YAML" 2>&1) || true
assert_eq "third worktree blocked by limit" "1" "$?"

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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
chmod +x tests/test-pool-manage.sh
bash tests/test-pool-manage.sh
```

Expected: FAIL — `scripts/pool-manage.sh` does not exist.

- [ ] **Step 3: Implement scripts/pool-manage.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/parse-yaml.sh"

# Defaults — can be overridden by flags
POOL_DIR="${PROJECT_ROOT}/pool"
WORKTREES_DIR="${PROJECT_ROOT}/worktrees"
REPOS_YAML="${PROJECT_ROOT}/config/repos.yaml"
DEFAULTS_YAML="${PROJECT_ROOT}/config/defaults.yaml"

usage() {
    cat <<EOF
Usage: pool-manage.sh <command> [args] [flags]

Commands:
  init                              Clone all pre_clone repos
  clone <repo>                      Clone a specific repo into the pool
  fetch <repo>                      Fetch latest for a repo
  fetch-all                         Fetch latest for all pool repos
  worktree-create <repo> <id> <slug>  Create a worktree for a task
  worktree-remove <repo> <name>     Remove a worktree
  gc                                Prune stale worktrees and git gc
  status                            Show pool state

Flags:
  --pool-dir <path>       Override pool directory
  --worktrees-dir <path>  Override worktrees directory
  --repos-yaml <path>     Override repos.yaml path
  --defaults-yaml <path>  Override defaults.yaml path
EOF
}

# Parse global flags from any position
parse_flags() {
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pool-dir)      POOL_DIR="$2"; shift 2 ;;
            --worktrees-dir) WORKTREES_DIR="$2"; shift 2 ;;
            --repos-yaml)    REPOS_YAML="$2"; shift 2 ;;
            --defaults-yaml) DEFAULTS_YAML="$2"; shift 2 ;;
            *)               args+=("$1"); shift ;;
        esac
    done
    POSITIONAL_ARGS=("${args[@]}")
}

cmd_clone() {
    local repo="$1"
    local url
    url=$(yaml_get_repo_field "$REPOS_YAML" "$repo" "url")
    if [[ -z "$url" ]]; then
        echo "Error: repo '$repo' not found in $REPOS_YAML" >&2
        return 1
    fi
    if [[ -d "$POOL_DIR/$repo" ]]; then
        echo "Repo '$repo' already cloned in pool"
        return 0
    fi
    mkdir -p "$POOL_DIR"
    git clone "$url" "$POOL_DIR/$repo"
    echo "Cloned '$repo' into pool"
}

cmd_init() {
    local repos
    repos=$(yaml_list_repos "$REPOS_YAML")
    for repo in $repos; do
        local pre_clone
        pre_clone=$(yaml_get_repo_field "$REPOS_YAML" "$repo" "pre_clone")
        if [[ "$pre_clone" == "true" ]]; then
            cmd_clone "$repo"
        fi
    done
}

cmd_fetch() {
    local repo="$1"
    if [[ ! -d "$POOL_DIR/$repo" ]]; then
        echo "Error: repo '$repo' not in pool. Run 'clone $repo' first." >&2
        return 1
    fi
    git -C "$POOL_DIR/$repo" fetch --all --prune
}

cmd_fetch_all() {
    for dir in "$POOL_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local repo
        repo=$(basename "$dir")
        echo "Fetching $repo..."
        git -C "$dir" fetch --all --prune
    done
}

cmd_worktree_create() {
    local repo="$1" task_id="$2" slug="$3"
    local worktree_name="${repo}--${task_id}--${slug}"
    local worktree_path="${WORKTREES_DIR}/${worktree_name}"
    local branch_name="${task_id}/${slug}"

    # Check pool clone exists
    if [[ ! -d "$POOL_DIR/$repo" ]]; then
        echo "Repo '$repo' not in pool. Cloning..." >&2
        cmd_clone "$repo"
    fi

    # Check worktree limit
    local max_wt
    max_wt=$(yaml_get_repo_field "$REPOS_YAML" "$repo" "max_worktrees")
    if [[ -z "$max_wt" ]]; then
        max_wt=$(yaml_get_default "$DEFAULTS_YAML" "max_worktrees")
    fi
    if [[ -z "$max_wt" ]]; then
        max_wt=3
    fi

    local current_count
    current_count=$(find "$WORKTREES_DIR" -maxdepth 1 -type d -name "${repo}--*" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$current_count" -ge "$max_wt" ]]; then
        echo "Error: worktree limit ($max_wt) reached for '$repo'. Remove a worktree first." >&2
        return 1
    fi

    # Get default branch
    local default_branch
    default_branch=$(yaml_get_repo_field "$REPOS_YAML" "$repo" "default_branch")
    if [[ -z "$default_branch" ]]; then
        default_branch=$(yaml_get_default "$DEFAULTS_YAML" "default_branch")
    fi
    if [[ -z "$default_branch" ]]; then
        default_branch="main"
    fi

    mkdir -p "$WORKTREES_DIR"
    git -C "$POOL_DIR/$repo" worktree add "$worktree_path" -b "$branch_name" "origin/$default_branch"
    echo "$worktree_path"
}

cmd_worktree_remove() {
    local repo="$1" worktree_name="$2"
    local worktree_path="${WORKTREES_DIR}/${worktree_name}"

    if [[ ! -d "$worktree_path" ]]; then
        echo "Error: worktree '$worktree_name' not found" >&2
        return 1
    fi

    git -C "$POOL_DIR/$repo" worktree remove "$worktree_path" --force
    git -C "$POOL_DIR/$repo" worktree prune
    echo "Removed worktree '$worktree_name'"
}

cmd_gc() {
    # Prune worktrees
    for dir in "$POOL_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        git -C "$dir" worktree prune
        git -C "$dir" gc --auto
    done
    echo "GC complete"
}

cmd_status() {
    echo "=== Pool Status ==="
    for dir in "$POOL_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local repo
        repo=$(basename "$dir")
        local wt_count
        wt_count=$(find "$WORKTREES_DIR" -maxdepth 1 -type d -name "${repo}--*" 2>/dev/null | wc -l | tr -d ' ')
        local max_wt
        max_wt=$(yaml_get_repo_field "$REPOS_YAML" "$repo" "max_worktrees" 2>/dev/null || echo "?")
        echo "  $repo: $wt_count active worktrees (max: $max_wt)"

        # List active worktrees
        for wt in "$WORKTREES_DIR"/${repo}--*/; do
            [[ -d "$wt" ]] || continue
            echo "    - $(basename "$wt")"
        done
    done

    if [[ ! -d "$POOL_DIR" ]] || [[ -z "$(ls -A "$POOL_DIR" 2>/dev/null)" ]]; then
        echo "  (no repos in pool)"
    fi
}

# --- Main ---
if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

COMMAND="$1"
shift

parse_flags "$@"
set -- "${POSITIONAL_ARGS[@]}"

case "$COMMAND" in
    init)             cmd_init ;;
    clone)            cmd_clone "$1" ;;
    fetch)            cmd_fetch "$1" ;;
    fetch-all)        cmd_fetch_all ;;
    worktree-create)  cmd_worktree_create "$1" "$2" "$3" ;;
    worktree-remove)  cmd_worktree_remove "$1" "$2" ;;
    gc)               cmd_gc ;;
    status)           cmd_status ;;
    *)                echo "Unknown command: $COMMAND" >&2; usage; exit 1 ;;
esac
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x scripts/pool-manage.sh
bash tests/test-pool-manage.sh
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/pool-manage.sh tests/test-pool-manage.sh
git commit -m "feat: add pool management script with worktree lifecycle"
```

---

### Task 4: Cross-Platform Notification Script

**Files:**
- Create: `scripts/notify.sh`
- Create: `tests/test-notify.sh`

- [ ] **Step 1: Write failing tests — tests/test-notify.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY="$SCRIPT_DIR/../scripts/notify.sh"

PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        ((FAIL++))
    fi
}

echo "=== notify tests ==="

# Test: script exists and is executable
[[ -x "$NOTIFY" ]] 2>/dev/null
assert_eq "notify.sh is executable" "0" "$?"

# Test: detects platform (should not error)
output=$("$NOTIFY" --detect-platform 2>&1)
assert_eq "platform detection exits 0" "0" "$?"
echo "  Detected platform: $output"

# Test: dry-run mode (doesn't actually fire notification)
output=$("$NOTIFY" --dry-run "Test Title" "Test Body" 2>&1)
assert_eq "dry-run exits 0" "0" "$?"
echo "$output" | grep -q "Test Title"
assert_eq "dry-run includes title" "0" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
chmod +x tests/test-notify.sh
bash tests/test-notify.sh
```

Expected: FAIL — `scripts/notify.sh` does not exist.

- [ ] **Step 3: Implement scripts/notify.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Cross-platform notification script
# Usage: notify.sh <title> <body>
# Flags:
#   --dry-run          Print what would be sent, don't actually notify
#   --detect-platform  Print detected platform and exit

detect_platform() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        MINGW*|MSYS*|CYGWIN*)  echo "windows" ;;
        Linux*)
            # Check if running in WSL
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "windows"
            else
                echo "linux"
            fi
            ;;
        *)  echo "unknown" ;;
    esac
}

notify_macos() {
    local title="$1" body="$2"
    osascript -e "display notification \"$body\" with title \"$title\" sound name \"Ping\""
}

notify_windows() {
    local title="$1" body="$2"
    powershell.exe -Command "
        Add-Type -AssemblyName System.Windows.Forms
        \$notify = New-Object System.Windows.Forms.NotifyIcon
        \$notify.Icon = [System.Drawing.SystemIcons]::Information
        \$notify.Visible = \$true
        \$notify.ShowBalloonTip(5000, '$title', '$body', [System.Windows.Forms.ToolTipIcon]::Info)
        Start-Sleep -Seconds 1
        \$notify.Dispose()
    " 2>/dev/null || {
        # Fallback: simple message box
        powershell.exe -Command "
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show('$body', '$title')
        " 2>/dev/null || echo "NOTIFICATION: [$title] $body"
    }
}

notify_linux() {
    local title="$1" body="$2"
    if command -v notify-send &>/dev/null; then
        notify-send "$title" "$body"
    else
        echo "NOTIFICATION: [$title] $body"
    fi
}

# --- Main ---
DRY_RUN=false

if [[ "${1:-}" == "--detect-platform" ]]; then
    detect_platform
    exit 0
fi

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

TITLE="${1:-Notification}"
BODY="${2:-}"

if $DRY_RUN; then
    echo "Would notify on $(detect_platform): [$TITLE] $BODY"
    exit 0
fi

PLATFORM=$(detect_platform)
case "$PLATFORM" in
    macos)   notify_macos "$TITLE" "$BODY" ;;
    windows) notify_windows "$TITLE" "$BODY" ;;
    linux)   notify_linux "$TITLE" "$BODY" ;;
    *)       echo "NOTIFICATION: [$TITLE] $BODY" ;;
esac
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x scripts/notify.sh
bash tests/test-notify.sh
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/notify.sh tests/test-notify.sh
git commit -m "feat: add cross-platform notification script"
```

---

### Task 5: Monitor Script

**Files:**
- Create: `scripts/monitor.sh`
- Create: `tests/test-monitor.sh`
- Create: `tests/fixtures/sample-agent-output.log`

- [ ] **Step 1: Create test fixture — tests/fixtures/sample-agent-output.log**

```
I'll start by looking at the codebase structure.
Reading the billing service files...
Found the issue in subscription_check.py line 42.
The expired subscription check returns None instead of raising a proper error.
BLOCKED: Should I consolidate the subscription check into a shared middleware, or fix it inline in the billing endpoint?
```

- [ ] **Step 2: Create a second fixture — tests/fixtures/sample-agent-done.log**

```
I'll start by looking at the codebase structure.
Reading the billing service files...
Fixed the subscription check to properly handle expired subscriptions.
Added tests for the edge case.
DONE: Fixed billing 500 error for expired subscriptions. Branch: bd-a1b2/fix-billing-500. Files changed: subscription_check.py, test_subscription.py
```

- [ ] **Step 3: Write failing tests — tests/test-monitor.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR="$SCRIPT_DIR/../scripts/monitor.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        ((FAIL++))
    fi
}

echo "=== monitor tests ==="

# Test: detect BLOCKED pattern
output=$("$MONITOR" --parse-line 'BLOCKED: Should I refactor this?' 2>&1)
echo "$output" | grep -q "BLOCKED"
assert_eq "detects BLOCKED pattern" "0" "$?"
echo "$output" | grep -q "Should I refactor this?"
assert_eq "extracts BLOCKED message" "0" "$?"

# Test: detect DONE pattern
output=$("$MONITOR" --parse-line 'DONE: Fixed the bug. Branch: bd-a1b2/fix. Files: a.py' 2>&1)
echo "$output" | grep -q "DONE"
assert_eq "detects DONE pattern" "0" "$?"

# Test: normal line (no pattern)
output=$("$MONITOR" --parse-line 'Reading the billing service files...' 2>&1)
assert_eq "normal line returns nothing" "" "$output"

# Test: scan fixture file for BLOCKED
output=$("$MONITOR" --scan "$FIXTURES/sample-agent-output.log" 2>&1)
echo "$output" | grep -q "BLOCKED"
assert_eq "scan finds BLOCKED in fixture" "0" "$?"

# Test: scan fixture file for DONE
output=$("$MONITOR" --scan "$FIXTURES/sample-agent-done.log" 2>&1)
echo "$output" | grep -q "DONE"
assert_eq "scan finds DONE in fixture" "0" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
chmod +x tests/test-monitor.sh
bash tests/test-monitor.sh
```

Expected: FAIL — `scripts/monitor.sh` does not exist.

- [ ] **Step 5: Implement scripts/monitor.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage:
#   monitor.sh <task-id> <log-file> <pid>    Watch a running agent
#   monitor.sh --parse-line "<line>"          Parse a single line (for testing)
#   monitor.sh --scan <file>                  Scan a file for patterns (for testing)

parse_line() {
    local line="$1"
    if [[ "$line" =~ ^BLOCKED:[[:space:]]*(.*) ]]; then
        echo "BLOCKED: ${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^DONE:[[:space:]]*(.*) ]]; then
        echo "DONE: ${BASH_REMATCH[1]}"
    fi
}

scan_file() {
    local file="$1"
    while IFS= read -r line; do
        local result
        result=$(parse_line "$line")
        if [[ -n "$result" ]]; then
            echo "$result"
        fi
    done < "$file"
}

watch_agent() {
    local task_id="$1" log_file="$2" agent_pid="$3"

    # Tail the log file and watch for patterns
    tail -f "$log_file" 2>/dev/null | while IFS= read -r line; do
        local result
        result=$(parse_line "$line")
        if [[ -z "$result" ]]; then
            continue
        fi

        if [[ "$result" == BLOCKED:* ]]; then
            local message="${result#BLOCKED: }"
            # Update Beads task
            bd update "$task_id" -s blocked 2>/dev/null || true
            # Fire notification
            "$SCRIPT_DIR/notify.sh" "Agent $task_id needs input" "$message"
        elif [[ "$result" == DONE:* ]]; then
            local message="${result#DONE: }"
            # Update Beads task
            bd close "$task_id" --reason "$message" 2>/dev/null || true
            # Fire notification
            "$SCRIPT_DIR/notify.sh" "Agent $task_id finished" "$message"
            break
        fi
    done &

    local tail_pid=$!

    # Also watch for process exit (crash detection)
    while kill -0 "$agent_pid" 2>/dev/null; do
        sleep 2
    done

    # Agent process exited — check if it was a clean exit
    wait "$agent_pid" 2>/dev/null
    local exit_code=$?

    # Kill the tail watcher
    kill "$tail_pid" 2>/dev/null || true

    if [[ $exit_code -ne 0 ]]; then
        bd update "$task_id" -s blocked 2>/dev/null || true
        "$SCRIPT_DIR/notify.sh" "Agent $task_id crashed" "Exit code: $exit_code. Check logs/$task_id.log"
    fi
}

# --- Main ---
case "${1:-}" in
    --parse-line)
        parse_line "$2"
        ;;
    --scan)
        scan_file "$2"
        ;;
    *)
        if [[ $# -lt 3 ]]; then
            echo "Usage: monitor.sh <task-id> <log-file> <agent-pid>" >&2
            exit 1
        fi
        watch_agent "$1" "$2" "$3"
        ;;
esac
```

- [ ] **Step 6: Make executable and run tests**

```bash
chmod +x scripts/monitor.sh
bash tests/test-monitor.sh
```

Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/monitor.sh tests/test-monitor.sh tests/fixtures/sample-agent-output.log tests/fixtures/sample-agent-done.log
git commit -m "feat: add agent monitor script with pattern detection"
```

---

### Task 6: Dispatch Script

**Files:**
- Create: `scripts/dispatch.sh`
- Create: `tests/test-dispatch.sh`

- [ ] **Step 1: Write failing tests — tests/test-dispatch.sh**

```bash
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
        ((PASS++))
    else
        echo "  FAIL: $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        ((FAIL++))
    fi
}

assert_contains() {
    local desc="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -qF "$expected"; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: '$expected'"
        echo "    actual: '$actual'"
        ((FAIL++))
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
chmod +x tests/test-dispatch.sh
bash tests/test-dispatch.sh
```

Expected: FAIL — `scripts/dispatch.sh` does not exist.

- [ ] **Step 3: Implement scripts/dispatch.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/parse-yaml.sh"

# Defaults
REPOS_YAML="${PROJECT_ROOT}/config/repos.yaml"
DEFAULTS_YAML="${PROJECT_ROOT}/config/defaults.yaml"
TEMPLATE="${PROJECT_ROOT}/config/agent-template.md"
LOGS_DIR="${PROJECT_ROOT}/logs"

AUTONOMY_HIGH="You have HIGH autonomy. Implement, test, commit, push, and open a PR. The user will review the PR."
AUTONOMY_MEDIUM="You have MEDIUM autonomy. Implement and test freely. BLOCK before making architectural decisions or opening PRs."
AUTONOMY_LOW="You have LOW autonomy. Present a plan before writing code. BLOCK on design decisions, implementation choices, and before PRs."

get_autonomy_instructions() {
    case "$1" in
        high)   echo "$AUTONOMY_HIGH" ;;
        medium) echo "$AUTONOMY_MEDIUM" ;;
        low)    echo "$AUTONOMY_LOW" ;;
        *)      echo "$AUTONOMY_MEDIUM" ;;
    esac
}

build_prompt() {
    local task_id="$1" repo="$2" brief="$3" context="${4:-}" worktree_path="${5:-}" branch="${6:-}"

    local autonomy
    autonomy=$(yaml_get_repo_field "$REPOS_YAML" "$repo" "autonomy")
    if [[ -z "$autonomy" ]]; then
        autonomy=$(yaml_get_default "$DEFAULTS_YAML" "autonomy")
    fi
    if [[ -z "$autonomy" ]]; then
        autonomy="medium"
    fi

    local autonomy_instructions
    autonomy_instructions=$(get_autonomy_instructions "$autonomy")

    local prompt
    prompt=$(cat "$TEMPLATE")

    # Replace placeholders
    prompt="${prompt//\{\{TASK_ID\}\}/$task_id}"
    prompt="${prompt//\{\{REPO_NAME\}\}/$repo}"
    prompt="${prompt//\{\{TASK_BRIEF\}\}/$brief}"
    prompt="${prompt//\{\{USER_CONTEXT\}\}/${context:-None provided.}}"
    prompt="${prompt//\{\{WORKTREE_PATH\}\}/${worktree_path:-<worktree>}}"
    prompt="${prompt//\{\{BRANCH_NAME\}\}/${branch:-$task_id/task}}"
    prompt="${prompt//\{\{AUTONOMY\}\}/$autonomy}"
    prompt="${prompt//\{\{AUTONOMY_INSTRUCTIONS\}\}/$autonomy_instructions}"

    # Inject repo-specific CLAUDE.md if it exists
    local repo_claude_md=""
    if [[ -n "$worktree_path" && -f "$worktree_path/CLAUDE.md" ]]; then
        repo_claude_md=$(cat "$worktree_path/CLAUDE.md")
    fi
    prompt="${prompt//\{\{REPO_CLAUDE_MD\}\}/${repo_claude_md:-No repo-specific instructions.}}"

    echo "$prompt"
}

build_flags() {
    local repo="$1"

    local perm_mode
    perm_mode=$(yaml_get_repo_field "$REPOS_YAML" "$repo" "permission_mode")
    if [[ -z "$perm_mode" ]]; then
        perm_mode=$(yaml_get_default "$DEFAULTS_YAML" "permission_mode")
    fi
    if [[ -z "$perm_mode" ]]; then
        perm_mode="managed"
    fi

    if [[ "$perm_mode" == "yolo" ]]; then
        echo "--dangerously-skip-permissions"
        return
    fi

    # Managed mode: build --allowedTools list
    local allowed_tools
    allowed_tools=$(yaml_get_repo_list "$REPOS_YAML" "$repo" "allowed_tools")
    if [[ -z "$allowed_tools" ]]; then
        allowed_tools=$(yaml_get_default_list "$DEFAULTS_YAML" "allowed_tools")
    fi

    local flags="--permission-mode dontAsk"
    if [[ -n "$allowed_tools" ]]; then
        flags="$flags --allowedTools"
        for tool in $allowed_tools; do
            flags="$flags \"$tool\""
        done
    fi

    echo "$flags"
}

dispatch_agent() {
    local task_id="$1" worktree_path="$2" repo="$3" brief="$4" context="${5:-}"

    local branch="${task_id}/task"
    local prompt
    prompt=$(build_prompt "$task_id" "$repo" "$brief" "$context" "$worktree_path" "$branch")

    local flags
    flags=$(build_flags "$repo")

    mkdir -p "$LOGS_DIR"
    local log_file="$LOGS_DIR/${task_id}.log"

    # Launch claude in the worktree directory
    echo "Dispatching agent for $task_id in $worktree_path..."
    cd "$worktree_path"

    # Build and execute the command
    eval claude -p \""$prompt"\" $flags > "$log_file" 2>&1 &
    local agent_pid=$!

    echo "Agent PID: $agent_pid"
    echo "Log: $log_file"

    # Start monitor in background
    "$SCRIPT_DIR/monitor.sh" "$task_id" "$log_file" "$agent_pid" &

    echo "$agent_pid"
}

# --- Main ---
# Parse arguments
ACTION=""
TASK_ID=""
REPO=""
BRIEF=""
CONTEXT=""
WORKTREE_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-prompt)   ACTION="build-prompt"; shift ;;
        --build-flags)    ACTION="build-flags"; shift ;;
        --task-id)        TASK_ID="$2"; shift 2 ;;
        --repo)           REPO="$2"; shift 2 ;;
        --brief)          BRIEF="$2"; shift 2 ;;
        --context)        CONTEXT="$2"; shift 2 ;;
        --worktree)       WORKTREE_PATH="$2"; shift 2 ;;
        --template)       TEMPLATE="$2"; shift 2 ;;
        --repos-yaml)     REPOS_YAML="$2"; shift 2 ;;
        --defaults-yaml)  DEFAULTS_YAML="$2"; shift 2 ;;
        --logs-dir)       LOGS_DIR="$2"; shift 2 ;;
        *)
            # Positional args: task-id worktree-path repo brief [context]
            if [[ -z "$TASK_ID" ]]; then TASK_ID="$1"
            elif [[ -z "$WORKTREE_PATH" ]]; then WORKTREE_PATH="$1"
            elif [[ -z "$REPO" ]]; then REPO="$1"
            elif [[ -z "$BRIEF" ]]; then BRIEF="$1"
            else CONTEXT="$1"
            fi
            shift
            ;;
    esac
done

case "$ACTION" in
    build-prompt)
        build_prompt "$TASK_ID" "$REPO" "$BRIEF" "$CONTEXT" "$WORKTREE_PATH"
        ;;
    build-flags)
        build_flags "$REPO"
        ;;
    "")
        dispatch_agent "$TASK_ID" "$WORKTREE_PATH" "$REPO" "$BRIEF" "$CONTEXT"
        ;;
esac
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x scripts/dispatch.sh
bash tests/test-dispatch.sh
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/dispatch.sh tests/test-dispatch.sh
git commit -m "feat: add agent dispatch script with prompt and flag generation"
```

---

### Task 7: Continue Script

**Files:**
- Create: `scripts/continue.sh`
- Create: `tests/test-continue.sh`

- [ ] **Step 1: Write failing tests — tests/test-continue.sh**

```bash
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
        ((PASS++))
    else
        echo "  FAIL: $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        ((FAIL++))
    fi
}

assert_contains() {
    local desc="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -qF "$expected"; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: '$expected'"
        ((FAIL++))
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
chmod +x tests/test-continue.sh
bash tests/test-continue.sh
```

Expected: FAIL — `scripts/continue.sh` does not exist.

- [ ] **Step 3: Implement scripts/continue.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/parse-yaml.sh"

# Defaults
WORKTREES_DIR="${PROJECT_ROOT}/worktrees"
REPOS_YAML="${PROJECT_ROOT}/config/repos.yaml"
DEFAULTS_YAML="${PROJECT_ROOT}/config/defaults.yaml"
LOGS_DIR="${PROJECT_ROOT}/logs"

find_worktree() {
    local task_id="$1"
    # Find the worktree directory containing the task ID
    for dir in "$WORKTREES_DIR"/*--${task_id}--*/; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return
        fi
    done
    echo ""
}

extract_repo_from_worktree() {
    local worktree_name="$1"
    # Worktree name format: <repo>--<task-id>--<slug>
    echo "$worktree_name" | cut -d'-' -f1 | sed 's/--.*$//'
    # More robust: split on --
    echo "$worktree_name" | awk -F'--' '{print $1}'
}

build_permission_flags() {
    local repo="$1"

    local perm_mode
    perm_mode=$(yaml_get_repo_field "$REPOS_YAML" "$repo" "permission_mode")
    if [[ -z "$perm_mode" ]]; then
        perm_mode=$(yaml_get_default "$DEFAULTS_YAML" "permission_mode")
    fi
    if [[ -z "$perm_mode" ]]; then
        perm_mode="managed"
    fi

    if [[ "$perm_mode" == "yolo" ]]; then
        echo "--dangerously-skip-permissions"
        return
    fi

    local allowed_tools
    allowed_tools=$(yaml_get_repo_list "$REPOS_YAML" "$repo" "allowed_tools")
    if [[ -z "$allowed_tools" ]]; then
        allowed_tools=$(yaml_get_default_list "$DEFAULTS_YAML" "allowed_tools")
    fi

    local flags="--permission-mode dontAsk"
    if [[ -n "$allowed_tools" ]]; then
        flags="$flags --allowedTools"
        for tool in $allowed_tools; do
            flags="$flags \"$tool\""
        done
    fi

    echo "$flags"
}

build_command() {
    local task_id="$1" message="$2"

    local worktree_path
    worktree_path=$(find_worktree "$task_id")
    if [[ -z "$worktree_path" ]]; then
        echo "Error: no worktree found for task '$task_id'" >&2
        return 1
    fi

    local worktree_name
    worktree_name=$(basename "$worktree_path")
    local repo
    repo=$(echo "$worktree_name" | awk -F'--' '{print $1}')

    local perm_flags
    perm_flags=$(build_permission_flags "$repo")

    echo "cd \"$worktree_path\" && claude --continue -p \"$message\" $perm_flags"
}

continue_agent() {
    local task_id="$1" message="$2"

    local worktree_path
    worktree_path=$(find_worktree "$task_id")
    if [[ -z "$worktree_path" ]]; then
        echo "Error: no worktree found for task '$task_id'" >&2
        return 1
    fi

    local worktree_name
    worktree_name=$(basename "$worktree_path")
    local repo
    repo=$(echo "$worktree_name" | awk -F'--' '{print $1}')

    local perm_flags
    perm_flags=$(build_permission_flags "$repo")

    local log_file="$LOGS_DIR/${task_id}.log"

    # Update Beads status
    bd update "$task_id" -s in_progress 2>/dev/null || true

    echo "Continuing agent $task_id..."
    cd "$worktree_path"
    eval claude --continue -p \""$message"\" $perm_flags >> "$log_file" 2>&1 &
    local agent_pid=$!

    # Re-attach monitor
    "$SCRIPT_DIR/monitor.sh" "$task_id" "$log_file" "$agent_pid" &

    echo "$agent_pid"
}

# --- Main ---
ACTION=""
TASK_ID=""
MESSAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-command)   ACTION="build-command"; shift ;;
        --task-id)         TASK_ID="$2"; shift 2 ;;
        --message)         MESSAGE="$2"; shift 2 ;;
        --worktrees-dir)   WORKTREES_DIR="$2"; shift 2 ;;
        --repos-yaml)      REPOS_YAML="$2"; shift 2 ;;
        --defaults-yaml)   DEFAULTS_YAML="$2"; shift 2 ;;
        --logs-dir)        LOGS_DIR="$2"; shift 2 ;;
        *)
            if [[ -z "$TASK_ID" ]]; then TASK_ID="$1"
            else MESSAGE="$1"
            fi
            shift
            ;;
    esac
done

case "$ACTION" in
    build-command)
        build_command "$TASK_ID" "$MESSAGE"
        ;;
    "")
        continue_agent "$TASK_ID" "$MESSAGE"
        ;;
esac
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x scripts/continue.sh
bash tests/test-continue.sh
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/continue.sh tests/test-continue.sh
git commit -m "feat: add agent continue script for resuming blocked agents"
```

---

### Task 8: Orchestrator CLAUDE.md

This is the brain of the system. It instructs the Claude Code session on how to behave as the orchestrator.

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Write CLAUDE.md**

```markdown
# Agent Orchestrator

You are an orchestration agent managing multiple sub-agents working across different code repositories. The user talks ONLY to you. Sub-agents are invisible to the user.

## Your Role

- Receive tasks from the user in natural language
- Dispatch work to sub-agents in the appropriate repositories
- Monitor agent status and relay information back to the user
- Relay user followups and answers to the right agents
- Manage the repository pool and worktrees

## Directory Layout

- `config/repos.yaml` — Registry of all managed repos (URL, platform, permissions)
- `config/defaults.yaml` — Default settings for new repos and agents
- `config/agent-template.md` — Prompt template for sub-agents
- `pool/` — Pre-cloned repos (one clone per repo, never work in directly)
- `worktrees/` — Active git worktrees for agent tasks
- `scripts/` — Process lifecycle scripts
- `logs/` — Per-task agent output logs

## Dispatching a Task

When the user gives you a task:

1. **Identify the repo.** Match from description or ask if ambiguous. Check `config/repos.yaml` for known repos.
2. **Create a Beads task:**
   ```bash
   bd create "<task title>" -t <bug|feature|task|chore> -l "repo:<repo-name>"
   ```
   Note the task ID (e.g., `bd-a1b2`).
3. **Provision a worktree:**
   ```bash
   scripts/pool-manage.sh fetch <repo> --pool-dir pool --worktrees-dir worktrees
   scripts/pool-manage.sh worktree-create <repo> <task-id> <slug> --pool-dir pool --worktrees-dir worktrees
   ```
4. **Dispatch the agent:**
   ```bash
   scripts/dispatch.sh --task-id <task-id> --repo <repo> --worktree <worktree-path> --brief "<task description>"
   ```
5. **Confirm to the user:** "Task `<task-id>` created, agent dispatched to `<repo>`."

## Handling /status

When the user asks for status or says `/status`:

1. Query Beads for all active tasks:
   ```bash
   bd list --status open,in_progress,blocked --json
   ```
2. Also check for completed tasks:
   ```bash
   bd list --status closed --json
   ```
3. Present in this format:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    <id>  <repo>  <slug>          <status-emoji>  <STATUS>
          <last status message or blocked question>
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
   Status emojis: BLOCKED=⚠️, WORKING=🔄, DONE=✅, QUEUED=📋

## Handling Followups & Answers

When the user provides additional context or answers a question:

1. **Identify the task.** Match by task ID if explicit, or by context (repo name, topic).
2. **Relay to the agent:**
   ```bash
   scripts/continue.sh --task-id <task-id> --message "<user's message>"
   ```
3. **Confirm:** "Relayed to `<task-id>`, agent continuing."

## Handling /done <task-id>

1. Read the task completion summary from Beads:
   ```bash
   bd show <task-id>
   ```
2. Present the summary to the user (branch, files changed, what was done).
3. Clean up the worktree:
   ```bash
   scripts/pool-manage.sh worktree-remove <repo> <worktree-name> --pool-dir pool --worktrees-dir worktrees
   ```
4. Close the Beads task if not already closed.

## Handling /cancel <task-id>

1. Find and kill the agent process (check `logs/<task-id>.log` for PID).
2. Clean up the worktree.
3. Close the Beads task:
   ```bash
   bd close <task-id> --reason "Cancelled by user"
   ```

## Handling /pool

Show the pool status:
```bash
scripts/pool-manage.sh status --pool-dir pool --worktrees-dir worktrees
```

## Handling /pool add <name> <url>

1. Add the repo to `config/repos.yaml` with defaults from `config/defaults.yaml`.
2. Clone it:
   ```bash
   scripts/pool-manage.sh clone <name> --pool-dir pool
   ```
3. Commit the config change.

## Handling /permissions <repo>

Show the repo's current permission_mode and allowed/denied tools from `config/repos.yaml`.

## Handling /permissions <repo> add <tool>

1. Add the tool to the repo's `allowed_tools` list in `config/repos.yaml`.
2. Commit the config change.
3. Confirm: "Added `<tool>` to `<repo>` permissions."

## Permission Learning Flow

When a blocked agent reports it needs a tool that isn't allowed:

1. Present to the user: "Agent `<task-id>` needs `<tool>` — not currently allowed for `<repo>`."
2. Wait for the user's response:
   - "allow it" → add to this repo's `allowed_tools`, commit, resume agent
   - "allow it everywhere" → add to all repos and `defaults.yaml`, commit, resume agent
   - "allow it this time" → resume agent with `--allowedTools` including the tool (one-shot)
   - "deny" → resume agent telling it to find an alternative

## Self-Modification

You can edit your own config files, templates, and scripts when the user asks for process changes. After any modification:

1. Commit the change with a descriptive message.
2. Note which changes take effect immediately vs. next session:
   - `config/repos.yaml`, `config/defaults.yaml`, `config/agent-template.md` → next agent dispatch
   - `scripts/*.sh` → immediately
   - `CLAUDE.md` (this file) → next orchestrator session

## Important Rules

- NEVER make the user interact with sub-agents directly. You are their only interface.
- When unsure which repo a task belongs to, ASK.
- When a repo isn't in the pool yet, offer to add it via `/pool add`.
- Always confirm task dispatch and followup relay to the user.
- Keep status reports concise. The user is busy.
```

- [ ] **Step 2: Verify CLAUDE.md reads correctly**

```bash
cat CLAUDE.md | head -5
```

Expected: First 5 lines of the CLAUDE.md content.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: add orchestrator CLAUDE.md with all commands and workflows"
```

---

### Task 9: Beads Initialization

**Files:**
- No new files — this task runs Beads setup commands.

- [ ] **Step 1: Verify Dolt is installed**

```bash
dolt version
```

Expected: A version string like `dolt version 1.x.x`. If not installed, install with:
- macOS: `brew install dolt`
- Windows: `choco install dolt` or download from https://github.com/dolthub/dolt/releases

- [ ] **Step 2: Verify Beads is installed**

```bash
bd --version
```

Expected: A version string. If not installed, follow instructions at https://github.com/steveyegge/beads

- [ ] **Step 3: Initialize Beads in the project**

```bash
cd /Users/zane/Desktop/AgentOrchestration
bd init
```

Expected: Beads database initialized in `.beads/` directory.

- [ ] **Step 4: Verify .beads/ is gitignored**

```bash
grep -q ".beads/" .gitignore && echo "OK" || echo "MISSING"
```

Expected: "OK"

- [ ] **Step 5: Test creating a task**

```bash
bd create "Test task" -t task -l "repo:test"
```

Expected: Task created with an ID like `bd-xxxx`.

- [ ] **Step 6: Test querying tasks**

```bash
bd list --json
```

Expected: JSON output containing the test task.

- [ ] **Step 7: Clean up test task**

```bash
bd close <task-id-from-step-5> --reason "Test cleanup"
```

- [ ] **Step 8: Commit any Beads config if generated**

```bash
git status
# If any beads config files exist that should be tracked, add and commit them
```

---

### Task 10: End-to-End Integration Test

This test exercises the full flow: config → pool → worktree → dispatch → monitor → continue → cleanup.

**Files:**
- Create: `tests/test-integration.sh`

- [ ] **Step 1: Write integration test**

```bash
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
        ((PASS++))
    else
        echo "  FAIL: $desc"
        ((FAIL++))
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
```

- [ ] **Step 2: Run integration test**

```bash
chmod +x tests/test-integration.sh
bash tests/test-integration.sh
```

Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/test-integration.sh
git commit -m "feat: add end-to-end integration test"
```

---

### Task 11: Final Verification

- [ ] **Step 1: Run all tests**

```bash
echo "=== Running all tests ==="
bash tests/test-parse-yaml.sh
bash tests/test-pool-manage.sh
bash tests/test-notify.sh
bash tests/test-monitor.sh
bash tests/test-dispatch.sh
bash tests/test-continue.sh
bash tests/test-integration.sh
echo "=== All tests complete ==="
```

Expected: All tests PASS across all test files.

- [ ] **Step 2: Verify file structure**

```bash
find . -type f | grep -v '.git/' | grep -v 'pool/' | grep -v 'worktrees/' | grep -v 'logs/' | sort
```

Expected output should show all files from the file structure defined at the top of this plan.

- [ ] **Step 3: Verify all scripts are executable**

```bash
ls -la scripts/*.sh
```

Expected: All scripts have executable permission.

- [ ] **Step 4: Review git log**

```bash
git log --oneline
```

Expected: Clean commit history showing each task's commit.

- [ ] **Step 5: Final commit if any cleanup needed**

```bash
git status
# If there are any remaining changes, stage and commit them
```
