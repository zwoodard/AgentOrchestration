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
