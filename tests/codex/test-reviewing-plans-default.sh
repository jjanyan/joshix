#!/usr/bin/env bash
# Behavior test: pasted implementation plans default to review, not execution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: reviewing-plans"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

mkdir -p "$TEST_PROJECT/src" "$TEST_PROJECT/.agents/plans"
cat > "$TEST_PROJECT/src/notifications.js" <<'EOF'
export function formatNotification(message) {
  return message.trim();
}
EOF

git -C "$TEST_PROJECT" add src/notifications.js
git -C "$TEST_PROJECT" commit --quiet -m "Add notification formatter"

read -r -d '' PROMPT <<'EOF' || true
# Notification Queue Implementation Plan

**Goal:** Add queued notification delivery.

---

### Task 1: Queue model

**Files:**
- Create: `src/notificationQueue.js`
- Test: `tests/notificationQueue.test.js`

- [ ] **Step 1: Implement the queue**

Create `enqueueNotification(message)` and store messages in memory.

- [ ] **Step 2: Add test coverage**

Verify two enqueued messages are delivered in order.

### Task 2: Delivery worker

**Files:**
- Modify: `src/notificationQueue.js`

- [ ] **Step 1: Call delivery service**

Call `sendNotification(message)` for each queued item.

### Task 3: Documentation

**Files:**
- Create: `docs/notifications.md`

- [ ] **Step 1: Add durable docs**

Document how notification delivery works.
EOF

echo "Test project: $TEST_PROJECT"
echo "Running Codex with workspace-write so accidental execution is observable..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "workspace-write"

FINAL_FILE="$OUTPUT_DIR/final.md"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"
STATUS_AFTER="$(git -C "$TEST_PROJECT" status --porcelain -- src tests docs .agents/plans)"
FINAL_ONE_LINE="$(printf '%s\n' "$FINAL_OUTPUT" | tr '\n' ' ')"

echo ""
echo "Verifying default plan review behavior..."
FAILED=0

assert_contains "$FINAL_OUTPUT" "reviewing.*plan|plan review|review.*implementation plan" "Treats bare pasted plan as review" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "not to execute|not.*approval.*execute|explicit.*(execute|implement|instruction)|execute.*explicit" "States execution requires explicit instruction" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_ONE_LINE" "Task 1.*(test-first|TDD|before.*test|test.*after|implement.*before.*test)" "Flags Task 1 TDD/order issue" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_ONE_LINE" "sendNotification.*(undefined|missing|not.*defined|not.*created|not.*imported|needs investigation)" "Flags undefined delivery dependency" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "Status:|Issues Found|Findings|Ready|Not ready" "Returns review status/findings" || FAILED=$((FAILED + 1))

if [ -z "$STATUS_AFTER" ]; then
    echo "  [PASS] Plan review did not edit workspace files"
else
    echo "  [FAIL] Git status changed during plan review"
    printf '%s\n' "$STATUS_AFTER" | sed 's/^/    /'
    FAILED=$((FAILED + 1))
fi

if [ "$FAILED" -eq 0 ]; then
    echo ""
    echo "STATUS: PASSED"
    exit 0
fi

echo ""
echo "STATUS: FAILED"
echo "Final output: $FINAL_FILE"
echo "Events: $OUTPUT_DIR/events.jsonl"
echo "stderr: $OUTPUT_DIR/stderr.txt"
exit 1
