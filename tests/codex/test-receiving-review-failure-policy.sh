#!/usr/bin/env bash
# Behavior test: expected diagnostics and bounded post-edit recovery preserve exact state.
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
`./verify-review.sh`. If verification fails, diagnose the current state
read-only and follow joshix's bounded failure-recovery rule. Preserve the
artifact's exact state and never roll back a partial change.
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
    && rg -q 'Retries use exponential backoff' .joshix/specs/retry-policy.md; then
  echo 'retry three times; exponential backoff | exit 0' >> "$CALL_LOG"
  exit 0
fi
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
EXPECTED_POST=$'# Retry Policy\n\n## Approved requirements\n\n- The approved retry count is three.\n- The approved backoff rule is exponential.\n\n## Retry count\n\n- Failed jobs retry three times.\n\n## Backoff\n\n- Retries use exponential backoff.'
ACTUAL_POST="$(cat "$POST_PROJECT/.joshix/specs/retry-policy.md")"
if [ "$ACTUAL_POST" = "$EXPECTED_POST" ]; then
  echo '  [PASS] Applies one bounded recovery change without rolling back the first edit'
else
  echo '  [FAIL] Artifact state differs from the required recovered state'
  printf '%s\n' "$ACTUAL_POST" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi
EXPECTED_POST_CALLS=$'retry three times; fixed delay | exit 23\nretry three times; exponential backoff | exit 0'
ACTUAL_POST_CALLS="$(cat "$POST_CALL_LOG" 2>/dev/null || true)"
if [ "$ACTUAL_POST_CALLS" = "$EXPECTED_POST_CALLS" ]; then
  echo '  [PASS] Focused verifier records the failure once and the recovered success once'
else
  echo '  [FAIL] Expected one failed verification followed by one focused recovered success'
  if [ -n "$ACTUAL_POST_CALLS" ]; then
    printf '%s\n' "$ACTUAL_POST_CALLS" | sed 's/^/    /'
  else
    echo '    <no post-edit verifier calls recorded>'
  fi
  FAILED=$((FAILED + 1))
fi
assert_contains "$POST_FINAL" 'exit(ed| code)?[[:space:]]+23|fixed delay' \
  'Names the verification failure that was automatically recovered' || FAILED=$((FAILED + 1))
assert_contains "$POST_FINAL" 'verify-review\.sh|exit(ed| code)?[[:space:]]+0' \
  'Names the focused command or successful evidence' || FAILED=$((FAILED + 1))
assert_not_contains "$POST_FINAL" '^## .+\?$' \
  'Successful objective recovery does not ask the owner to restart the turn' || FAILED=$((FAILED + 1))
if validate_review_outcome "$POST_FINAL" 'Rereview required'; then
  echo '  [PASS] Recovered artifact change reports exactly one canonical rereview outcome'
else
  echo '  [FAIL] Expected exactly one canonical Rereview required outcome after recovery'
  FAILED=$((FAILED + 1))
fi

FAIL_PROJECT="$TEST_ROOT/recovery-failure"
mkdir -p "$FAIL_PROJECT/.joshix/specs"
init_git_project "$FAIL_PROJECT"
install_repo_skills_symlink "$FAIL_PROJECT"
cp "$CODEX_REPO_ROOT/AGENTS.md" "$FAIL_PROJECT/AGENTS.md"
cat >> "$FAIL_PROJECT/AGENTS.md" <<'EOF'

For received review feedback about retry-policy.md, edit findings in review
order and run `./verify-review.sh` after every edit. Diagnose failures read-only,
make only the bounded recovery authorized by joshix, preserve the artifact's
exact current state, and never roll back a partial change.
EOF
cat > "$FAIL_PROJECT/.joshix/specs/retry-policy.md" <<'EOF'
# Retry Policy

## Approved requirements

- The approved retry count is three.
- The approved backoff rule is exponential.
- Every audit line includes the attempt ID.

## Retry count

- Failed jobs retry two times.

## Backoff

- Retries use a fixed delay.

## Audit

- Audit lines omit the attempt ID.
EOF
cat > "$FAIL_PROJECT/verify-review.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CALL_LOG="$(cd "$(dirname "$0")" && pwd)/output/verify-review.calls"
if rg -q 'Failed jobs retry three times' .joshix/specs/retry-policy.md \
    && rg -q 'Retries use exponential backoff' .joshix/specs/retry-policy.md; then
  echo 'retry three times; exponential backoff | exit 24' >> "$CALL_LOG"
  exit 24
fi
if rg -q 'Failed jobs retry three times' .joshix/specs/retry-policy.md; then
  echo 'retry three times; fixed delay | exit 23' >> "$CALL_LOG"
  exit 23
fi
echo 'unexpected recovery state | exit 25' >> "$CALL_LOG"
exit 25
EOF
chmod +x "$FAIL_PROJECT/verify-review.sh"
git -C "$FAIL_PROJECT" add AGENTS.md .joshix/specs/retry-policy.md verify-review.sh
git -C "$FAIL_PROJECT" commit --quiet -m 'Add failed recovery fixture'

read -r -d '' FAIL_PROMPT <<'EOF' || true
Here is another agent's spec review. Apply the objective feedback in review order and run the required focused verification after every edit.

1. Change the Retry count sentence to `Failed jobs retry three times`.
2. Change the Backoff sentence to `Retries use exponential backoff`.
3. Change the Audit sentence to `Audit lines include the attempt ID`.
EOF
run_codex "$FAIL_PROJECT" "$FAIL_PROMPT" "$FAIL_PROJECT/output" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"
FAIL_FINAL="$(cat "$FAIL_PROJECT/output/final.md")"
FAIL_CALL_LOG="$FAIL_PROJECT/output/verify-review.calls"
EXPECTED_FAIL=$'# Retry Policy\n\n## Approved requirements\n\n- The approved retry count is three.\n- The approved backoff rule is exponential.\n- Every audit line includes the attempt ID.\n\n## Retry count\n\n- Failed jobs retry three times.\n\n## Backoff\n\n- Retries use exponential backoff.\n\n## Audit\n\n- Audit lines omit the attempt ID.'
ACTUAL_FAIL="$(cat "$FAIL_PROJECT/.joshix/specs/retry-policy.md")"
if [ "$ACTUAL_FAIL" = "$EXPECTED_FAIL" ]; then
  echo '  [PASS] Failed recovery preserves the exact partial state and leaves later work unattempted'
else
  echo '  [FAIL] Failed recovery did not preserve the exact required partial state'
  printf '%s\n' "$ACTUAL_FAIL" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi
EXPECTED_FAIL_CALLS=$'retry three times; fixed delay | exit 23\nretry three times; exponential backoff | exit 24'
ACTUAL_FAIL_CALLS="$(cat "$FAIL_CALL_LOG" 2>/dev/null || true)"
if [ "$ACTUAL_FAIL_CALLS" = "$EXPECTED_FAIL_CALLS" ]; then
  echo '  [PASS] A failed recovery verification does not open another pass'
else
  echo '  [FAIL] Expected exactly one initial failure and one failed recovery verification'
  printf '%s\n' "${ACTUAL_FAIL_CALLS:-<empty>}" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi
assert_contains "$FAIL_FINAL" 'changed[- ]but[- ]unverified|partial' \
  'Reports the failed recovery as partial or changed but unverified' || FAILED=$((FAILED + 1))
assert_contains "$FAIL_FINAL" 'unattempted.*Audit|Audit.*unattempted' \
  'Reports the later audit correction as unattempted' || FAILED=$((FAILED + 1))
assert_contains "$FAIL_FINAL" 'exit(ed| code)?[[:space:]]+24|verify-review\.sh' \
  'Names the failed recovery evidence' || FAILED=$((FAILED + 1))
assert_exact_heading_count "$FAIL_FINAL" '## .+\?' 1 \
  'Failed recovery emits one owner-decision lane' || FAILED=$((FAILED + 1))

CAP_PROJECT="$TEST_ROOT/recovery-cap"
mkdir -p "$CAP_PROJECT/.joshix/specs"
init_git_project "$CAP_PROJECT"
install_repo_skills_symlink "$CAP_PROJECT"
cp "$CODEX_REPO_ROOT/AGENTS.md" "$CAP_PROJECT/AGENTS.md"
cat >> "$CAP_PROJECT/AGENTS.md" <<'EOF'

For received review feedback about retry-policy.md, edit findings strictly in
review order and run `./verify-review.sh` after every edit. Follow joshix's
bounded failure-recovery rule, including its total cap across distinct failures.
Preserve exact partial state and never roll back.
EOF
cat > "$CAP_PROJECT/.joshix/specs/retry-policy.md" <<'EOF'
# Retry Policy

## Approved requirements

- Required timeout value: 30 seconds.
- Required backoff mode: exponential.
- Required attempt limit: three.
- Required jitter state: enabled.
- Required audit field: attempt ID.
- Required metrics field: job ID.

## Timeout

- Timeout is 10 seconds.

## Backoff

- Backoff is fixed.

## Attempts

- Attempt limit is one.

## Jitter

- Jitter is disabled.

## Audit

- Audit lines omit the attempt ID.

## Metrics

- Metrics omit the job ID.
EOF
cat > "$CAP_PROJECT/verify-review.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CALL_LOG="$(cd "$(dirname "$0")" && pwd)/output/verify-review.calls"
if rg -q 'Metrics include the job ID' .joshix/specs/retry-policy.md; then
  echo 'third recovery applied | exit 99' >> "$CALL_LOG"
  exit 99
fi
if rg -q 'Audit lines include the attempt ID' .joshix/specs/retry-policy.md; then
  echo 'audit changed; metrics old | exit 33' >> "$CALL_LOG"
  exit 33
fi
if rg -q 'Jitter is enabled' .joshix/specs/retry-policy.md; then
  echo 'second recovery green | exit 0' >> "$CALL_LOG"
  exit 0
fi
if rg -q 'Attempt limit is three' .joshix/specs/retry-policy.md; then
  echo 'attempts changed; jitter old | exit 22' >> "$CALL_LOG"
  exit 22
fi
if rg -q 'Backoff is exponential' .joshix/specs/retry-policy.md; then
  echo 'first recovery green | exit 0' >> "$CALL_LOG"
  exit 0
fi
if rg -q 'Timeout is 30 seconds' .joshix/specs/retry-policy.md; then
  echo 'timeout changed; backoff old | exit 11' >> "$CALL_LOG"
  exit 11
fi
echo 'unexpected cap state | exit 44' >> "$CALL_LOG"
exit 44
EOF
chmod +x "$CAP_PROJECT/verify-review.sh"
git -C "$CAP_PROJECT" add AGENTS.md .joshix/specs/retry-policy.md verify-review.sh
git -C "$CAP_PROJECT" commit --quiet -m 'Add total recovery cap fixture'

read -r -d '' CAP_PROMPT <<'EOF' || true
Here is another agent's spec review. Apply each objective finding strictly in order and run the repository-required focused verification after every edit.

1. Change Timeout to `Timeout is 30 seconds`.
2. Change Backoff to `Backoff is exponential`.
3. Change Attempts to `Attempt limit is three`.
4. Change Jitter to `Jitter is enabled`.
5. Change Audit to `Audit lines include the attempt ID`.
6. Change Metrics to `Metrics include the job ID`.
EOF
run_codex "$CAP_PROJECT" "$CAP_PROMPT" "$CAP_PROJECT/output" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"
CAP_FINAL="$(cat "$CAP_PROJECT/output/final.md")"
CAP_CALL_LOG="$CAP_PROJECT/output/verify-review.calls"
EXPECTED_CAP_CALLS=$'timeout changed; backoff old | exit 11\nfirst recovery green | exit 0\nattempts changed; jitter old | exit 22\nsecond recovery green | exit 0\naudit changed; metrics old | exit 33'
ACTUAL_CAP_CALLS="$(cat "$CAP_CALL_LOG" 2>/dev/null || true)"
if [ "$ACTUAL_CAP_CALLS" = "$EXPECTED_CAP_CALLS" ]; then
  echo '  [PASS] Two distinct recovery passes cannot become a third pass'
else
  echo '  [FAIL] Recovery-cap call sequence was not bounded at two passes'
  printf '%s\n' "${ACTUAL_CAP_CALLS:-<empty>}" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi
assert_file_contains "$CAP_PROJECT/.joshix/specs/retry-policy.md" \
  'Audit lines include the attempt ID' \
  'The third triggering edit remains in exact partial state' || FAILED=$((FAILED + 1))
assert_file_contains "$CAP_PROJECT/.joshix/specs/retry-policy.md" \
  'Metrics omit the job ID' \
  'The would-be third recovery remains unattempted' || FAILED=$((FAILED + 1))
assert_contains "$CAP_FINAL" 'third recovery|third pass|two recovery|recovery cap' \
  'Reports the total recovery cap as the stopping reason' || FAILED=$((FAILED + 1))
assert_contains "$CAP_FINAL" 'unattempted.*Metrics|Metrics.*unattempted' \
  'Reports the capped recovery as unattempted' || FAILED=$((FAILED + 1))
assert_exact_heading_count "$CAP_FINAL" '## .+\?' 1 \
  'Recovery cap emits one owner-decision lane' || FAILED=$((FAILED + 1))

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
