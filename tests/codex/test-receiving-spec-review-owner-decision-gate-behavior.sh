#!/usr/bin/env bash
# Behavior test: applying spec-review feedback fixes objective contradictions
# but stops before new product, scope, or architecture decisions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: receiving-spec-review owner gate"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

mkdir -p "$TEST_PROJECT/.joshix/specs"
cat > "$TEST_PROJECT/.joshix/specs/notification-delivery-design.md" <<'EOF'
# Notification Delivery Design

## Requirements

- Retry failed notifications three times.

## Failure Handling

- Retry failed notifications two times before reporting failure.
EOF

git -C "$TEST_PROJECT" add .joshix/specs/notification-delivery-design.md
git -C "$TEST_PROJECT" commit --quiet -m 'Add notification delivery design'

read -r -d '' PROMPT <<'EOF' || true
Here is a spec review from another agent. Apply the valid feedback to
.joshix/specs/notification-delivery-design.md.

1. Objective correction: Failure Handling says two retries, contradicting the
   approved requirement of three retries. Make Failure Handling say three.
2. Architecture request: Add a NotificationDeliveryPolicy service as the owner
   of notification retry rules.
3. Product request: Require a DurableNotificationQueue that makes pending
   notifications survive process restarts.

Update the named spec for objective feedback, but do not make new product,
scope, or architecture decisions for me.
EOF

echo "Test project: $TEST_PROJECT"
echo "Running Codex with workspace-write so spec edits are observable..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "workspace-write"

FINAL_FILE="$OUTPUT_DIR/final.md"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"
SPEC_FILE="$TEST_PROJECT/.joshix/specs/notification-delivery-design.md"
SPEC_OUTPUT="$(cat "$SPEC_FILE")"
FAILURE_HANDLING="$(awk '
  /^## Failure Handling$/ { capture = 1; next }
  capture && /^## / { capture = 0 }
  capture
' "$SPEC_FILE")"
COMPACT_ITEM='^[[:space:]]*-[[:space:]]+\*\*[^*]+ — (VALID|REJECT|DEFER)( · (CRITICAL|IMPORTANT|MINOR))?\*\* — .+'

echo ""
echo "Verifying spec owner-decision gate behavior..."
FAILED=0

assert_contains "$FAILURE_HANDLING" 'three times' 'Updates Failure Handling to three retries' || FAILED=$((FAILED + 1))
assert_not_contains "$FAILURE_HANDLING" 'two times' 'Removes the contradictory retry count' || FAILED=$((FAILED + 1))
assert_not_contains "$SPEC_OUTPUT" 'NotificationDeliveryPolicy|DurableNotificationQueue|process restarts' 'Leaves gated architecture and product behavior out of the spec' || FAILED=$((FAILED + 1))

SPEC_STATUS="$(git -C "$TEST_PROJECT" status --porcelain -- .joshix/specs)"
if [ -n "$SPEC_STATUS" ] && ! printf '%s\n' "$SPEC_STATUS" | awk '$NF != ".joshix/specs/notification-delivery-design.md" { exit 1 }'; then
  echo '  [FAIL] Modified a spec other than the named target'
  printf '%s\n' "$SPEC_STATUS" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
else
  echo '  [PASS] Changes only the named spec'
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
assert_contains "$FINAL_OUTPUT" '^[[:space:]]*-[[:space:]]+\*\*[^*]+ — VALID( · (CRITICAL|IMPORTANT|MINOR))?\*\* — .*(((three|3).*(retr|Failure Handling|correct))|((retr|Failure Handling|correct).*(three|3)))' 'Reports the corrected retry count' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" 'Your decision needed' 'Separates the architecture decision' || FAILED=$((FAILED + 1))

OWNER_EXAMPLE_LINE="$(printf '%s\n' "$FINAL_OUTPUT" | awk '
  /^### Your decision needed$/ { in_lane = 1; next }
  in_lane && /^Example:/ { print; exit }
')"
FIRST_IDENTIFIER_COUNT="$(printf '%s\n' "$FINAL_OUTPUT" | rg -o 'NotificationDeliveryPolicy' | wc -l | tr -d ' ' || true)"
if [ "$FIRST_IDENTIFIER_COUNT" -eq 1 ] \
    && printf '%s\n' "$OWNER_EXAMPLE_LINE" | rg -q 'NotificationDeliveryPolicy' \
    && ! printf '%s\n' "$FINAL_OUTPUT" | rg -q 'DurableNotificationQueue|process restarts'; then
  echo '  [PASS] Puts the first identifier only in the example and hides the second request'
else
  echo '  [FAIL] Expected NotificationDeliveryPolicy only in Example and no durable-queue preview'
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
echo "Spec after run:"
sed 's/^/  /' "$SPEC_FILE"
exit 1
