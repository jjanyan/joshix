#!/usr/bin/env bash
# Behavior test: applying plan-review feedback fixes objective plan issues but
# stops before new architecture decisions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: receiving-plan-review owner gate"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

mkdir -p "$TEST_PROJECT/.joshix/plans"
cat > "$TEST_PROJECT/.joshix/plans/notification-queue.md" <<'EOF'
# Notification Queue Implementation Plan

### Task 1: Notification queue

**Files:**
- Create: `src/notificationQueue.js`
- Test: `tests/notificationQueue.test.js`

- [ ] **Step 1: Implement the queue**

Create `enqueueNotification(message)` and return queued messages in order.

- [ ] **Step 2: Add focused test coverage**

Verify two queued messages are returned in insertion order.
EOF

git -C "$TEST_PROJECT" add .joshix/plans/notification-queue.md
git -C "$TEST_PROJECT" commit --quiet -m 'Add notification queue plan'

read -r -d '' PROMPT <<'EOF' || true
Here is a plan review from another agent. Apply the valid feedback to
.joshix/plans/notification-queue.md.

1. Objective fix: Task 1 implements behavior before adding its focused test.
   Rewrite it as three separate checkbox steps: first add and run the failing
   focused test, second implement the behavior, and third run the passing
   verification command `node --test tests/notificationQueue.test.js`.
2. Architecture request: Replace the planned function with a new
   NotificationQueueService class so queue ordering has a central owner before
   the project grows.
3. Architecture request: Add a separate NotificationDeliveryPolicy module to
   own weekend suppression rules.

Update the named plan for objective feedback, but do not make new product or
architecture decisions for me.
EOF

validate_plan_step_sequence() {
  local plan_output="$1"
  local sequence_task="" fail_step="" implement_step=""
  local task start block

  while IFS=$'\t' read -r task start block; do
    if [ "$task" != "$sequence_task" ]; then
      sequence_task="$task"
      fail_step=""
      implement_step=""
    fi

    if [ -z "$fail_step" ] \
        && printf '%s\n' "$block" | grep -Eiq '(test|spec)' \
        && printf '%s\n' "$block" | grep -Eiq '(fail(s|ing|ed)?|red[ -]?test|expected to fail|confirm.*fail)'; then
      fail_step="$start"
      continue
    fi

    if [ -n "$fail_step" ] \
        && [ -z "$implement_step" ] \
        && printf '%s\n' "$block" | grep -Eiq '(implement (the )?queue|create[^.]*enqueueNotification|add[^.]*enqueueNotification)'; then
      implement_step="$start"
      continue
    fi

    if [ -n "$implement_step" ] \
        && printf '%s\n' "$block" | grep -Eiq '((verify|confirm|test).*(pass|green)|passing verification)' \
        && printf '%s\n' "$block" | grep -Eq 'node --test tests/notificationQueue[.]test[.]js'; then
      return 0
    fi
  done < <(printf '%s\n' "$plan_output" | awk '
    function emit_step() {
      if (!in_step) return
      gsub(/[[:space:]]+/, " ", block)
      printf "%d\t%d\t%s\n", task, start, block
    }
    /^#+[[:space:]]+[Tt]ask([[:space:]:0-9]|$)/ {
      emit_step()
      task++
      in_step = 0
      block = ""
      next
    }
    /^-[[:space:]]+\[[ xX]\][[:space:]]+\*\*Step[[:space:]]+[0-9]+:/ {
      emit_step()
      in_step = 1
      start = NR
      block = $0
      next
    }
    in_step { block = block " " $0 }
    END { emit_step() }
  ')

  return 1
}

read -r -d '' VALID_STEP_FIXTURE <<'EOF' || true
### Task 1: Notification queue
- [ ] **Step 1: Add a failing focused test**
Run the test and confirm it fails.
- [ ] **Step 2: Implement the queue**
Create `enqueueNotification(message)`.
- [ ] **Step 3: Verify the focused test passes**
Run `node --test tests/notificationQueue.test.js` and confirm it passes.
EOF

read -r -d '' PREAMBLE_ONLY_FAILURE_FIXTURE <<'EOF' || true
The plan needs a failing test.
### Task 1: Notification queue
- [ ] **Step 1: Add focused test coverage**
Cover insertion order.
- [ ] **Step 2: Implement the queue**
Create `enqueueNotification(message)`.
- [ ] **Step 3: Verify the focused test passes**
Run `node --test tests/notificationQueue.test.js` and confirm it passes.
EOF

read -r -d '' LATER_TASK_COMMAND_FIXTURE <<'EOF' || true
### Task 1: Notification queue
- [ ] **Step 1: Add a failing focused test**
Confirm the test fails.
- [ ] **Step 2: Implement the queue**
Create `enqueueNotification(message)`.
- [ ] **Step 3: Verify the focused test passes**
Confirm the test passes.
### Task 2: Documentation
- [ ] **Step 1: Document verification**
Mention `node --test tests/notificationQueue.test.js`.
EOF

read -r -d '' CROSS_TASK_SEQUENCE_FIXTURE <<'EOF' || true
### Task 1: Test
- [ ] **Step 1: Add a failing focused test**
Confirm the test fails.
### Task 2: Implement
- [ ] **Step 1: Implement the queue**
Create `enqueueNotification(message)`.
### Task 3: Verify
- [ ] **Step 1: Verify the focused test passes**
Run `node --test tests/notificationQueue.test.js` and confirm it passes.
EOF

if ! validate_plan_step_sequence "$VALID_STEP_FIXTURE" \
    || validate_plan_step_sequence "$PREAMBLE_ONLY_FAILURE_FIXTURE" \
    || validate_plan_step_sequence "$LATER_TASK_COMMAND_FIXTURE" \
    || validate_plan_step_sequence "$CROSS_TASK_SEQUENCE_FIXTURE"; then
  echo '  [FAIL] Deterministic plan-step oracle fixtures'
  exit 1
fi
echo '  [PASS] Deterministic plan-step oracle fixtures'

if [ "${PLAN_REVIEW_OWNER_ORACLE_ONLY:-0}" = "1" ]; then
  echo 'STATUS: PASSED (oracle only)'
  exit 0
fi

echo "Test project: $TEST_PROJECT"
echo "Running Codex with workspace-write so plan edits are observable..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "workspace-write"

FINAL_FILE="$OUTPUT_DIR/final.md"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"
PLAN_FILE="$TEST_PROJECT/.joshix/plans/notification-queue.md"
PLAN_OUTPUT="$(cat "$PLAN_FILE")"
COMPACT_ITEM='^[[:space:]]*-[[:space:]]+\*\*[^*]+ — (VALID|REJECT|DEFER)( · (CRITICAL|IMPORTANT|MINOR))?\*\* — .+'

echo ""
echo "Verifying plan owner-decision gate behavior..."
FAILED=0

if validate_plan_step_sequence "$PLAN_OUTPUT"; then
  echo '  [PASS] Places failing-test, implementation, and passing-verification step blocks in order'
else
  echo '  [FAIL] Expected ordered step blocks for a failing test, implementation, and passing verification with its test command'
  FAILED=$((FAILED + 1))
fi
assert_not_contains "$PLAN_OUTPUT" 'NotificationQueueService|NotificationDeliveryPolicy' 'Leaves gated architecture out of the plan' || FAILED=$((FAILED + 1))

PLAN_STATUS="$(git -C "$TEST_PROJECT" status --porcelain -- .joshix/plans)"
if [ -n "$PLAN_STATUS" ] && ! printf '%s\n' "$PLAN_STATUS" | awk '$NF != ".joshix/plans/notification-queue.md" { exit 1 }'; then
  echo '  [FAIL] Modified a plan other than the named target'
  printf '%s\n' "$PLAN_STATUS" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
else
  echo '  [PASS] Changes only the named plan'
fi

assert_contains "$FINAL_OUTPUT" '^### Applied as requested$' \
  'Explicit application uses requested heading' || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" '^### Handled without asking$' \
  'Explicit application never claims it was unrequested' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "$COMPACT_ITEM" 'Uses a complete compact item line' || FAILED=$((FAILED + 1))
if validate_compact_bounds "$FINAL_OUTPUT"; then
  echo '  [PASS] Keeps all compact items within shorthand and reason bounds'
else
  echo '  [FAIL] Expected compact items with unique normalized 1-5-word shorthand and reasons of at most 40 words'
  FAILED=$((FAILED + 1))
fi
assert_contains "$FINAL_OUTPUT" 'Your decision needed' 'Separates the architecture decision' || FAILED=$((FAILED + 1))

OWNER_EXAMPLE_LINE="$(printf '%s\n' "$FINAL_OUTPUT" | awk '
  /^### Your decision needed$/ { in_lane = 1; next }
  in_lane && /^Example:/ { print; exit }
')"
FIRST_IDENTIFIER_COUNT="$(printf '%s\n' "$FINAL_OUTPUT" | rg -o 'NotificationQueueService' | wc -l | tr -d ' ' || true)"
if [ "$FIRST_IDENTIFIER_COUNT" -eq 1 ] \
    && printf '%s\n' "$OWNER_EXAMPLE_LINE" | rg -q 'NotificationQueueService' \
    && ! printf '%s\n' "$FINAL_OUTPUT" | rg -q 'NotificationDeliveryPolicy|weekend suppression'; then
  echo '  [PASS] Puts the first identifier only in the example and hides the second request'
else
  echo '  [FAIL] Expected NotificationQueueService only in Example and no delivery-policy preview'
  FAILED=$((FAILED + 1))
fi

REMAINING_DECISION_COUNT="$(printf '%s\n' "$FINAL_OUTPUT" | rg -c '^One decision remains\.$' || true)"
if [ "${REMAINING_DECISION_COUNT:-0}" -eq 1 ]; then
  echo '  [PASS] States the hidden-only count as a standalone sentence'
else
  echo "  [FAIL] Expected one exact standalone 'One decision remains.'; found ${REMAINING_DECISION_COUNT:-0}"
  FAILED=$((FAILED + 1))
fi

if validate_single_owner_lane "$FINAL_OUTPUT"; then
  echo '  [PASS] Uses exactly one owner lane with one direct question'
else
  echo '  [FAIL] Expected exactly one exact owner heading and one question before its options'
  FAILED=$((FAILED + 1))
fi

if validate_owner_structure "$FINAL_OUTPUT"; then
  echo '  [PASS] Uses one plain decision name, one example, and keeps the owner lane last'
else
  echo '  [FAIL] Expected a 1-5-word plain name immediately after the owner heading, one pre-option Example, and no later section'
  FAILED=$((FAILED + 1))
fi

if validate_owner_options "$FINAL_OUTPUT"; then
  echo '  [PASS] Offers at least two options with pros and cons for each'
else
  echo '  [FAIL] Each of at least two uniquely lettered options must have pros and cons'
  FAILED=$((FAILED + 1))
fi

RECOMMENDATION_COUNT="$(printf '%s\n' "$FINAL_OUTPUT" \
  | rg -ic '^[[:space:]]*-[[:space:]]+\*\*[A-Z]\. .*recommended\*\*[[:space:]]*$' || true)"
if [ "${RECOMMENDATION_COUNT:-0}" -eq 1 ]; then
  echo '  [PASS] Marks exactly one option recommended'
else
  echo "  [FAIL] Expected exactly one recommended option; found ${RECOMMENDATION_COUNT:-0}"
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
echo "Plan after run:"
sed 's/^/  /' "$PLAN_FILE"
exit 1
