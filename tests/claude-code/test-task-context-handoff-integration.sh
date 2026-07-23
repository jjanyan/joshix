#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT/tests/codex/test-helpers.sh"
source "$SCRIPT_DIR/test-helpers.sh"

fail() {
  echo "FAIL: $*"
  exit 1
}

TEST_PROJECT="$(create_test_project)"
TEST_PROJECT="$(cd "$TEST_PROJECT" && pwd -P)"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT
init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"
[ ! -e "$TEST_PROJECT/.joshix" ] \
  || fail 'test project unexpectedly contains .joshix before Codex runs'

CODEX_ONE="$TEST_PROJECT/codex-one"
CODEX_TWO="$TEST_PROJECT/codex-two"
CLAUDE_OUTPUT="$TEST_PROJECT/claude-output.txt"
HELPER="$ROOT/skills/task-context/scripts/task-context.mjs"

read -r -d '' FIRST_PROMPT <<'EOF' || true
This is a new top-level Git-backed conversation for ticket CJ-66. Follow all
applicable joshix startup guidance. Record this decision in the shared current
state: initial-token-8372. Read-only Git inspection is allowed; do not mutate
Git state.
EOF
run_codex \
  "$TEST_PROJECT" \
  "$FIRST_PROMPT" \
  "$CODEX_ONE" \
  "workspace-write" \
  "$CODEX_TEST_TIMEOUT" \
  "ignore-rules"

shopt -s nullglob
TASK_DIRS=("$TEST_PROJECT"/.joshix/tasks/20??-??-??-CJ-66*)
[ "${#TASK_DIRS[@]}" -eq 1 ] \
  || fail 'first Codex run did not create exactly one CJ-66 task'
TASK_DIR="${TASK_DIRS[0]}"
TASK_NAME="$(basename "$TASK_DIR")"

read -r -d '' CLAUDE_PROMPT <<EOF || true
Use shared task $TASK_NAME. Read current.md first, retrieve only the missing
rows you need, and record the decision claude-token-4916 in the shared current
state. Do not export or scan the whole history. Read-only Git inspection is
allowed; do not mutate Git state.
EOF
(
  cd "$TEST_PROJECT"
  run_claude_stream "$CLAUDE_PROMPT" 300 "$CLAUDE_OUTPUT" \
    --allowed-tools=all --permission-mode bypassPermissions
)

rg -q 'claude-token-4916' "$TASK_DIR/current.md" \
  || fail 'Claude did not update current.md'
TEST_PROJECT_REAL="$(cd "$TEST_PROJECT" && pwd -P)"
SESSION_DIR="$HOME/.claude/projects/$(printf '%s' "$TEST_PROJECT_REAL" | sed 's|[^a-zA-Z0-9]|-|g')"
CLAUDE_SESSION="$(ls -t "$SESSION_DIR"/*.jsonl 2>/dev/null | head -1 || true)"
[ -n "$CLAUDE_SESSION" ] || fail 'Claude session transcript was not found'
CLAUDE_VISIBLE="$(jq -r '
  select(.type == "assistant")
  | .message.content[]?
  | select(.type == "text")
  | .text
' "$CLAUDE_SESSION")"
CLAUDE_NOTICE_COUNT="$( (printf '%s\n' "$CLAUDE_VISIBLE" \
  | rg -o 'Using shared task:' || true) | wc -l | tr -d '[:space:]')"
[ "$CLAUDE_NOTICE_COUNT" -eq 1 ] \
  || fail "expected one Claude usage notice, got $CLAUDE_NOTICE_COUNT"
CLAUDE_COMMANDS="$(jq -r '
  select(.type == "assistant")
  | .message.content[]?
  | select(.type == "tool_use" and .name == "Bash")
  | .input.command
' "$CLAUDE_SESSION")"
if printf '%s\n' "$CLAUDE_COMMANDS" \
  | rg -q 'task-context\.mjs[^[:cntrl:]]* export '; then
  fail 'Claude exported the full history instead of querying selectively'
fi
printf '%s\n' "$CLAUDE_COMMANDS" \
  | rg -q "/[^[:space:]\"']*/skills/task-context/scripts/task-context\\.mjs" \
  || fail 'Claude did not resolve an absolute helper path from the installed skill'

read -r -d '' SECOND_PROMPT <<EOF || true
Use shared task $TASK_NAME. What decision did Claude record? Read current.md
first and do not export or scan the whole history. Read-only Git inspection is
allowed; do not mutate Git state.
EOF
run_codex \
  "$TEST_PROJECT" \
  "$SECOND_PROMPT" \
  "$CODEX_TWO" \
  "workspace-write" \
  "$CODEX_TEST_TIMEOUT" \
  "ignore-rules"

CODEX_VISIBLE="$(jq -r 'select(.type == "item.completed" and .item.type == "agent_message") | .item.text' "$CODEX_TWO/events.jsonl")"
CODEX_NOTICE_COUNT="$( (printf '%s\n' "$CODEX_VISIBLE" | rg -o 'Using shared task:' || true) \
  | wc -l | tr -d '[:space:]')"
[ "$CODEX_NOTICE_COUNT" -eq 1 ] \
  || fail "expected one Codex usage notice, got $CODEX_NOTICE_COUNT"
rg -q 'claude-token-4916' "$CODEX_TWO/final.md" \
  || fail 'Codex did not recover the Claude decision'
CODEX_COMMANDS="$(jq -r '
  select(.type == "item.completed" and .item.type == "command_execution")
  | .item.command
' "$CODEX_TWO/events.jsonl")"
if printf '%s\n' "$CODEX_COMMANDS" \
  | rg -q 'task-context\.mjs[^[:cntrl:]]* export '; then
  fail 'Codex exported the full history instead of reading current.md first'
fi
printf '%s\n' "$CODEX_COMMANDS" \
  | rg -q "/[^[:space:]\"']*/skills/task-context/scripts/task-context\\.mjs" \
  || fail 'Codex did not resolve an absolute helper path from the installed skill'

CHECK_JSON="$(node --disable-warning=ExperimentalWarning "$HELPER" check "$TASK_DIR")"
printf '%s\n' "$CHECK_JSON" | rg -q '"ok": true'
HISTORY="$(node --disable-warning=ExperimentalWarning "$HELPER" export "$TASK_DIR" --format markdown)"
CREATED_ROWS="$( (printf '%s\n' "$HISTORY" | rg -c 'Shared task created:' || true) | tail -1)"
USAGE_ROWS="$( (printf '%s\n' "$HISTORY" | rg -c 'Using shared task:' || true) | tail -1)"
[ "${CREATED_ROWS:-0}" -eq 1 ] || fail 'creation notice was not recorded exactly once'
[ "${USAGE_ROWS:-0}" -eq 2 ] || fail 'both handoff notices were not recorded'
USER_LINE="$(printf '%s\n' "$HISTORY" | rg -n '## [0-9]+ · User ·' | head -1 | cut -d: -f1)"
CLAUDE_LINE="$(printf '%s\n' "$HISTORY" | rg -n '## [0-9]+ · Claude ·' | head -1 | cut -d: -f1)"
LAST_CODEX_LINE="$(printf '%s\n' "$HISTORY" | rg -n '## [0-9]+ · Codex ·' | tail -1 | cut -d: -f1)"
[ "$USER_LINE" -lt "$CLAUDE_LINE" ] && [ "$CLAUDE_LINE" -lt "$LAST_CODEX_LINE" ]
MAX_ID="$(node --disable-warning=ExperimentalWarning "$HELPER" recent "$TASK_DIR" --limit 1 --full \
  | rg -o '"id": [0-9]+' | awk '{print $2}')"
SUMMARY_ID="$(rg '^history_through:' "$TASK_DIR/current.md" | awk '{print $2}')"
[ "$SUMMARY_ID" -eq "$MAX_ID" ] \
  || fail "summary is at $SUMMARY_ID but history is at $MAX_ID"
[ "$(wc -w < "$TASK_DIR/current.md" | tr -d '[:space:]')" -le 1000 ] \
  || fail 'current summary exceeds 1,000 words'
[ -z "$(git -C "$TEST_PROJECT" status --porcelain -- .joshix/tasks)" ] \
  || fail 'task context leaked into Git status'

echo 'STATUS: PASSED'
