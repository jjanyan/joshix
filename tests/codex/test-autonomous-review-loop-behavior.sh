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
    'one provider attempt' \
    'ordinary SQLite message' \
    'repeats a rebutted disagreement without new evidence' \
    'same concrete defect is materially unchanged' \
    'There is no automatic retry or alternate provider' \
    '512 KiB' \
    'rolling 16 KiB'; do
    [[ "$normalized" == *"$expected"* ]]
  done
  for removed in \
    'correction rounds' 'session-unavailable' 'promptDigest' \
    'ReviewerTransport' 'configuration-stale'; do
    [[ "$normalized" != *"$removed"* ]]
  done
  test ! -e "$ROOT/skills/requesting-code-review/scripts/reviewer-runner.mjs"
  test ! -e "$ROOT/skills/requesting-code-review/review-record.schema.json"
  test ! -e "$ROOT/skills/requesting-code-review/review-failure-record.schema.json"
  echo 'STATUS: PASSED'
}

if [ "${1:-}" = '--oracle-only' ]; then
  oracle_only
  exit 0
fi

oracle_only >/dev/null
source "$SCRIPT_DIR/test-helpers.sh"
TEST_PROJECT="$(realpath "$(create_test_project)")"
TASK='.joshix/tasks/codex-to-claude-review'
TASK_PATH="$TEST_PROJECT/$TASK"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT/.joshix/plans" "$TEST_PROJECT/src"
"$ROOT/skills/task-context/scripts/task-context.mjs" init "$TASK_PATH" >/dev/null
cat > "$TEST_PROJECT/.joshix/plans/rollback-plan.md" <<'EOF'
# Approved rollback plan

Delete the recovery row inside the same transaction as the external operation.
If the transaction rolls back, recovery reads the deleted row afterward. The
plan is approved and implementation is active.
EOF
cat > "$TEST_PROJECT/src/cleanup.js" <<'EOF'
export async function cleanup(transaction, id) {
  const deletedRow = await transaction.recoveryRows.delete({ where: { id } });
  await transaction.performRiskyExternalOperation();
  await transaction.rollback();
  return recoveryReadsAfterRollback(deletedRow);
}
EOF
cat > "$TEST_PROJECT/review-request.md" <<'EOF'
Implementation of `.joshix/plans/rollback-plan.md` is active in
`src/cleanup.js`. Challenge the approved plan when its rollback assumption
creates a concrete recovery risk.
EOF
"$ROOT/skills/task-context/scripts/task-context.mjs" append "$TASK_PATH" \
  --speaker User --content-file "$TEST_PROJECT/review-request.md" >/dev/null

CURRENT_BEFORE="$(shasum -a 256 "$TEST_PROJECT/$TASK/current.md" | awk '{print $1}')"
SOURCE_BEFORE="$(shasum -a 256 "$TEST_PROJECT/src/cleanup.js" | awk '{print $1}')"
[ -x "$LAUNCHER" ] || { echo "FAIL: installed review bridge is missing: $LAUNCHER"; exit 1; }

if ! "$LAUNCHER" review \
  --provider claude \
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
      ($finding | test("rollback|transaction")) and
      ($finding | test("recover|deleted row"))))
' "$TEST_PROJECT/first-review.json" >/dev/null || {
  echo 'FAIL: Claude did not infer the cross-layer rollback risk'
  cat "$TEST_PROJECT/first-review.json"
  exit 1
}

cat > "$TEST_PROJECT/rereview-request.md" <<'EOF'
Run a fresh rereview. The prior reviewer result is ordinary SQLite history;
read it before assessing the still-unchanged implementation.
EOF
"$ROOT/skills/task-context/scripts/task-context.mjs" append "$TASK_PATH" \
  --speaker User --content-file "$TEST_PROJECT/rereview-request.md" >/dev/null
if ! "$LAUNCHER" review \
  --provider claude \
  --repo-root "$TEST_PROJECT" \
  --task-folder "$TASK" > "$TEST_PROJECT/second-review.json"; then
  cat "$TEST_PROJECT/second-review.json"
  exit 1
fi
jq -e '.ok == true' "$TEST_PROJECT/second-review.json" >/dev/null

"$ROOT/skills/task-context/scripts/task-context.mjs" recent "$TASK_PATH" --full \
  > "$TEST_PROJECT/history.json"
jq -e '[.[] | select(.speaker == "Claude Reviewer")] | length == 2' \
  "$TEST_PROJECT/history.json" >/dev/null
[ "$(shasum -a 256 "$TEST_PROJECT/$TASK/current.md" | awk '{print $1}')" = "$CURRENT_BEFORE" ]
[ "$(shasum -a 256 "$TEST_PROJECT/src/cleanup.js" | awk '{print $1}')" = "$SOURCE_BEFORE" ]

echo 'STATUS: PASSED'
