#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTRACT="$ROOT/skills/using-joshix/references/autonomous-review.md"
LAUNCHER="${JOSHIX_REVIEW_LAUNCHER:-$HOME/.local/share/joshix/reviewer-host/bin/joshix-review}"

oracle_only() {
  local normalized
  normalized="$(tr '\n\r\t' '   ' < "$CONTRACT" | tr -s ' ')"
  for expected in \
    'one fresh reviewer process' \
    'SQLite task history provides continuity' \
    'ordinary SQLite message' \
    'Codex runs fresh and ephemeral with' \
    'exec --ignore-user-config --ephemeral --ignore-rules --sandbox read-only' \
    'starts no retry or fallback'; do
    [[ "$normalized" == *"$expected"* ]] \
      || { printf 'FAIL: missing contract text: %s\n' "$expected"; return 1; }
  done
  [[ "$normalized" != *'one persistent reviewer session'* ]]
  [[ "$normalized" != *'correction rounds'* ]]
  test ! -e "$ROOT/skills/requesting-code-review/scripts/reviewer-runner.mjs"
  echo 'STATUS: PASSED'
}

if [ "${1:-}" = '--oracle-only' ]; then
  oracle_only
  exit 0
fi

oracle_only >/dev/null
source "$SCRIPT_DIR/test-helpers.sh"
TEST_PROJECT="$(realpath "$(create_test_project)")"
TASK='.joshix/tasks/claude-to-codex-review'
TASK_PATH="$TEST_PROJECT/$TASK"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

git -C "$TEST_PROJECT" init --quiet
mkdir -p "$TEST_PROJECT/.joshix/plans"
"$ROOT/skills/task-context/scripts/task-context.mjs" init "$TASK_PATH" >/dev/null
cat > "$TEST_PROJECT/.joshix/plans/test-order-plan.md" <<'EOF'
# Parser implementation plan

The approved requirement is strict test-driven development. Step 1 implements
the parser behavior. Step 2 adds tests after implementation is complete. No
implementation has started, and this plan is awaiting review.
EOF
cat > "$TEST_PROJECT/review-request.md" <<'EOF'
Review the active `.joshix/plans/test-order-plan.md` against the approved strict
test-driven-development requirement. No implementation exists yet.
EOF
"$ROOT/skills/task-context/scripts/task-context.mjs" append "$TASK_PATH" \
  --speaker User --content-file "$TEST_PROJECT/review-request.md" >/dev/null

CURRENT_BEFORE="$(shasum -a 256 "$TEST_PROJECT/$TASK/current.md" | awk '{print $1}')"
PLAN_BEFORE="$(shasum -a 256 "$TEST_PROJECT/.joshix/plans/test-order-plan.md" | awk '{print $1}')"
[ -x "$LAUNCHER" ] || { echo "FAIL: installed review bridge is missing: $LAUNCHER"; exit 1; }

if ! "$LAUNCHER" review \
  --provider codex \
  --repo-root "$TEST_PROJECT" \
  --task-folder "$TASK" > "$TEST_PROJECT/first-review.json"; then
  cat "$TEST_PROJECT/first-review.json"
  exit 1
fi

jq -e '
  .ok == true and .review.status == "issues" and
  (.review.findings | length) >= 1 and
  any(.review.findings[];
    (([.title, .evidence, .recommendation] | join(" ") | ascii_downcase) as $finding |
      ($finding | test("tdd|test-driven")) and
      ($finding | test("tests?[^.]*before[^.]*implement|implement[^.]*before[^.]*tests?|tests?[^.]*after[^.]*implement"))))
' "$TEST_PROJECT/first-review.json" >/dev/null || {
  echo 'FAIL: Codex did not infer the active plan test-order defect'
  cat "$TEST_PROJECT/first-review.json"
  exit 1
}

cat > "$TEST_PROJECT/rereview-request.md" <<'EOF'
Run a fresh rereview and use the prior Codex Reviewer message in SQLite as
continuity. The plan itself is unchanged.
EOF
"$ROOT/skills/task-context/scripts/task-context.mjs" append "$TASK_PATH" \
  --speaker User --content-file "$TEST_PROJECT/rereview-request.md" >/dev/null
if ! "$LAUNCHER" review \
  --provider codex \
  --repo-root "$TEST_PROJECT" \
  --task-folder "$TASK" > "$TEST_PROJECT/second-review.json"; then
  cat "$TEST_PROJECT/second-review.json"
  exit 1
fi
jq -e '.ok == true' "$TEST_PROJECT/second-review.json" >/dev/null

"$ROOT/skills/task-context/scripts/task-context.mjs" recent "$TASK_PATH" --full \
  > "$TEST_PROJECT/history.json"
jq -e '[.[] | select(.speaker == "Codex Reviewer")] | length == 2' \
  "$TEST_PROJECT/history.json" >/dev/null
[ "$(shasum -a 256 "$TEST_PROJECT/$TASK/current.md" | awk '{print $1}')" = "$CURRENT_BEFORE" ]
[ "$(shasum -a 256 "$TEST_PROJECT/.joshix/plans/test-order-plan.md" | awk '{print $1}')" = "$PLAN_BEFORE" ]

echo 'STATUS: PASSED'
