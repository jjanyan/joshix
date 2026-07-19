#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Codex Behavior Test: parallel plan metadata and routing ==="

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

read -r -d '' PROMPT <<'EOF' || true
Use the writing-plans and executing-plans skills from this repo.

Show the task-heading metadata for two independent planned tasks. Explain
whether task order itself creates a dependency. Then explain how execution
routes (a) two independently implementable tasks with disjoint ownership and
(b) two tasks that modify the same files.

Give the two routing decisions as exactly two unbulleted single lines using
these labels:

Independent: <route for the disjoint tasks>
Overlap: <route for the tasks that modify the same files>

Name the applicable joshix skill or inline/serial execution mode on each line.
Do not propose branches, worktrees, staging, or commits.
EOF

run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "read-only"
FINAL_OUTPUT="$(cat "$OUTPUT_DIR/final.md")"
INDEPENDENT_LINE="$(printf '%s\n' "$FINAL_OUTPUT" | grep -Eim1 '^Independent:' || true)"
OVERLAP_LINE="$(printf '%s\n' "$FINAL_OUTPUT" | grep -Eim1 '^Overlap:' || true)"
FAILED=0

assert_contains "$FINAL_OUTPUT" "Depends on:\\*{0,2}[[:space:]]*None" "Uses explicit dependency metadata" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "order.*presentational|order.*no dependency|order.*does not.*depend" "Task order has no dependency meaning" || FAILED=$((FAILED + 1))
assert_contains "$INDEPENDENT_LINE" "^Independent:.*joshix:subagent-driven-development" "Routes independent disjoint work to SDD" || FAILED=$((FAILED + 1))
assert_contains "$OVERLAP_LINE" "^Overlap:.*(joshix:executing-plans|inline|serial)" "Keeps overlapping work inline or serial" || FAILED=$((FAILED + 1))
assert_contains "$OVERLAP_LINE" "same files|overlap|shared.*files|shared ownership" "Recognizes overlapping ownership on its route line" || FAILED=$((FAILED + 1))
assert_not_contains "$OVERLAP_LINE" "joshix:subagent-driven-development" "Does not route overlapping work to SDD" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "worktree is required|new branch is required|must.*(stage|commit)|should.*(stage|commit)" "Does not invent git operations" || FAILED=$((FAILED + 1))

if [ "$FAILED" -eq 0 ]; then
  echo "STATUS: PASSED"
  exit 0
fi

echo "STATUS: FAILED"
echo "Final output: $OUTPUT_DIR/final.md"
echo "Events: $OUTPUT_DIR/events.jsonl"
exit 1
