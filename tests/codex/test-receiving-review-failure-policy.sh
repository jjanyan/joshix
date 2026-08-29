#!/usr/bin/env bash
# Behavior test: expected pre-edit diagnostics are usable, but unexpected post-edit failures stop the turn.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: review failure policy"
echo "========================================"
echo ""

TEST_ROOT="$(create_test_project)"
trap 'cleanup_test_project "$TEST_ROOT"' EXIT
FAILED=0

PRE_PROJECT="$TEST_ROOT/pre-application"
mkdir -p "$PRE_PROJECT/.joshix/specs"
init_git_project "$PRE_PROJECT"
install_repo_skills_symlink "$PRE_PROJECT"
cp "$CODEX_REPO_ROOT/AGENTS.md" "$PRE_PROJECT/AGENTS.md"
cat >> "$PRE_PROJECT/AGENTS.md" <<'EOF'

For received review feedback about retry-policy.md, run `./verify-review.sh`
before editing. Its expected initial failure is evidence for the reviewed
contradiction. Run it again after the edit.
EOF
cat > "$PRE_PROJECT/.joshix/specs/retry-policy.md" <<'EOF'
# Retry Policy

## Approved requirement

- The approved retry count is three.

## Runtime rule

- Failed jobs retry twice.
EOF
cat > "$PRE_PROJECT/verify-review.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CALL_LOG="$(cd "$(dirname "$0")" && pwd)/output/verify-review.calls"
if rg -q 'Failed jobs retry twice' .joshix/specs/retry-policy.md; then
  echo 'retry twice | exit 1' >> "$CALL_LOG"
  exit 1
fi
if rg -q 'Failed jobs retry three times' .joshix/specs/retry-policy.md; then
  echo 'retry three times | exit 0' >> "$CALL_LOG"
  exit 0
fi
echo 'unexpected retry state | exit 2' >> "$CALL_LOG"
exit 2
EOF
chmod +x "$PRE_PROJECT/verify-review.sh"

mkdir -p "$PRE_PROJECT/output" "$PRE_PROJECT/subdir"
set +e
(
  cd "$PRE_PROJECT/subdir"
  ../verify-review.sh >/dev/null 2>&1
)
PRE_SUBDIR_EXIT=$?
set -e
PRE_SUBDIR_LOG="$(cat "$PRE_PROJECT/output/verify-review.calls" 2>/dev/null || true)"
if [ "$PRE_SUBDIR_EXIT" -eq 2 ] \
    && [ "$PRE_SUBDIR_LOG" = 'unexpected retry state | exit 2' ]; then
  echo '  [PASS] Verifier call log is anchored to the fixture script directory'
else
  echo '  [FAIL] Verifier call log followed the caller working directory'
  printf '    exit: %s\n' "$PRE_SUBDIR_EXIT"
  printf '    root log: %s\n' "${PRE_SUBDIR_LOG:-<empty>}"
  FAILED=$((FAILED + 1))
fi
: > "$PRE_PROJECT/output/verify-review.calls"

PRE_CALL_LOG="$PRE_PROJECT/output/verify-review.calls"

pre_call_log_is_valid() {
  local call_log="$1"
  local actual_calls failure_count success_count total_count last_call

  actual_calls="$(cat "$call_log" 2>/dev/null || true)"
  failure_count="$(grep -cFx 'retry twice | exit 1' "$call_log" 2>/dev/null || true)"
  success_count="$(grep -cFx 'retry three times | exit 0' "$call_log" 2>/dev/null || true)"
  total_count="$(printf '%s\n' "$actual_calls" | awk 'NF { count++ } END { print count + 0 }')"
  last_call="$(printf '%s\n' "$actual_calls" | tail -n 1)"

  [ "$failure_count" -ge 1 ] \
    && [ "$success_count" -eq 1 ] \
    && [ "$total_count" -eq $((failure_count + success_count)) ] \
    && [ "$last_call" = 'retry three times | exit 0' ]
}

if [ "${FAILURE_POLICY_ORACLE_ONLY:-0}" = '1' ]; then
  printf '%s\n' \
    'retry twice | exit 1' \
    'retry twice | exit 1' \
    'retry three times | exit 0' > "$PRE_CALL_LOG"
else
  git -C "$PRE_PROJECT" add AGENTS.md .joshix/specs/retry-policy.md verify-review.sh
  git -C "$PRE_PROJECT" commit --quiet -m 'Add pre-application failure fixture'

  read -r -d '' PRE_PROMPT <<'EOF' || true
Here is another agent's spec review. What do you think?

The Runtime rule objectively contradicts the approved retry count. The expected diagnostic `./verify-review.sh` demonstrates that `retry twice` must become `retry three times`.
EOF
  run_codex "$PRE_PROJECT" "$PRE_PROMPT" "$PRE_PROJECT/output" \
    "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"
  PRE_FINAL="$(cat "$PRE_PROJECT/output/final.md")"
  assert_file_contains "$PRE_PROJECT/.joshix/specs/retry-policy.md" \
    'Failed jobs retry three times' \
    'Expected RED diagnostic guides the accepted correction' || FAILED=$((FAILED + 1))
fi

ACTUAL_PRE_CALLS="$(cat "$PRE_CALL_LOG" 2>/dev/null || true)"
if pre_call_log_is_valid "$PRE_CALL_LOG"; then
  echo '  [PASS] Diagnostic fails one or more times before editing and passes exactly once after editing'
else
  echo '  [FAIL] Expected one or more pre-edit failures followed by exactly one post-edit pass'
  if [ -n "$ACTUAL_PRE_CALLS" ]; then
    printf '%s\n' "$ACTUAL_PRE_CALLS" | sed 's/^/    /'
  else
    echo '    <no diagnostic calls recorded>'
  fi
  FAILED=$((FAILED + 1))
fi

if [ "${FAILURE_POLICY_ORACLE_ONLY:-0}" = '1' ]; then
  assert_pre_call_log_rejected() {
    local description="$1"
    shift
    printf '%s\n' "$@" > "$PRE_CALL_LOG"
    if pre_call_log_is_valid "$PRE_CALL_LOG"; then
      echo "  [FAIL] Oracle accepted $description"
      FAILED=$((FAILED + 1))
    else
      echo "  [PASS] Oracle rejects $description"
    fi
  }

  assert_pre_call_log_rejected \
    'duplicate post-edit success' \
    'retry twice | exit 1' \
    'retry three times | exit 0' \
    'retry three times | exit 0'
  assert_pre_call_log_rejected \
    'a pre-edit failure after success' \
    'retry twice | exit 1' \
    'retry three times | exit 0' \
    'retry twice | exit 1'
  assert_pre_call_log_rejected \
    'an unexpected diagnostic line' \
    'retry twice | exit 1' \
    'unexpected retry state | exit 2' \
    'retry three times | exit 0'

  if [ "$FAILED" -eq 0 ]; then
    echo 'STATUS: PASSED (oracle only)'
    exit 0
  fi
  echo 'STATUS: FAILED (oracle only)'
  exit 1
fi

assert_contains "$PRE_FINAL" '^### Handled without asking$' \
  'Successful automatic correction is reported as handled' || FAILED=$((FAILED + 1))
if validate_review_outcome "$PRE_FINAL" 'Rereview required'; then
  echo '  [PASS] Successful correction requires rereview'
else
  echo '  [FAIL] Successful correction lacks the exact rereview outcome'
  FAILED=$((FAILED + 1))
fi

POST_PROJECT="$TEST_ROOT/post-application"
mkdir -p "$POST_PROJECT/.joshix/specs"
init_git_project "$POST_PROJECT"
install_repo_skills_symlink "$POST_PROJECT"
cp "$CODEX_REPO_ROOT/AGENTS.md" "$POST_PROJECT/AGENTS.md"
cat >> "$POST_PROJECT/AGENTS.md" <<'EOF'

For received review feedback about retry-policy.md, edit findings in review
order. After each artifact edit and before any later edit, run
`./verify-review.sh`. If that verification fails, preserve the artifact's
exact state and stop all later artifact edits for the turn.
EOF
cat > "$POST_PROJECT/.joshix/specs/retry-policy.md" <<'EOF'
# Retry Policy

## Approved requirements

- The approved retry count is three.
- The approved backoff rule is exponential.

## Retry count

- Failed jobs retry two times.

## Backoff

- Retries use a fixed delay.
EOF
cat > "$POST_PROJECT/verify-review.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CALL_LOG="$(cd "$(dirname "$0")" && pwd)/output/verify-review.calls"
if rg -q 'Failed jobs retry three times' .joshix/specs/retry-policy.md \
    && rg -q 'Retries use a fixed delay' .joshix/specs/retry-policy.md; then
  echo 'retry three times; fixed delay | exit 23' >> "$CALL_LOG"
  exit 23
fi
if rg -q 'Failed jobs retry two times' .joshix/specs/retry-policy.md; then
  echo 'retry two times | exit 22' >> "$CALL_LOG"
  exit 22
fi
echo 'unexpected post-edit state | exit 24' >> "$CALL_LOG"
exit 24
EOF
chmod +x "$POST_PROJECT/verify-review.sh"
git -C "$POST_PROJECT" add AGENTS.md .joshix/specs/retry-policy.md verify-review.sh
git -C "$POST_PROJECT" commit --quiet -m 'Add post-application failure fixture'

read -r -d '' POST_PROMPT <<'EOF' || true
Here is another agent's spec review. Apply the objective feedback in review order. After the first artifact edit, run the repository-required verification before making the second edit.

1. The approved retry count is three, so the Retry count section must say `Failed jobs retry three times`.
2. The established backoff rule is exponential, so the later Backoff section must say `Retries use exponential backoff`.
EOF
run_codex "$POST_PROJECT" "$POST_PROMPT" "$POST_PROJECT/output" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"
POST_FINAL="$(cat "$POST_PROJECT/output/final.md")"
POST_CALL_LOG="$POST_PROJECT/output/verify-review.calls"
EXPECTED_POST=$'# Retry Policy\n\n## Approved requirements\n\n- The approved retry count is three.\n- The approved backoff rule is exponential.\n\n## Retry count\n\n- Failed jobs retry three times.\n\n## Backoff\n\n- Retries use a fixed delay.'
ACTUAL_POST="$(cat "$POST_PROJECT/.joshix/specs/retry-policy.md")"
if [ "$ACTUAL_POST" = "$EXPECTED_POST" ]; then
  echo '  [PASS] Preserves exact first-edit state and leaves the later correction untouched'
else
  echo '  [FAIL] Artifact state differs from the required preserve-and-stop boundary'
  printf '%s\n' "$ACTUAL_POST" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi
EXPECTED_POST_CALLS='retry three times; fixed delay | exit 23'
ACTUAL_POST_CALLS="$(cat "$POST_CALL_LOG" 2>/dev/null || true)"
if [ "$ACTUAL_POST_CALLS" = "$EXPECTED_POST_CALLS" ]; then
  echo '  [PASS] Verifier runs exactly once after the first edit and records exit 23'
else
  echo '  [FAIL] Expected exactly one post-first-edit verifier call recording exit 23'
  if [ -n "$ACTUAL_POST_CALLS" ]; then
    printf '%s\n' "$ACTUAL_POST_CALLS" | sed 's/^/    /'
  else
    echo '    <no post-edit verifier calls recorded>'
  fi
  FAILED=$((FAILED + 1))
fi
assert_contains "$POST_FINAL" 'changed[- ]but[- ]unverified|changed.*unverified|unverified.*changed|partial' \
  'Reports the first correction as changed but unverified' || FAILED=$((FAILED + 1))
assert_contains "$POST_FINAL" 'unattempted.*(Backoff|second|later)|(Backoff|second|later).*unattempted' \
  'Reports the later correction as unattempted' || FAILED=$((FAILED + 1))
assert_not_contains "$POST_FINAL" 'retry.* — VALID.*— .*(updated|handled|completed|fixed)' \
  'Does not call the failed retry item handled' || FAILED=$((FAILED + 1))
assert_contains "$POST_FINAL" 'exit(ed| code)?[[:space:]]+23|verify-review\.sh' \
  'Names exit 23 or the verification command as recovery evidence' || FAILED=$((FAILED + 1))
if validate_review_outcome "$POST_FINAL" 'Rereview required'; then
  echo '  [PASS] Post-failure response reports exactly one canonical rereview outcome'
else
  echo '  [FAIL] Expected exactly one canonical Rereview required outcome after failure'
  FAILED=$((FAILED + 1))
fi

if [ "$FAILED" -eq 0 ]; then
  echo ""
  echo "STATUS: PASSED"
  exit 0
fi

echo ""
echo "STATUS: FAILED"
echo "Pre-application output: $PRE_PROJECT/output/final.md"
echo "Post-application output: $POST_PROJECT/output/final.md"
exit 1
