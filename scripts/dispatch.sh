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
