#!/usr/bin/env bash
# Behavior test: referenced design specs default to review, not editing or execution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

has_seeded_timeout_contradiction() {
  local output="$1"
  local normalized relation
  normalized="$(printf '%s\n' "$output" | tr '\n\r\t' '   ' | tr -s ' ')"
  relation='(contradict|conflict|inconsisten|versus|vs[.]?|while)'

  printf '%s\n' "$normalized" | grep -Eiq \
    "(${relation}[^.!?]{0,240}(30[^.!?]{0,220}60|60[^.!?]{0,220}30)|(30[^.!?]{0,220}60|60[^.!?]{0,220}30)[^.!?]{0,240}${relation}|30[^.!?]{0,220}${relation}[^.!?]{0,220}60|60[^.!?]{0,220}${relation}[^.!?]{0,220}30)"
}

worktree_status_except_output() {
  git -C "$1" status --porcelain --untracked-files=all -- \
    . ':(exclude)output' ':(exclude)output/**'
}

echo "========================================"
echo " Codex Behavior Test: reviewing-specs"
echo "========================================"
echo ""

VALID_CONTRADICTION='The requirements set 30 minutes, while Timeout Behavior sets 60 minutes.'
VALID_REVERSED='The 60-minute timeout conflicts with the required 30-minute timeout.'
INVALID_SUBJECT_ONLY='The session timeout design is ready for implementation.'
INVALID_GENERIC='The timeout duration is contradictory.'
INVALID_UNRELATED_DURATIONS='Warn at 30 minutes. Retry another operation after 60 minutes.'
INVALID_SUPPORTED_DURATIONS='The system supports 30 and 60 minutes, but the default is configurable.'

if ! has_seeded_timeout_contradiction "$VALID_CONTRADICTION" \
    || ! has_seeded_timeout_contradiction "$VALID_REVERSED" \
    || has_seeded_timeout_contradiction "$INVALID_SUBJECT_ONLY" \
    || has_seeded_timeout_contradiction "$INVALID_GENERIC" \
    || has_seeded_timeout_contradiction "$INVALID_UNRELATED_DURATIONS" \
    || has_seeded_timeout_contradiction "$INVALID_SUPPORTED_DURATIONS"; then
  echo '  [FAIL] Deterministic timeout-contradiction oracle fixtures'
  exit 1
fi
echo '  [PASS] Deterministic timeout-contradiction oracle fixtures'

if [ "${REVIEWING_SPECS_ORACLE_ONLY:-0}" = "1" ]; then
  echo 'STATUS: PASSED (oracle only)'
  exit 0
fi

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

mkdir -p "$TEST_PROJECT/.joshix/specs"
cat > "$TEST_PROJECT/AGENTS.md" <<'EOF'
# Test Agent Guidance

Use `joshix:using-joshix` before responding.
EOF
cat > "$TEST_PROJECT/.joshix/specs/session-timeout-design.md" <<'EOF'
# Session Timeout Design

## Requirements

- End an inactive session after 30 minutes.
- Warn the user five minutes before the session ends.

## Timeout Behavior

- End an inactive session after 60 minutes.
EOF

git -C "$TEST_PROJECT" add AGENTS.md .joshix/specs/session-timeout-design.md
git -C "$TEST_PROJECT" commit --quiet -m 'Add session timeout design'
WORKTREE_STATUS_BEFORE="$(worktree_status_except_output "$TEST_PROJECT")"

read -r -d '' PROMPT <<'EOF' || true
Review .joshix/specs/session-timeout-design.md for implementation readiness.
Do not edit the spec or execute implementation work.
EOF

echo "Test project: $TEST_PROJECT"
echo "Running Codex with workspace-write so accidental edits are observable..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" \
  "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"

FINAL_FILE="$OUTPUT_DIR/final.md"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"
EXPECTED_OPENING="I'm using joshix:reviewing-specs to review this spec by default, not to edit it."
FIRST_NONEMPTY_LINE="$(first_nonempty_trimmed_line < "$FINAL_FILE")"
WORKTREE_STATUS_AFTER="$(worktree_status_except_output "$TEST_PROJECT")"

echo ""
echo "Verifying default spec review behavior..."
FAILED=0
if [ "$FIRST_NONEMPTY_LINE" = "$EXPECTED_OPENING" ]; then
  echo '  [PASS] Uses the exact spec-producer opening'
else
  echo '  [FAIL] Expected the exact spec-producer opening'
  echo "  Expected: $EXPECTED_OPENING"
  echo "  Actual: ${FIRST_NONEMPTY_LINE:-<empty>}"
  FAILED=$((FAILED + 1))
fi
assert_contains "$FINAL_OUTPUT" '^# Spec Review|^## Spec Review' \
  'Uses detailed spec review format' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" '\*\*Status:\*\*[[:space:]]*Issues Found' \
  'Reports provisional producer status' || FAILED=$((FAILED + 1))
if has_seeded_timeout_contradiction "$FINAL_OUTPUT"; then
  echo '  [PASS] Finds the seeded 30-minute versus 60-minute contradiction'
else
  echo '  [FAIL] Expected a finding connecting the conflicting 30-minute and 60-minute durations'
  FAILED=$((FAILED + 1))
fi
if [ "$WORKTREE_STATUS_AFTER" = "$WORKTREE_STATUS_BEFORE" ]; then
  echo '  [PASS] Spec producer leaves the full fixture worktree unchanged outside output/'
else
  echo '  [FAIL] Fixture worktree changed outside expected output/ artifacts'
  echo '  Before:'
  printf '%s\n' "$WORKTREE_STATUS_BEFORE" | sed 's/^/    /'
  echo '  After:'
  printf '%s\n' "$WORKTREE_STATUS_AFTER" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi

if [ "$FAILED" -ne 0 ]; then
  echo 'STATUS: FAILED'
  exit 1
fi

echo 'STATUS: PASSED'
