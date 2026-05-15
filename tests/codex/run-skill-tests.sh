#!/usr/bin/env bash
# Test runner for Codex skill behavior tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
CODEX_BIN="${CODEX_BIN:-codex}"

echo "========================================"
echo " Codex Skills Test Suite"
echo "========================================"
echo ""
echo "Repository: $(cd ../.. && pwd)"
echo "Test time: $(date)"
echo "Codex version: $($CODEX_BIN --version 2>/dev/null || echo 'not found')"
echo ""

if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
    echo "ERROR: Codex CLI not found"
    exit 1
fi

VERBOSE=false
SPECIFIC_TEST=""
TIMEOUT="${CODEX_TEST_TIMEOUT:-300}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --test|-t)
            SPECIFIC_TEST="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --verbose, -v        Show verbose test output"
            echo "  --test, -t NAME      Run only the specified test file"
            echo "  --timeout SECONDS    Set timeout per Codex run (default: 300)"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Environment:"
            echo "  CODEX_BIN            Codex executable (default: codex)"
            echo "  CODEX_TEST_MODEL     Optional model override for test runs"
            echo "  CODEX_TEST_TIMEOUT   Default timeout per Codex run"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

export CODEX_TEST_TIMEOUT="$TIMEOUT"

tests=(
    "test-skill-discovery-smoke.sh"
    "test-code-review-skill.sh"
    "test-commit-message-skill.sh"
    "test-receiving-code-review-review-review.sh"
    "test-receiving-plan-review-review-review.sh"
    "test-joshix-guidance-regressions.sh"
    "test-using-joshix-no-implicit-git.sh"
)

if [ -n "$SPECIFIC_TEST" ]; then
    tests=("$SPECIFIC_TEST")
fi

passed=0
failed=0
skipped=0

for test in "${tests[@]}"; do
    echo "----------------------------------------"
    echo "Running: $test"
    echo "----------------------------------------"

    test_path="$SCRIPT_DIR/$test"

    if [ ! -f "$test_path" ]; then
        echo "  [SKIP] Test file not found: $test"
        skipped=$((skipped + 1))
        continue
    fi

    if [ "$VERBOSE" = true ]; then
        if bash "$test_path"; then
            echo ""
            echo "  [PASS] $test"
            passed=$((passed + 1))
        else
            echo ""
            echo "  [FAIL] $test"
            failed=$((failed + 1))
        fi
    else
        if output="$(bash "$test_path" 2>&1)"; then
            echo "  [PASS]"
            passed=$((passed + 1))
        else
            echo "  [FAIL]"
            echo ""
            echo "  Output:"
            printf '%s\n' "$output" | sed 's/^/    /'
            failed=$((failed + 1))
        fi
    fi

    echo ""
done

echo "========================================"
echo " Test Results Summary"
echo "========================================"
echo ""
echo "  Passed:  $passed"
echo "  Failed:  $failed"
echo "  Skipped: $skipped"
echo ""

if [ "$failed" -gt 0 ]; then
    echo "STATUS: FAILED"
    exit 1
fi

echo "STATUS: PASSED"
