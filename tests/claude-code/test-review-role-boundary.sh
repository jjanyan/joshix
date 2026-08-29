#!/usr/bin/env bash
# Prompt-mode integration test: producer reviews stay read-only; received reviews use automatic reception.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Claude Integration Test: review role boundary"
echo "========================================"
echo ""

validate_claude_retry_replacement() {
  local spec_output="$1"
  printf '%s\n' "$spec_output" | grep -Eq '^-[[:space:]]+Failed jobs retry three times' \
    && ! printf '%s\n' "$spec_output" | grep -Eq '^-[[:space:]]+Failed jobs retry two times'
}

VALID_CLAUDE_RETRY='- Failed jobs retry three times.'
read -r -d '' STALE_AND_NEW_CLAUDE_RETRY <<'EOF' || true
- Failed jobs retry two times.
- Failed jobs retry three times.
EOF
if ! validate_claude_retry_replacement "$VALID_CLAUDE_RETRY" \
    || validate_claude_retry_replacement "$STALE_AND_NEW_CLAUDE_RETRY"; then
  echo '  [FAIL] Deterministic Claude retry replacement fixtures'
  exit 1
fi
echo '  [PASS] Deterministic Claude retry replacement fixtures'
if [ "${CLAUDE_REVIEW_ROLE_ORACLE_ONLY:-0}" = '1' ]; then
  echo 'STATUS: PASSED (oracle only)'
  exit 0
fi

TEST_ROOT="$(create_test_project)"
trap 'cleanup_test_project "$TEST_ROOT"' EXIT
FAILED=0

PRODUCER_PROJECT="$TEST_ROOT/producer"
mkdir -p "$PRODUCER_PROJECT/.joshix/specs"
cp "$CLAUDE_REPO_ROOT/CLAUDE.md" "$PRODUCER_PROJECT/CLAUDE.md"
cat > "$PRODUCER_PROJECT/.joshix/specs/session-design.md" <<'EOF'
# Session Design

## Requirements

- Sessions expire after 30 minutes.
- TODO: Define refresh behavior.
EOF
git -C "$PRODUCER_PROJECT" init --quiet
git -C "$PRODUCER_PROJECT" config user.email 'claude-test@example.com'
git -C "$PRODUCER_PROJECT" config user.name 'Claude Test'
git -C "$PRODUCER_PROJECT" add CLAUDE.md .joshix/specs/session-design.md
git -C "$PRODUCER_PROJECT" commit --quiet -m 'Add producer fixture'

PRODUCER_PROMPT='Review .joshix/specs/session-design.md.'
PRODUCER_OUTPUT="$(cd "$PRODUCER_PROJECT" && run_claude "$PRODUCER_PROMPT" 300)"
assert_contains "$PRODUCER_OUTPUT" 'joshix:reviewing-specs' \
  'Direct spec review routes to the spec producer skill' || FAILED=$((FAILED + 1))
assert_contains "$PRODUCER_OUTPUT" '^#\{1,2\}[[:space:]]\+Spec Review$' \
  'Direct spec review returns the detailed report' || FAILED=$((FAILED + 1))
assert_contains "$PRODUCER_OUTPUT" '\*\*Status:\*\*[[:space:]]*Issues Found' \
  'Direct spec review returns producer status' || FAILED=$((FAILED + 1))
if git -C "$PRODUCER_PROJECT" diff --quiet -- .joshix/specs/session-design.md; then
  echo '  [PASS] Producer leaves the reviewed spec unchanged'
else
  echo '  [FAIL] Producer edited the reviewed spec'
  FAILED=$((FAILED + 1))
fi

RECEIVER_PROJECT="$TEST_ROOT/receiver"
mkdir -p "$RECEIVER_PROJECT/.joshix/specs"
cp "$CLAUDE_REPO_ROOT/CLAUDE.md" "$RECEIVER_PROJECT/CLAUDE.md"
cat > "$RECEIVER_PROJECT/.joshix/specs/retry-design.md" <<'EOF'
# Retry Design

## Requirements

- The approved retry count is three.

## Failure Handling

- Failed jobs retry two times.
EOF
git -C "$RECEIVER_PROJECT" init --quiet
git -C "$RECEIVER_PROJECT" config user.email 'claude-test@example.com'
git -C "$RECEIVER_PROJECT" config user.name 'Claude Test'
git -C "$RECEIVER_PROJECT" add CLAUDE.md .joshix/specs/retry-design.md
git -C "$RECEIVER_PROJECT" commit --quiet -m 'Add receiver fixture'

read -r -d '' RECEIVER_PROMPT <<'EOF' || true
Here is another agent's spec review. What do you think?

The Failure Handling line contradicts the approved retry count. It must say `Failed jobs retry three times`.
EOF
RECEIVER_OUTPUT="$(cd "$RECEIVER_PROJECT" && run_claude "$RECEIVER_PROMPT" 300)"
if rg -q 'Failed jobs retry three times' "$RECEIVER_PROJECT/.joshix/specs/retry-design.md"; then
  echo '  [PASS] Received objective feedback is applied automatically'
else
  echo '  [FAIL] Received objective feedback was not applied automatically'
  FAILED=$((FAILED + 1))
fi
if rg -q 'Failed jobs retry two times' "$RECEIVER_PROJECT/.joshix/specs/retry-design.md"; then
  echo '  [FAIL] Received correction retained the stale two-times state'
  FAILED=$((FAILED + 1))
else
  echo '  [PASS] Received correction removes the stale two-times state'
fi
assert_contains "$RECEIVER_OUTPUT" '^### Handled without asking$' \
  'Receiver uses the automatic-application heading' || FAILED=$((FAILED + 1))
assert_not_contains "$RECEIVER_OUTPUT" "I'm reviewing the spec review as feedback to evaluate, not as approval to edit the spec." \
  'Receiver omits the exact review-only sentence in automatic mode' || FAILED=$((FAILED + 1))

if [ "$FAILED" -eq 0 ]; then
  echo ""
  echo "STATUS: PASSED"
  exit 0
fi

echo ""
echo "STATUS: FAILED"
exit 1
