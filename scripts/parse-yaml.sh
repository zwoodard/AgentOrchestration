#!/usr/bin/env bash
# parse-yaml.sh — Minimal YAML parser for flat/simple YAML structures.
#
# Supports the specific patterns used in repos.yaml and defaults.yaml:
#   repos:
#     <repo-name>:              (2-space indent)
#       key: value              (4-space indent)
#       list_key:               (4-space indent)
#         - "item"              (6-space indent)
#
#   defaults:
#     key: value                (2-space indent)
#     list_key:                 (2-space indent)
#       - "item"                (4-space indent)
#
# All functions strip surrounding double-quotes from values.
# Missing fields/repos return an empty string.

# _yaml_strip_quotes <value>
# Remove surrounding double-quotes from a string.
_yaml_strip_quotes() {
    local val="$1"
    # Strip leading quote
    val="${val#\"}"
    # Strip trailing quote
    val="${val%\"}"
    printf '%s' "$val"
}

# yaml_list_repos <file>
# Print space-separated list of repo names under the top-level `repos:` key.
yaml_list_repos() {
    local file="$1"
    local repos=()
    local in_repos=0

    while IFS= read -r line; do
        # Detect top-level `repos:` key (no leading spaces)
        if [[ "$line" =~ ^repos:[[:space:]]*$ ]]; then
            in_repos=1
            continue
        fi

        # A new top-level key ends the repos block
        if [[ $in_repos -eq 1 ]] && [[ "$line" =~ ^[a-zA-Z_] ]]; then
            break
        fi

        # Repo names are at exactly 2-space indent: "  name:"
        if [[ $in_repos -eq 1 ]] && [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
            repos+=("${BASH_REMATCH[1]}")
        fi
    done < "$file"

    printf '%s' "${repos[*]}"
}

# yaml_get_repo_field <file> <repo> <field>
# Get a scalar value for a field within a specific repo block.
yaml_get_repo_field() {
    local file="$1"
    local repo="$2"
    local field="$3"

    local in_repos=0
    local in_target_repo=0
    local result=""

    while IFS= read -r line; do
        # Detect top-level `repos:` key
        if [[ "$line" =~ ^repos:[[:space:]]*$ ]]; then
            in_repos=1
            continue
        fi

        # A new top-level key ends the repos block
        if [[ $in_repos -eq 1 ]] && [[ "$line" =~ ^[a-zA-Z_] ]]; then
            break
        fi

        if [[ $in_repos -eq 1 ]]; then
            # Check for the target repo at 2-space indent
            if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
                local name="${BASH_REMATCH[1]}"
                if [[ "$name" == "$repo" ]]; then
                    in_target_repo=1
                else
                    # Hit a different repo — stop if we were in target
                    if [[ $in_target_repo -eq 1 ]]; then
                        break
                    fi
                    in_target_repo=0
                fi
                continue
            fi

            if [[ $in_target_repo -eq 1 ]]; then
                # Scalar field at 4-space indent: "    key: value"
                if [[ "$line" =~ ^[[:space:]]{4}([a-zA-Z0-9_-]+):[[:space:]]*(.+)$ ]]; then
                    local key="${BASH_REMATCH[1]}"
                    local val="${BASH_REMATCH[2]}"
                    if [[ "$key" == "$field" ]]; then
                        result="$(_yaml_strip_quotes "$val")"
                        break
                    fi
                fi
            fi
        fi
    done < "$file"

    printf '%s' "$result"
}

# yaml_get_repo_list <file> <repo> <field>
# Get a list field for a specific repo, returned as space-separated values.
yaml_get_repo_list() {
    local file="$1"
    local repo="$2"
    local field="$3"

    local in_repos=0
    local in_target_repo=0
    local in_list=0
    local items=()

    while IFS= read -r line; do
        # Detect top-level `repos:` key
        if [[ "$line" =~ ^repos:[[:space:]]*$ ]]; then
            in_repos=1
            continue
        fi

        # A new top-level key ends the repos block
        if [[ $in_repos -eq 1 ]] && [[ "$line" =~ ^[a-zA-Z_] ]]; then
            break
        fi

        if [[ $in_repos -eq 1 ]]; then
            # Check for the target repo at 2-space indent
            if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
                local name="${BASH_REMATCH[1]}"
                if [[ "$name" == "$repo" ]]; then
                    in_target_repo=1
                else
                    if [[ $in_target_repo -eq 1 ]]; then
                        break
                    fi
                    in_target_repo=0
                    in_list=0
                fi
                continue
            fi

            if [[ $in_target_repo -eq 1 ]]; then
                # List key at 4-space indent with no value: "    key:"
                if [[ "$line" =~ ^[[:space:]]{4}([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
                    local key="${BASH_REMATCH[1]}"
                    if [[ "$key" == "$field" ]]; then
                        in_list=1
                    else
                        # Different key — if we were collecting, stop
                        if [[ $in_list -eq 1 ]]; then
                            break
                        fi
                        in_list=0
                    fi
                    continue
                fi

                # Scalar field at 4-space indent (key: value) — ends list collection
                if [[ $in_list -eq 1 ]] && [[ "$line" =~ ^[[:space:]]{4}([a-zA-Z0-9_-]+):[[:space:]]*.+$ ]]; then
                    break
                fi

                # List item at 6-space indent: "      - "value""
                if [[ $in_list -eq 1 ]] && [[ "$line" =~ ^[[:space:]]{6}-[[:space:]]+(.+)$ ]]; then
                    local item="$(_yaml_strip_quotes "${BASH_REMATCH[1]}")"
                    items+=("$item")
                fi
            fi
        fi
    done < "$file"

    printf '%s' "${items[*]}"
}

# yaml_get_default <file> <field>
# Get a scalar value from the `defaults:` block (fields at 2-space indent).
yaml_get_default() {
    local file="$1"
    local field="$2"
    local result=""
    local in_defaults=0

    while IFS= read -r line; do
        # Detect top-level `defaults:` key
        if [[ "$line" =~ ^defaults:[[:space:]]*$ ]]; then
            in_defaults=1
            continue
        fi

        # A new top-level key ends the defaults block
        if [[ $in_defaults -eq 1 ]] && [[ "$line" =~ ^[a-zA-Z_] ]]; then
            break
        fi

        if [[ $in_defaults -eq 1 ]]; then
            # Scalar field at 2-space indent: "  key: value"
            if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):[[:space:]]*(.+)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"
                if [[ "$key" == "$field" ]]; then
                    result="$(_yaml_strip_quotes "$val")"
                    break
                fi
            fi
        fi
    done < "$file"

    printf '%s' "$result"
}

# yaml_get_default_list <file> <field>
# Get a list field from the `defaults:` block, returned as space-separated values.
yaml_get_default_list() {
    local file="$1"
    local field="$2"
    local in_defaults=0
    local in_list=0
    local items=()

    while IFS= read -r line; do
        # Detect top-level `defaults:` key
        if [[ "$line" =~ ^defaults:[[:space:]]*$ ]]; then
            in_defaults=1
            continue
        fi

        # A new top-level key ends the defaults block
        if [[ $in_defaults -eq 1 ]] && [[ "$line" =~ ^[a-zA-Z_] ]]; then
            break
        fi

        if [[ $in_defaults -eq 1 ]]; then
            # List key at 2-space indent with no value: "  key:"
            if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
                local key="${BASH_REMATCH[1]}"
                if [[ "$key" == "$field" ]]; then
                    in_list=1
                else
                    if [[ $in_list -eq 1 ]]; then
                        break
                    fi
                    in_list=0
                fi
                continue
            fi

            # Scalar field at 2-space indent (key: value) — ends list collection
            if [[ $in_list -eq 1 ]] && [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):[[:space:]]*.+$ ]]; then
                break
            fi

            # List item at 4-space indent: "    - "value""
            if [[ $in_list -eq 1 ]] && [[ "$line" =~ ^[[:space:]]{4}-[[:space:]]+(.+)$ ]]; then
                local item="$(_yaml_strip_quotes "${BASH_REMATCH[1]}")"
                items+=("$item")
            fi
        fi
    done < "$file"

    printf '%s' "${items[*]}"
}
