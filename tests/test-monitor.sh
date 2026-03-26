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
        ((PASS++)) || true
    else
        echo "  FAIL: $desc"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        ((FAIL++)) || true
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
