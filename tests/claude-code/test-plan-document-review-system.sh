#!/usr/bin/env bash
# Integration Test: Plan Document Review System
# Runs the plan document reviewer and verifies its detailed report catches blocking issues.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Integration Test: Plan Document Review"
echo "========================================"
echo ""
echo "This test verifies the plan document reviewer by:"
echo "  1. Creating a plan with intentional implementation blockers"
echo "  2. Running the plan document reviewer"
echo "  3. Verifying the reviewer returns a detailed report"
echo ""

TEST_PROJECT=$(create_test_project)
echo "Test project: $TEST_PROJECT"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

cd "$TEST_PROJECT"
mkdir -p .joshix/plans

cat > .joshix/plans/report-export.md <<'EOF'
# Report Export Implementation Plan

### Task 1: CSV export

**Depends on:** None

**Files:**
- Create: `src/exportReport.js`
- Test: `tests/exportReport.test.js`

- [ ] **Step 1: Implement CSV export**

Create `exportReport(rows)` and return CSV text.

- [ ] **Step 2: Add focused tests**

Verify headers and one data row.

### Task 2: Upload export

**Depends on:** Task 1

- [ ] **Step 1: Upload the report**

Call `uploadReport(csv)` after export.
EOF

git init --quiet
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial commit with report export plan" --quiet

echo ""
echo "Created plan with intentional blockers:"
echo "  - Task 1 implements behavior before adding its focused tests"
echo "  - Task 2 calls uploadReport without defining or creating it"
echo ""
echo "Running plan document reviewer..."
echo ""

OUTPUT_FILE="$TEST_PROJECT/claude-output.txt"
PROMPT="You are testing the plan document reviewer.

Read skills/reviewing-plans/plan-document-reviewer-prompt.md to understand the review criteria and output format.

Then review the exact plan at $TEST_PROJECT/.joshix/plans/report-export.md and return the template's detailed report.

Check whether:
- testable behavior is implemented before its focused test;
- every called function is defined or created by the plan;
- an engineer could execute every step without getting stuck.

Output only the detailed review requested by the template."

echo "================================================================================"
cd "$CLAUDE_REPO_ROOT"
if ! run_claude_stream "$PROMPT" 120 "$OUTPUT_FILE" --permission-mode bypassPermissions; then
    echo ""
    echo "================================================================================"
    echo "EXECUTION FAILED"
    exit 1
fi
echo "================================================================================"

echo ""
echo "Analyzing reviewer output..."
echo ""

FAILED=0
OUTPUT_ONE_LINE="$(tr '\n' ' ' < "$OUTPUT_FILE")"

echo "=== Verification Tests ==="
echo ""

echo "Test 1: Implementation-before-test ordering flagged..."
if printf '%s\n' "$OUTPUT_ONE_LINE" | grep -qiE 'Task 1.*(test-first|TDD|before.*test|test.*after|implement.*before.*test)'; then
    echo "  [PASS] Reviewer flagged Task 1 ordering"
else
    echo "  [FAIL] Reviewer did not flag implementation-before-test ordering in Task 1"
    FAILED=$((FAILED + 1))
fi
echo ""

echo "Test 2: Undefined uploadReport flagged..."
if printf '%s\n' "$OUTPUT_ONE_LINE" | grep -qiE 'uploadReport.*(undefined|missing|not.*defined|never.*created|not.*created|not.*implemented|no.*definition)'; then
    echo "  [PASS] Reviewer flagged uploadReport as undefined or never created"
else
    echo "  [FAIL] Reviewer did not flag uploadReport as undefined or never created"
    FAILED=$((FAILED + 1))
fi
echo ""

echo "Test 3: Detailed plan review format..."
if grep -q '## Plan Review' "$OUTPUT_FILE" \
   && grep -q '\*\*Status:\*\*' "$OUTPUT_FILE" \
   && grep -q '\*\*Issues' "$OUTPUT_FILE"; then
    echo "  [PASS] Review uses the detailed plan review format"
else
    echo "  [FAIL] Review missing detailed plan review markers"
    FAILED=$((FAILED + 1))
fi
echo ""

echo "Test 4: Reviewer verdict..."
if grep -qiE '\*\*Status:\*\*[[:space:]]*Issues Found|not approved|requires fixes|with fixes' "$OUTPUT_FILE"; then
    echo "  [PASS] Reviewer did not approve the plan without fixes"
else
    echo "  [FAIL] Reviewer approved or did not clearly reject the plan with blockers"
    FAILED=$((FAILED + 1))
fi
echo ""

echo "========================================"
echo " Test Summary"
echo "========================================"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo "STATUS: PASSED"
    echo "The plan document reviewer correctly:"
    echo "  ✓ Flagged implementation-before-test ordering"
    echo "  ✓ Flagged the undefined uploadReport dependency"
    echo "  ✓ Produced a detailed plan review"
    echo "  ✓ Did not approve the plan without fixes"
    exit 0
fi

echo "STATUS: FAILED"
echo "Failed $FAILED verification tests"
echo ""
echo "Output saved to: $OUTPUT_FILE"
exit 1
