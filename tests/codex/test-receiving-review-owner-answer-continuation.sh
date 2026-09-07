#!/usr/bin/env bash
# Behavior test: a letter-only owner answer resumes agreed work in a fresh session.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: owner-answer continuation"
echo "========================================"
echo ""

validate_notification_retry_replacement() {
  local spec_output="$1"
  printf '%s\n' "$spec_output" | rg -q '^-[[:space:]]+Retry failed notifications three times' \
    && ! printf '%s\n' "$spec_output" | rg -q '^-[[:space:]]+Retry failed notifications two times'
}

VALID_NOTIFICATION_RETRY='- Retry failed notifications three times.'
read -r -d '' STALE_AND_NEW_NOTIFICATION_RETRY <<'EOF' || true
- Retry failed notifications two times.
- Retry failed notifications three times.
EOF
if ! validate_notification_retry_replacement "$VALID_NOTIFICATION_RETRY" \
    || validate_notification_retry_replacement "$STALE_AND_NEW_NOTIFICATION_RETRY"; then
  echo '  [FAIL] Deterministic notification retry replacement fixtures'
  exit 1
fi
echo '  [PASS] Deterministic notification retry replacement fixtures'
if [ "${OWNER_ANSWER_ORACLE_ONLY:-0}" = '1' ]; then
  echo 'STATUS: PASSED (oracle only)'
  exit 0
fi

TEST_PROJECT="$(create_test_project)"
FIRST_OUTPUT_DIR="$TEST_PROJECT/first-output"
SECOND_OUTPUT_DIR="$TEST_PROJECT/second-output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"
cp "$CODEX_REPO_ROOT/AGENTS.md" "$TEST_PROJECT/AGENTS.md"

mkdir -p "$TEST_PROJECT/.joshix/specs"
SPEC_FILE="$TEST_PROJECT/.joshix/specs/notification-retry-design.md"
cat > "$SPEC_FILE" <<'EOF'
# Notification Retry Design

## Requirements

- The approved retry count is three.

## Failure Handling

- Retry failed notifications two times.
- The retry rule remains inline in the delivery worker.
EOF

git -C "$TEST_PROJECT" add AGENTS.md .joshix/specs/notification-retry-design.md
git -C "$TEST_PROJECT" commit --quiet -m 'Add notification retry design'

read -r -d '' FIRST_PROMPT <<'EOF' || true
Here is another agent's spec review. What do you think?

1. The Failure Handling retry count objectively contradicts the approved requirement. It must say three times.
2. Decide whether a new NotificationPolicy service should own retry rules. This is an architecture choice.
3. If the policy-owner option is selected, replace the inline placement statement with `NotificationPolicy owns the retry rule`.

For the owner choice, use `Choice A: Add a policy owner` and `Choice B: Keep the rule inline` as the choice headings, with the recommended marker on your recommendation.
EOF

run_codex "$TEST_PROJECT" "$FIRST_PROMPT" "$FIRST_OUTPUT_DIR" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"

FIRST_FINAL="$(cat "$FIRST_OUTPUT_DIR/final.md")"
FAILED=0

assert_file_contains "$SPEC_FILE" 'Retry failed notifications three times' \
  'First turn applies the independent objective correction' || FAILED=$((FAILED + 1))
assert_not_contains "$(cat "$SPEC_FILE")" 'Retry failed notifications two times' \
  'First turn removes the stale two-times retry state' || FAILED=$((FAILED + 1))
assert_not_contains "$(cat "$SPEC_FILE")" 'NotificationPolicy' \
  'First turn leaves the owner-gated architecture untouched' || FAILED=$((FAILED + 1))
assert_file_contains "$SPEC_FILE" 'retry rule remains inline' \
  'First turn leaves the dependent placement correction blocked' || FAILED=$((FAILED + 1))
assert_contains "$FIRST_FINAL" '^### Choice A: Add a policy owner' \
  'First turn presents the requested A option' || FAILED=$((FAILED + 1))
assert_contains "$FIRST_FINAL" '^### Choice B: Keep the rule inline' \
  'First turn presents the requested B option' || FAILED=$((FAILED + 1))

validate_owner_structure "$FIRST_FINAL" || FAILED=$((FAILED + 1))

shopt -s nullglob
FIRST_TASK_DIRS=("$TEST_PROJECT"/.joshix/tasks/20??-??-??-*)
[ "${#FIRST_TASK_DIRS[@]}" -eq 1 ] \
  || fail 'first turn did not create exactly one shared task'
TASK_NAME="$(basename "${FIRST_TASK_DIRS[0]}")"
read -r -d '' SECOND_PROMPT <<EOF || true
Use shared task $TASK_NAME.
A
EOF
run_codex "$TEST_PROJECT" "$SECOND_PROMPT" "$SECOND_OUTPUT_DIR" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"

SECOND_FINAL="$(cat "$SECOND_OUTPUT_DIR/final.md")"
read -r -d '' EXPECTED_SECOND_SPEC <<'EOF' || true
# Notification Retry Design

## Requirements

- The approved retry count is three.

## Failure Handling

- Retry failed notifications three times.
- NotificationPolicy owns the retry rule.
EOF
ACTUAL_SECOND_SPEC="$(cat "$SPEC_FILE")"
if [ "$ACTUAL_SECOND_SPEC" = "$EXPECTED_SECOND_SPEC" ]; then
  echo '  [PASS] Owner continuation matches the exact agreed artifact'
else
  echo '  [FAIL] Owner continuation must preserve the exact selected replacement without restyling, elaboration, or duplication'
  printf '%s\n' '--- expected artifact ---' "$EXPECTED_SECOND_SPEC" '--- actual artifact ---' "$ACTUAL_SECOND_SPEC"
  FAILED=$((FAILED + 1))
fi
assert_contains "$SECOND_FINAL" '^### Applied as requested$' \
  'Owner answer continuation uses requested heading' || FAILED=$((FAILED + 1))
assert_not_contains "$SECOND_FINAL" '^### Handled without asking$' \
  'Owner answer is not described as unrequested' || FAILED=$((FAILED + 1))
assert_not_contains "$SECOND_FINAL" ' — VALID' \
  'Continuation does not repeat the completed compact list' || FAILED=$((FAILED + 1))
assert_not_contains "$SECOND_FINAL" 'should I proceed|want me to apply' \
  'Continuation does not ask for another permission round-trip' || FAILED=$((FAILED + 1))
if validate_review_outcome "$SECOND_FINAL" 'Rereview required'; then
  echo '  [PASS] Continuation reports exactly one rereview outcome'
else
  echo '  [FAIL] Expected exactly one Rereview required outcome'
  FAILED=$((FAILED + 1))
fi

FINAL_TASK_DIRS=("$TEST_PROJECT"/.joshix/tasks/20??-??-??-*)
[ "${#FINAL_TASK_DIRS[@]}" -eq 1 ] \
  || fail 'owner-answer continuation created a second shared task'
[ "${FINAL_TASK_DIRS[0]}" = "${FIRST_TASK_DIRS[0]}" ] \
  || fail 'owner-answer continuation switched shared tasks'

if [ "$FAILED" -eq 0 ]; then
  echo ""
  echo "STATUS: PASSED"
  exit 0
fi

echo ""
echo "STATUS: FAILED"
echo "First output: $FIRST_OUTPUT_DIR/final.md"
echo "Second output: $SECOND_OUTPUT_DIR/final.md"
exit 1
