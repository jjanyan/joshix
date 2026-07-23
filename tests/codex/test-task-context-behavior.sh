#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

fail() {
  echo "FAIL: $*"
  exit 1
}

TEST_PROJECT="$(create_test_project)"
TEST_PROJECT="$(cd "$TEST_PROJECT" && pwd -P)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT/.agents/tasks"

read -r -d '' PROMPT <<'EOF' || true
This is a new top-level conversation in a Git-backed repository. Follow all
applicable joshix startup guidance, then answer this one-turn question: What is
2 + 2? Read-only Git inspection is allowed; do not mutate Git state.
EOF

run_codex \
  "$TEST_PROJECT" \
  "$PROMPT" \
  "$OUTPUT_DIR" \
  "workspace-write" \
  "$CODEX_TEST_TIMEOUT" \
  "ignore-rules" \
  "$TEST_PROJECT/.agents/tasks"

shopt -s nullglob
TASK_DIRS=("$TEST_PROJECT"/.agents/tasks/20??-??-??-*)
[ "${#TASK_DIRS[@]}" -eq 1 ] || fail 'expected exactly one shared task folder'
TASK_DIR="${TASK_DIRS[0]}"

VISIBLE_MESSAGES="$(jq -r 'select(.type == "item.completed" and .item.type == "agent_message") | .item.text' "$OUTPUT_DIR/events.jsonl")"
NOTICE_COUNT="$( (printf '%s\n' "$VISIBLE_MESSAGES" | rg -o 'Shared task created:' || true) | wc -l | tr -d '[:space:]')"
[ "$NOTICE_COUNT" -eq 1 ] || fail "expected one creation notice, got $NOTICE_COUNT"
assert_contains "$(cat "$OUTPUT_DIR/final.md")" '4' 'one-turn question is answered'
[ -f "$TASK_DIR/current.md" ] || fail 'current summary exists'
[ -f "$TASK_DIR/history.sqlite" ] || fail 'history database exists'
[ -d "$TASK_DIR/files" ] || fail 'files directory exists'
[ "$(wc -w < "$TASK_DIR/current.md" | tr -d '[:space:]')" -le 1000 ] \
  || fail 'current summary exceeds 1,000 words'
assert_git_path_clean "$TEST_PROJECT" '.agents/tasks' 'task context is invisible to Git status'

HELPER="$CODEX_REPO_ROOT/skills/task-context/scripts/task-context.mjs"
ROWS="$(node --disable-warning=ExperimentalWarning "$HELPER" export "$TASK_DIR" --format markdown)"
assert_contains "$ROWS" '## 1 · User ·' 'user is the first speaker'
assert_contains "$ROWS" 'What is' 'user content is recorded'
assert_contains "$ROWS" '2 \+ 2' 'question content is recorded'
assert_contains "$ROWS" 'Codex' 'Codex visible output is recorded'

echo 'STATUS: PASSED'
