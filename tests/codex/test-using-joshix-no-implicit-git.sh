#!/usr/bin/env bash
# Behavior test: ordinary edits do not trigger implicit staging, commits, branches, or worktrees.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: no implicit git ops"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

printf 'original\n' > "$TEST_PROJECT/notes.txt"
git -C "$TEST_PROJECT" add notes.txt
git -C "$TEST_PROJECT" commit --quiet -m "Add notes"

INITIAL_BRANCH="$(git -C "$TEST_PROJECT" branch --show-current)"
INITIAL_COMMON_DIR="$(git -C "$TEST_PROJECT" rev-parse --git-common-dir)"

read -r -d '' PROMPT <<'EOF' || true
Use the using-joshix skill.

Change notes.txt so its entire contents are exactly:

updated

Report what you changed. Do not do extra work.
EOF

echo "Test project: $TEST_PROJECT"
echo "Running Codex edit request..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "workspace-write"

FINAL_FILE="$OUTPUT_DIR/final.md"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"

echo ""
echo "Verifying git discipline..."
FAILED=0

if [ "$(cat "$TEST_PROJECT/notes.txt")" = "updated" ]; then
    echo "  [PASS] File was edited"
else
    echo "  [FAIL] File was not edited as requested"
    printf '  Actual contents:\n'
    sed 's/^/    /' "$TEST_PROJECT/notes.txt"
    FAILED=$((FAILED + 1))
fi

commit_count="$(git -C "$TEST_PROJECT" log --oneline | wc -l | tr -d ' ')"
if [ "$commit_count" -eq 1 ]; then
    echo "  [PASS] No extra commits created"
else
    echo "  [FAIL] Unexpected commit count: $commit_count"
    git -C "$TEST_PROJECT" log --oneline | sed 's/^/    /'
    FAILED=$((FAILED + 1))
fi

if git -C "$TEST_PROJECT" diff --cached --quiet; then
    echo "  [PASS] No changes staged"
else
    echo "  [FAIL] Changes were staged"
    git -C "$TEST_PROJECT" status --porcelain | sed 's/^/    /'
    FAILED=$((FAILED + 1))
fi

CURRENT_BRANCH="$(git -C "$TEST_PROJECT" branch --show-current)"
if [ "$CURRENT_BRANCH" = "$INITIAL_BRANCH" ]; then
    echo "  [PASS] Stayed on current branch"
else
    echo "  [FAIL] Branch changed from $INITIAL_BRANCH to $CURRENT_BRANCH"
    FAILED=$((FAILED + 1))
fi

CURRENT_COMMON_DIR="$(git -C "$TEST_PROJECT" rev-parse --git-common-dir)"
if [ "$CURRENT_COMMON_DIR" = "$INITIAL_COMMON_DIR" ]; then
    echo "  [PASS] No worktree switch detected"
else
    echo "  [FAIL] Git common dir changed"
    echo "    Before: $INITIAL_COMMON_DIR"
    echo "    After:  $CURRENT_COMMON_DIR"
    FAILED=$((FAILED + 1))
fi

assert_not_contains "$FINAL_OUTPUT" "committed|staged|created.*branch|created.*worktree|switched.*branch" "Final response does not claim implicit git ops" || FAILED=$((FAILED + 1))

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
