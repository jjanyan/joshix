#!/usr/bin/env bash
# Behavior test: core workflow guidance uses joshix defaults, not old upstream defaults.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: joshix guidance"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

read -r -d '' PROMPT <<'EOF' || true
Use the using-joshix, writing-plans, and subagent-driven-development skills from this repo.

Answer these questions in concise bullets:
1. Where should specs and plans be saved?
2. Which exact skill names should a plan handoff use for subagent-driven execution and inline execution?
3. What is the default git behavior for branch, worktree, staging, and commits?
4. What model selection guidance should delegated work follow?
EOF

echo "Test project: $TEST_PROJECT"
echo "Running Codex guidance query..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "read-only"

FINAL_FILE="$OUTPUT_DIR/final.md"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"

echo ""
echo "Verifying joshix guidance..."
FAILED=0

assert_contains "$FINAL_OUTPUT" "\\.joshix/specs" "Uses .joshix/specs for specs" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "\\.joshix/plans" "Uses .joshix/plans for plans" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "joshix:subagent-driven-development" "Uses joshix SDD skill name" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "joshix:executing-plans" "Uses joshix executing-plans skill name" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "current.*checkout|current.*branch|work in.*current" "Defaults to current checkout/branch" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "do not.*stage|do not.*commit|unless.*explicit|unless.*ask" "Does not stage or commit unless requested" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "current/default model|default model|current model|do not downgrade|without downgrading" "Uses current/default model guidance" || FAILED=$((FAILED + 1))

assert_not_contains "$FINAL_OUTPUT" "s[u]perpowers:" "Does not emit old skill namespace" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "docs/s[u]perpowers" "Does not use old docs paths" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "using-git-worktrees|finishing-a-development-branch" "Does not reference removed workflow skills" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "use.*least powerful|choose.*least powerful|cheap model|cheaper model|fast, cheap" "Does not recommend least-powerful model selection" || FAILED=$((FAILED + 1))

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
