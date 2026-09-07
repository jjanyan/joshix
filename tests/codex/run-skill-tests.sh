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
    "test-task-context-behavior.sh"
    "test-progress-dag-guidance.sh"
    "test-dispatching-parallel-agents-guidance.sh"
    "test-parallel-planning-routing.sh"
    "test-code-review-skill.sh"
    "test-commit-message-skill.sh"
    "test-commit-staged-skill.sh"
    "test-receiving-code-review-review-review.sh"
    "test-receiving-code-review-owner-decision-gate.sh"
    "test-receiving-code-review-owner-decision-gate-behavior.sh"
    "test-receiving-plan-review-review-review.sh"
    "test-receiving-plan-review-owner-decision-gate-behavior.sh"
    "test-receiving-spec-review-review-review.sh"
    "test-receiving-spec-review-owner-decision-gate-behavior.sh"
    "test-receiving-review-automatic-application.sh"
    "test-receiving-review-owner-answer-continuation.sh"
    "test-receiving-review-failure-policy.sh"
    "test-receiving-review-convergence-outcomes.sh"
    "test-reviewing-plans-default.sh"
    "test-reviewing-specs-default.sh"
    "test-joshix-guidance-regressions.sh"
    "test-using-joshix-no-implicit-git.sh"
    "test-workflow-policy-behavior.sh"
    "test-autonomous-review-loop-behavior.sh"
    "test-readiness-hold-behavior.sh"
    "test-review-followup-scope-behavior.sh"
    "test-owner-question-wait-behavior.sh"
    "test-owner-question-no-timer-behavior.sh"
    "test-browser-test-isolation-behavior.sh"
    "test-discussion-review-routing-behavior.sh"
    "test-completion-gate-recovery-behavior.sh"
)

if [ -n "$SPECIFIC_TEST" ]; then
    tests=("$SPECIFIC_TEST")
fi

passed=0
failed=0
skipped=0
retried=0

# Every behavior test in this runner is model-backed unless it is explicitly
# listed here as deterministic-only. Model-backed failures receive one retry;
# deterministic failures remain single-attempt failures.
is_model_backed_test() {
    case "$1" in
        test-receiving-code-review-owner-decision-gate.sh)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

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

    test_passed=false

    if [ "$VERBOSE" = true ]; then
        if bash "$test_path"; then
            test_passed=true
        elif is_model_backed_test "$test"; then
            echo ""
            echo "  [RETRY] Model-backed test failed; retrying once."
            retried=$((retried + 1))
            if bash "$test_path"; then
                test_passed=true
            fi
        fi

        echo ""
        if [ "$test_passed" = true ]; then
            echo "  [PASS] $test"
            passed=$((passed + 1))
        else
            echo "  [FAIL] $test"
            failed=$((failed + 1))
        fi
    else
        if output="$(bash "$test_path" 2>&1)"; then
            test_passed=true
        elif is_model_backed_test "$test"; then
            first_output="$output"
            echo "  [RETRY] Model-backed test failed; retrying once."
            retried=$((retried + 1))
            if output="$(bash "$test_path" 2>&1)"; then
                test_passed=true
            else
                output="${first_output}"$'\n\n'"Retry output:"$'\n'"${output}"
            fi
        fi

        if [ "$test_passed" = true ]; then
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
echo "  Retried: $retried"
echo ""

if [ "$failed" -gt 0 ]; then
    echo "STATUS: FAILED"
    exit 1
fi

echo "STATUS: PASSED"
