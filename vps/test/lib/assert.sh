#!/bin/bash
# Tiny assertion helpers for vps/test scenarios.
# Each scenario sources this and increments TESTS_PASSED / TESTS_FAILED.

# Color codes (skip if not a TTY)
if [ -t 1 ]; then
    R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; NC='\033[0m'
else
    R=''; G=''; Y=''; NC=''
fi

TESTS_PASSED=${TESTS_PASSED:-0}
TESTS_FAILED=${TESTS_FAILED:-0}

_pass() { echo -e "  ${G}PASS${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
_fail() { echo -e "  ${R}FAIL${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# assert_exit_zero <actual_exit_code> <label>
assert_exit_zero() {
    if [ "$1" -eq 0 ]; then
        _pass "$2 (exit 0)"
    else
        _fail "$2 (exit $1)"
    fi
}

# assert_exec_in <container> <label> <cmd...>
# Asserts that `docker exec <container> <cmd>` exits 0.
assert_exec_in() {
    local container="$1" label="$2"; shift 2
    if docker exec "$container" "$@" >/dev/null 2>&1; then
        _pass "$label"
    else
        _fail "$label (cmd: $*)"
    fi
}

# assert_log_contains <log_file> <pattern> <label>
assert_log_contains() {
    if grep -qE "$2" "$1" 2>/dev/null; then
        _pass "$3"
    else
        _fail "$3 (pattern: $2 not found in $1)"
    fi
}

# assert_log_not_contains <log_file> <pattern> <label>
assert_log_not_contains() {
    if grep -qE "$2" "$1" 2>/dev/null; then
        _fail "$3 (unwanted pattern: $2 found in $1)"
    else
        _pass "$3"
    fi
}

# print_summary — call at end of each scenario; exit non-zero on any failure.
print_summary() {
    echo ""
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${G}✓ All $TESTS_PASSED assertions passed${NC}"
        return 0
    else
        echo -e "${R}✗ $TESTS_FAILED of $((TESTS_PASSED + TESTS_FAILED)) assertions failed${NC}"
        return 1
    fi
}
