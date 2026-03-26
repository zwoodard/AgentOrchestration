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
        ((PASS++)) || true
    else
        echo "  FAIL: $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        ((FAIL++)) || true
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
