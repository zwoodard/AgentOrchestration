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
        ((PASS++)) || true
    else
        echo "  FAIL: $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        ((FAIL++)) || true
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
