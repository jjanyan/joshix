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

mkdir -p "$TEST_PROJECT/src" "$TEST_PROJECT/.joshix/plans"
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

has_missing_delivery_dependency() {
  local output="$1"
  local finding direct_absence delivery_absence no_direct_definition
  direct_absence='(sendNotification[^.!?]{0,80}(does not exist|is (undefined|missing|absent)|is not (defined|created|imported)|has no (defined )?(source|contract|definition|implementation|module|import|export)|needs investigation)|(does not|doesn.t) identify where[^.!?]{0,40}sendNotification[^.!?]{0,40}(comes from|is sourced))'
  delivery_absence='delivery (service )?(dependency|module|contract|mechanism)[^.!?]{0,80}((is|are|remains) (undefined|missing|absent)|does not exist|is not (defined|created|imported))'
  no_direct_definition='(there is no[[:space:][:punct:]]+sendNotification|no (definition|implementation|module|function|import|export|creation)[^.!?]{0,80}sendNotification)'

  while IFS= read -r finding; do
    if printf '%s\n' "$finding" | grep -Eiq \
        '(sendNotification[^.!?]{0,80}(is (defined|present|available)|is not missing)|delivery (service )?(dependency|module|contract|mechanism)[^.!?]{0,80}is not (missing|undefined|absent))'; then
      continue
    fi

    if printf '%s\n' "$finding" | grep -Eiq \
        "($direct_absence|$delivery_absence.{0,240}sendNotification|sendNotification.{0,240}$delivery_absence|$no_direct_definition)"; then
      return 0
    fi
  done < <(printf '%s\n' "$output" | awk '
    function emit_finding() {
      if (!in_finding) return
      gsub(/[[:space:]]+/, " ", finding)
      print finding
    }
    { all = all " " $0 }
    /^-[[:space:]]+\*\*/ {
      emit_finding()
      saw_finding = 1
      in_finding = 1
      finding = $0
      next
    }
    /^##/ {
      emit_finding()
      in_finding = 0
      finding = ""
      next
    }
    in_finding { finding = finding " " $0 }
    END {
      emit_finding()
      if (!saw_finding) {
        gsub(/[[:space:]]+/, " ", all)
        print all
      }
    }
  ')

  return 1
}

VALID_DIRECT_ABSENCE='`sendNotification` does not exist in the repository.'
VALID_NO_SOURCE='`sendNotification(message)` has no defined source or contract.'
VALID_DELIVERY_ABSENCE='The delivery dependency is undefined. Evidence: The plan calls `sendNotification(message)`.'
VALID_CONTRACT_ABSENCE='The delivery contract and worker lifecycle are undefined. Evidence: no `sendNotification` service exists.'
VALID_NO_DEFINITION='There is no `sendNotification`, import path, or worker entry point.'
VALID_UNIDENTIFIED_SOURCE='The plan does not identify where `sendNotification` comes from.'
INVALID_NEGATED_DIRECT='No, sendNotification is defined by the existing module.'
INVALID_NOT_MISSING='sendNotification is not missing from the repository.'
INVALID_NEGATED_DELIVERY='The delivery dependency is not missing; sendNotification is defined.'
INVALID_CROSS_FINDINGS=$'- **Task 1:** The delivery module is missing documentation.\n- **Task 2:** sendNotification is defined.'
INVALID_SAME_FINDING='- **Task 1:** The delivery module is missing documentation; sendNotification is defined.'

if ! has_missing_delivery_dependency "$VALID_DIRECT_ABSENCE" \
    || ! has_missing_delivery_dependency "$VALID_NO_SOURCE" \
    || ! has_missing_delivery_dependency "$VALID_DELIVERY_ABSENCE" \
    || ! has_missing_delivery_dependency "$VALID_CONTRACT_ABSENCE" \
    || ! has_missing_delivery_dependency "$VALID_NO_DEFINITION" \
    || ! has_missing_delivery_dependency "$VALID_UNIDENTIFIED_SOURCE" \
    || has_missing_delivery_dependency "$INVALID_NEGATED_DIRECT" \
    || has_missing_delivery_dependency "$INVALID_NOT_MISSING" \
    || has_missing_delivery_dependency "$INVALID_NEGATED_DELIVERY" \
    || has_missing_delivery_dependency "$INVALID_CROSS_FINDINGS" \
    || has_missing_delivery_dependency "$INVALID_SAME_FINDING"; then
  echo '  [FAIL] Deterministic missing-delivery oracle fixtures'
  exit 1
fi
echo '  [PASS] Deterministic missing-delivery oracle fixtures'

if [ "${REVIEWING_PLANS_ORACLE_ONLY:-0}" = "1" ]; then
  echo 'STATUS: PASSED (oracle only)'
  exit 0
fi

echo "Test project: $TEST_PROJECT"
echo "Running Codex with workspace-write so accidental execution is observable..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "workspace-write"

FINAL_FILE="$OUTPUT_DIR/final.md"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"
STATUS_AFTER="$(git -C "$TEST_PROJECT" status --porcelain -- src tests docs .joshix/plans)"
FINAL_ONE_LINE="$(printf '%s\n' "$FINAL_OUTPUT" | tr '\n' ' ')"

echo ""
echo "Verifying default plan review behavior..."
FAILED=0

assert_contains "$FINAL_OUTPUT" "reviewing.*plan|plan review|review.*implementation plan" "Treats bare pasted plan as review" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "not to execute|not.*approval.*execute|explicit.*(execute|implement|instruction)|execute.*explicit" "States execution requires explicit instruction" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_ONE_LINE" "Task 1.*(test-first|TDD|before.*test|test.*after|implement.*before.*test)" "Flags Task 1 TDD/order issue" || FAILED=$((FAILED + 1))
if has_missing_delivery_dependency "$FINAL_OUTPUT"; then
  echo '  [PASS] Flags undefined delivery dependency'
else
  echo '  [FAIL] Flags undefined delivery dependency'
  echo '  In output:'
  printf '%s\n' "$FINAL_OUTPUT" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi
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
