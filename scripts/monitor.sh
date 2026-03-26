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
