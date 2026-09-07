#!/usr/bin/env bash
# Behavior test: receiver outcomes are authoritative and distinct from producer status.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: convergence outcomes"
echo "========================================"
echo ""

TEST_ROOT="$(create_test_project)"
trap 'cleanup_test_project "$TEST_ROOT"' EXIT
FAILED=0

init_case() {
  local project="$1"
  mkdir -p "$project/.joshix/specs"
  init_git_project "$project"
  install_repo_skills_symlink "$project"
  cp "$CODEX_REPO_ROOT/AGENTS.md" "$project/AGENTS.md"
}

assert_outcome() {
  local output="$1" expected="$2" label="$3"
  if validate_review_outcome "$output" "$expected"; then
    echo "  [PASS] $label"
  else
    echo "  [FAIL] $label"
    FAILED=$((FAILED + 1))
  fi
}

validate_unsettled_evidence_lane() {
  local output="$1"
  assert_exact_heading_count "$output" '### Evidence needed — no changes made' 1 \
    'Deterministic unsettled lane has one exact heading' >/dev/null \
    && printf '%s\n' "$output" | rg -q '^-[[:space:]]+\*\*[^*]+\*\*[[:space:]]+—[[:space:]]+Missing evidence:' \
    && ! printf '%s\n' "$output" | rg -q ' — (VALID|REJECT|DEFER)( · (CRITICAL|IMPORTANT|MINOR))?\*\*' \
    && validate_review_outcome "$output" 'Rereview required'
}

validate_retry_evidence_target() {
  local output="$1" evidence_lane
  evidence_lane="$(printf '%s\n' "$output" | awk '
    /^### Evidence needed — no changes made$/ { in_lane = 1; next }
    in_lane && /^### / { exit }
    in_lane { print }
  ')"

  printf '%s\n' "$evidence_lane" | rg -qi 'docs/retry-policy[.]md' \
    || { printf '%s\n' "$evidence_lane" | rg -qi 'approved|authoritative' \
      && printf '%s\n' "$evidence_lane" | rg -qi '(five|5).*(retr(y|ies)|attempt)|(retr(y|ies)|attempt).*(five|5)'; }
}

VALID_UNSETTLED_FIXTURE=$'### Evidence needed — no changes made\n\n- **Retry policy** — Missing evidence: the cited policy file is unavailable; Agent 2 must supply it.\n\n### Review outcome\n\n**Rereview required** — Agent 2 must supply the cited policy or accept the evidence gap.'
INVALID_SETTLED_FIXTURE=$'### Evidence needed — no changes made\n\n- **Retry policy — DEFER** — The cited policy file is unavailable.\n\n### Review outcome\n\n**Rereview required** — More evidence is needed.'
CLEAN_OUTCOME_FIXTURE=$'### Review outcome\n\n**Approved** — Both agents agree.'
VALID_RETRY_SOURCE_FIXTURE=$'### Evidence needed — no changes made\n\n- **Retry policy** — Missing evidence: `docs/retry-policy.md`.'
VALID_RETRY_FACT_FIXTURE=$'### Evidence needed — no changes made\n\n- **Retry policy** — Missing evidence: authoritative confirmation that five retries are approved.'
INVALID_GENERIC_EVIDENCE_FIXTURE=$'### Evidence needed — no changes made\n\n- **Retry policy** — Missing evidence: the supporting material.'
INVALID_UNRELATED_EVIDENCE_FIXTURE=$'### Evidence needed — no changes made\n\n- **Retry policy** — Missing evidence: the approved queue-ordering policy.'
if validate_unsettled_evidence_lane "$VALID_UNSETTLED_FIXTURE" \
    && ! validate_unsettled_evidence_lane "$INVALID_SETTLED_FIXTURE" \
    && validate_retry_evidence_target "$VALID_RETRY_SOURCE_FIXTURE" \
    && validate_retry_evidence_target "$VALID_RETRY_FACT_FIXTURE" \
    && ! validate_retry_evidence_target "$INVALID_GENERIC_EVIDENCE_FIXTURE" \
    && ! validate_retry_evidence_target "$INVALID_UNRELATED_EVIDENCE_FIXTURE" \
    && assert_exact_heading_count "$CLEAN_OUTCOME_FIXTURE" \
      '### No decision needed — no changes made' 0 \
      'Deterministic clean approval omits the no-change heading'; then
  echo '  [PASS] Deterministic unsettled-evidence and clean-approval fixtures'
else
  echo '  [FAIL] Deterministic unsettled-evidence or clean-approval fixture'
  exit 1
fi

CLEAN_PROJECT="$TEST_ROOT/clean-approval"
init_case "$CLEAN_PROJECT"
cat > "$CLEAN_PROJECT/.joshix/specs/retry.md" <<'EOF'
# Retry Design

- A failed job makes one initial attempt and then at most three retry attempts.
EOF
git -C "$CLEAN_PROJECT" add AGENTS.md .joshix/specs/retry.md
git -C "$CLEAN_PROJECT" commit --quiet -m 'Add clean approval fixture'
read -r -d '' CLEAN_PROMPT <<'EOF' || true
Here is another agent's spec review. Is this right?

## Spec Review

**Status:** Approved

The retry requirement is internally consistent. No issues found.
EOF
run_codex "$CLEAN_PROJECT" "$CLEAN_PROMPT" "$CLEAN_PROJECT/output" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"
CLEAN_FINAL="$(cat "$CLEAN_PROJECT/output/final.md")"
assert_outcome "$CLEAN_FINAL" 'Approved' 'Clean producer approval plus concurrence yields Approved'
assert_git_path_clean "$CLEAN_PROJECT" '.joshix/specs' \
  'Clean approval leaves the artifact unchanged' || FAILED=$((FAILED + 1))
assert_not_contains "$CLEAN_FINAL" ' — VALID' \
  'Approval is never rendered as a VALID issue' || FAILED=$((FAILED + 1))
assert_not_contains "$CLEAN_FINAL" '^### No decision needed — no changes made$' \
  'Clean approval omits the no-change compact heading' || FAILED=$((FAILED + 1))
assert_not_contains "$CLEAN_FINAL" '^### Handled without asking$' \
  'Clean approval omits the automatic-application heading' || FAILED=$((FAILED + 1))
assert_not_contains "$CLEAN_FINAL" '^### Applied as requested$' \
  'Clean approval omits the explicit-application heading' || FAILED=$((FAILED + 1))
assert_not_contains "$CLEAN_FINAL" '^### Evidence needed — no changes made$' \
  'Clean approval omits the unsettled-evidence heading' || FAILED=$((FAILED + 1))

EVIDENCE_PROJECT="$TEST_ROOT/unsettled-evidence"
init_case "$EVIDENCE_PROJECT"
cat > "$EVIDENCE_PROJECT/.joshix/specs/retry.md" <<'EOF'
# Retry Design

- A failed job makes one initial attempt and then at most three retry attempts.
EOF
git -C "$EVIDENCE_PROJECT" add AGENTS.md .joshix/specs/retry.md
git -C "$EVIDENCE_PROJECT" commit --quiet -m 'Add unsettled evidence fixture'
read -r -d '' EVIDENCE_PROMPT <<'EOF' || true
Here is another agent's spec review. Thoughts?

## Spec Review

**Status:** Issues Found

1. Change the retry count from three to five. The approved external policy at `docs/retry-policy.md` requires five, but that source is not present in this repository or included with the review. The claim is not disproved, but it cannot be independently verified from the available evidence.
EOF
run_codex "$EVIDENCE_PROJECT" "$EVIDENCE_PROMPT" "$EVIDENCE_PROJECT/output" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"
EVIDENCE_FINAL="$(cat "$EVIDENCE_PROJECT/output/final.md")"
assert_contains "$EVIDENCE_FINAL" '^### Evidence needed — no changes made$' \
  'Unverified reviewer claim uses the evidence-needed lane' || FAILED=$((FAILED + 1))
assert_not_contains "$EVIDENCE_FINAL" ' — (VALID|REJECT|DEFER)( · (CRITICAL|IMPORTANT|MINOR))?\*\*' \
  'Unverified reviewer claim has no settled issue classification' || FAILED=$((FAILED + 1))
if validate_retry_evidence_target "$EVIDENCE_FINAL"; then
  echo '  [PASS] Evidence-needed lane names the missing source or fact'
else
  echo '  [FAIL] Evidence-needed lane must name docs/retry-policy.md or the missing authoritative five-retry fact'
  FAILED=$((FAILED + 1))
fi
assert_contains "$EVIDENCE_FINAL" 'missing evidence|supply.*evidence|provide.*policy|provide.*evidence|accept|rebut' \
  'Evidence-needed lane states the recovery evidence or next exchange' || FAILED=$((FAILED + 1))
assert_outcome "$EVIDENCE_FINAL" 'Rereview required' \
  'Unverified reviewer claim requires another Agent 2 pass'
assert_git_path_clean "$EVIDENCE_PROJECT" '.joshix/specs' \
  'Unverified reviewer claim leaves the artifact unchanged' || FAILED=$((FAILED + 1))
assert_not_contains "$EVIDENCE_FINAL" '^### No decision needed — no changes made$' \
  'Evidence-needed response omits the compact no-change heading' || FAILED=$((FAILED + 1))
assert_not_contains "$EVIDENCE_FINAL" '^### Handled without asking$' \
  'Evidence-needed response omits the automatic-application heading' || FAILED=$((FAILED + 1))
assert_not_contains "$EVIDENCE_FINAL" '^### Applied as requested$' \
  'Evidence-needed response omits the explicit-application heading' || FAILED=$((FAILED + 1))

OWNER_PROJECT="$TEST_ROOT/owner-only-blocker"
init_case "$OWNER_PROJECT"
cat > "$OWNER_PROJECT/.joshix/specs/retry.md" <<'EOF'
# Retry Design

- A failed job makes one initial attempt and then at most three retry attempts.
EOF
git -C "$OWNER_PROJECT" add AGENTS.md .joshix/specs/retry.md
git -C "$OWNER_PROJECT" commit --quiet -m 'Add owner-only blocker fixture'
read -r -d '' OWNER_PROMPT <<'EOF' || true
Here is another agent's spec review. Thoughts?

## Spec Review

**Status:** Issues Found

1. Decide whether a new RetryPolicy service should own retry rules. This is a new architecture choice.
EOF
run_codex "$OWNER_PROJECT" "$OWNER_PROMPT" "$OWNER_PROJECT/output" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"
OWNER_FINAL="$(cat "$OWNER_PROJECT/output/final.md")"
assert_contains "$OWNER_FINAL" '^## .+\?$' \
  'Owner-only blocker uses the owner-decision lane' || FAILED=$((FAILED + 1))
assert_not_contains "$OWNER_FINAL" '^### Review outcome$' \
  'Owner-only blocker omits the review outcome lane' || FAILED=$((FAILED + 1))
assert_not_contains "$OWNER_FINAL" '^### No decision needed — no changes made$' \
  'Owner-only blocker omits the compact no-change heading' || FAILED=$((FAILED + 1))
assert_not_contains "$OWNER_FINAL" '^### Handled without asking$' \
  'Owner-only blocker omits the automatic-application heading' || FAILED=$((FAILED + 1))
assert_not_contains "$OWNER_FINAL" '^### Applied as requested$' \
  'Owner-only blocker omits the explicit-application heading' || FAILED=$((FAILED + 1))
assert_not_contains "$OWNER_FINAL" '^### Evidence needed — no changes made$' \
  'Owner-only blocker omits the unsettled-evidence heading' || FAILED=$((FAILED + 1))
assert_git_path_clean "$OWNER_PROJECT" '.joshix/specs' \
  'Owner-only blocker leaves the artifact unchanged' || FAILED=$((FAILED + 1))

REJECT_PROJECT="$TEST_ROOT/rejection-dispute"
init_case "$REJECT_PROJECT"
cat > "$REJECT_PROJECT/.joshix/specs/retry.md" <<'EOF'
# Retry Design

- Failed jobs retry at most three times.
EOF
git -C "$REJECT_PROJECT" add AGENTS.md .joshix/specs/retry.md
git -C "$REJECT_PROJECT" commit --quiet -m 'Add rejection fixture'
read -r -d '' REJECT_PROMPT <<'EOF' || true
Here is another agent's spec review. Thoughts?

## Spec Review

**Status:** Issues Found

1. The spec has no maximum retry limit and must add one.
EOF
run_codex "$REJECT_PROJECT" "$REJECT_PROMPT" "$REJECT_PROJECT/output" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"
REJECT_FINAL="$(cat "$REJECT_PROJECT/output/final.md")"
assert_contains "$REJECT_FINAL" '^### No decision needed — no changes made$' \
  'Rejection-only round uses the exact no-change heading' || FAILED=$((FAILED + 1))
assert_contains "$REJECT_FINAL" ' — REJECT' \
  'Receiver records the evidence-backed disagreement' || FAILED=$((FAILED + 1))
assert_git_path_clean "$REJECT_PROJECT" '.joshix/specs' \
  'Rejection-only dispute leaves the artifact unchanged' || FAILED=$((FAILED + 1))
assert_outcome "$REJECT_FINAL" 'Rereview required' 'Dispute requires Agent 2 to accept or rebut'
assert_contains "$REJECT_FINAL" 'accept|rebut|another review|review again' \
  'Rereview outcome explains the required next exchange' || FAILED=$((FAILED + 1))

DISPUTE_PROJECT="$TEST_ROOT/approval-disputed"
init_case "$DISPUTE_PROJECT"
cat > "$DISPUTE_PROJECT/.joshix/specs/access.md" <<'EOF'
# Access Design

## Requirements

- Guests may view public workspaces.

## Access Rules

- Only signed-in members may view any workspace.
EOF
git -C "$DISPUTE_PROJECT" add AGENTS.md .joshix/specs/access.md
git -C "$DISPUTE_PROJECT" commit --quiet -m 'Add disputed approval fixture'
read -r -d '' DISPUTE_PROMPT <<'EOF' || true
Here is another agent's spec review. What do you think?

## Spec Review

**Status:** Approved

No issues found.
EOF
run_codex "$DISPUTE_PROJECT" "$DISPUTE_PROMPT" "$DISPUTE_PROJECT/output" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"
DISPUTE_FINAL="$(cat "$DISPUTE_PROJECT/output/final.md")"
assert_outcome "$DISPUTE_FINAL" 'Approval disputed' 'Newly discovered contradiction disputes producer approval'
assert_contains "$DISPUTE_FINAL" '(guest|guests).*(public)|public.*(guest|guests)' \
  'Disputed outcome cites the guest/public permission' || FAILED=$((FAILED + 1))
assert_contains "$DISPUTE_FINAL" 'signed-in.*member|member.*signed-in|unsigned.*(prohibit|cannot|may not|view)|prohibit.*unsigned' \
  'Disputed outcome cites the signed-in/member restriction' || FAILED=$((FAILED + 1))
assert_contains "$DISPUTE_FINAL" 'contradict|conflict|inconsisten' \
  'Disputed outcome names the contradiction or conflict' || FAILED=$((FAILED + 1))
assert_git_path_clean "$DISPUTE_PROJECT" '.joshix/specs' \
  'New Agent 1 concern remains unchanged pending Agent 2 agreement' || FAILED=$((FAILED + 1))

DEFER_PROJECT="$TEST_ROOT/defer-convergence"
init_case "$DEFER_PROJECT"
cat > "$DEFER_PROJECT/.joshix/specs/access.md" <<'EOF'
# Access Design

## Access Rules

- Members may view their workspaces.
EOF
git -C "$DEFER_PROJECT" add AGENTS.md .joshix/specs/access.md
git -C "$DEFER_PROJECT" commit --quiet -m 'Add deferral fixture'
read -r -d '' DEFER_FIRST_PROMPT <<'EOF' || true
Here is another agent's spec review. Thoughts?

## Spec Review

**Status:** Issues Found

1. Rename `Access Rules` to `Authorization Rules` because it sounds more formal.
EOF
run_codex "$DEFER_PROJECT" "$DEFER_FIRST_PROMPT" "$DEFER_PROJECT/first-output" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"
DEFER_FIRST_FINAL="$(cat "$DEFER_PROJECT/first-output/final.md")"
assert_contains "$DEFER_FIRST_FINAL" ' — DEFER' \
  'First pass records the harmless naming preference as deferred' || FAILED=$((FAILED + 1))
assert_outcome "$DEFER_FIRST_FINAL" 'Rereview required' 'Unilateral deferral requires another review pass'

shopt -s nullglob
FIRST_TASK_DIRS=("$DEFER_PROJECT"/.joshix/tasks/20??-??-??-*)
[ "${#FIRST_TASK_DIRS[@]}" -eq 1 ] \
  || fail 'deferral first turn did not create exactly one shared task'
TASK_NAME="$(basename "${FIRST_TASK_DIRS[0]}")"
read -r -d '' DEFER_SECOND_PROMPT <<EOF || true
Use shared task $TASK_NAME.

Here is the later Agent 2 spec review.

## Spec Review

**Status:** Approved

No issues found. The earlier heading preference is non-blocking, and this review does not challenge Agent 1's DEFER reasoning.
EOF
run_codex "$DEFER_PROJECT" "$DEFER_SECOND_PROMPT" "$DEFER_PROJECT/second-output" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"
DEFER_SECOND_FINAL="$(cat "$DEFER_PROJECT/second-output/final.md")"
assert_outcome "$DEFER_SECOND_FINAL" 'Approved' 'Clean later review leaves accepted DEFER non-blocking'
assert_git_path_clean "$DEFER_PROJECT" '.joshix/specs' \
  'Accepted deferral never edits the artifact' || FAILED=$((FAILED + 1))
FINAL_TASK_DIRS=("$DEFER_PROJECT"/.joshix/tasks/20??-??-??-*)
[ "${#FINAL_TASK_DIRS[@]}" -eq 1 ] \
  || fail 'deferral continuation created a second shared task'
[ "${FINAL_TASK_DIRS[0]}" = "${FIRST_TASK_DIRS[0]}" ] \
  || fail 'deferral continuation switched shared tasks'

if [ "$FAILED" -eq 0 ]; then
  echo ""
  echo "STATUS: PASSED"
  exit 0
fi

echo ""
echo "STATUS: FAILED"
exit 1
