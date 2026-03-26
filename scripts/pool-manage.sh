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
    POSITIONAL_ARGS=("${args[@]+"${args[@]}"}")
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
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

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
