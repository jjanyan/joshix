#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTRACT="$ROOT/skills/using-joshix/references/autonomous-review.md"
RUNNER="$ROOT/skills/requesting-code-review/scripts/reviewer-runner.mjs"
LAUNCHER="${JOSHIX_REVIEW_LAUNCHER:-$HOME/.local/share/joshix/reviewer-host/bin/joshix-review}"

oracle_only() {
  rg -Fq -- 'OpenAI and Anthropic are the complete authorized' "$CONTRACT"
  rg -Fq -- 'one persistent reviewer session per task' "$CONTRACT"
  rg -Fq -- 'read shared task history' "$CONTRACT"
  rg -Fq -- 'The coordinator is the only writer' "$CONTRACT"
  rg -Fq -- "'exec', '--sandbox', 'read-only', '--cd', repoRoot" "$RUNNER"
  rg -Fq -- "'resume', '--ignore-rules'" "$RUNNER"
  ! rg -Fq -- "'--ignore-user-config'" "$RUNNER"
  ! rg -Fq -- "'--ephemeral'" "$RUNNER"
  rg -Fq -- "'--output-schema', schemaFile" "$RUNNER"
  rg -Fq -- 'version 2' "$CONTRACT"
  rg -Fq -- 'version 1 history stays readable' "$CONTRACT"
  echo 'STATUS: PASSED'
}

if [ "${1:-}" = '--oracle-only' ]; then
  oracle_only
  exit 0
fi

oracle_only >/dev/null
source "$SCRIPT_DIR/test-helpers.sh"
TEST_PROJECT="$(realpath "$(create_test_project)")"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT
[ -x "$LAUNCHER" ] || { echo "FAIL: installed reviewer launcher is not executable: $LAUNCHER"; exit 1; }
# This fixture represents a top-level Claude coordinator, not its parent Codex test process.
unset CODEX_SANDBOX CODEX_SANDBOX_NETWORK_DISABLED
git -C "$TEST_PROJECT" init --quiet
cat > "$TEST_PROJECT/.gitignore" <<'EOF'
.joshix/tasks/
EOF
cat > "$TEST_PROJECT/AGENTS.md" <<'EOF'
joshix-workflow-policy: workflow-policy.md
EOF
cat > "$TEST_PROJECT/workflow-policy.md" <<'EOF'
# Synthetic policy

Tiers from highest to lowest: protected, standard, cosmetic. Authorization and
data effects are protected, ordinary developer workflow is standard, and
presentation-only effects are cosmetic. Findings use the endangered outcome's
tier. Protected gets exhaustive invariant tests and every selected review gate;
standard gets one behavior test and one whole-change review; cosmetic gets no
new automated tests unless recurring and one whole-change review. Completion
check: `git diff --check`. All repository safety rules remain unconditional.
EOF

cat > "$TEST_PROJECT/coordinator-review-prompt.md" <<EOF
You are the persistent reviewer peer for this task. Remain read-only.
Task folder: .joshix/tasks/claude-coordinator-flow/
Read helper: $ROOT/skills/task-context/scripts/task-context.mjs
Gate: whole-change
Round: 1
Review target: workflow-policy.md
Diff/log evidence: none
Focused verification: oracle-only checks passed

Read current.md and query task history as needed. Return an approved review
with no findings as JSON matching the supplied schema. Never append task
history or edit repository files.
EOF

read -r -d '' COORDINATOR_PROMPT <<EOF || true
Use joshix as the top-level Claude coordinator in this repository. Use shared
task .joshix/tasks/claude-coordinator-flow. The declared task is a standard-tier
review-fixture surface, trivial complexity, five minutes effort, and scope only
to run and record one whole-change review without product edits. Run the Codex
review yourself by invoking this exact installed host-launcher command:
$LAUNCHER review --provider codex --repo-root $TEST_PROJECT --prompt-file $TEST_PROJECT/coordinator-review-prompt.md --result-schema review-result-v1 --timeout-ms 120000 --max-events 500 --max-output-bytes 524288 --max-review-bytes 65536
Construct and validate review-record.schema.json, append it exactly once with
the canonical idempotency key as speaker Reviewer, and atomically update the
complete workflow snapshot without losing declaration fields. Do not ask the
owner to invoke or relay anything. Finish after recording and report the
provider and history ID.
EOF
OUTPUT="$(
  cd "$TEST_PROJECT"
  run_claude "$COORDINATOR_PROMPT" 240
)"
assert_contains "$OUTPUT" '[Cc]odex' 'Claude selects Codex cross-provider'
assert_not_contains "$OUTPUT" 'ask.*owner.*paste\|ask.*owner.*relay' 'Claude does not broker routine review through owner'
TASK_FOLDER="$TEST_PROJECT/.joshix/tasks/claude-coordinator-flow"
[ -f "$TASK_FOLDER/history.sqlite" ] || { echo 'FAIL: Claude coordinator did not create task history'; exit 1; }
(
  cd "$TEST_PROJECT"
  node "$ROOT/skills/task-context/scripts/task-context.mjs" recent .joshix/tasks/claude-coordinator-flow --full
) > "$TEST_PROJECT/history.json"
[ "$(jq '[.[] | select(.speaker == "Reviewer")] | length' "$TEST_PROJECT/history.json")" = '1' ] \
  || { echo 'FAIL: Claude coordinator did not append exactly one review record'; exit 1; }
jq -r '.[] | select(.speaker == "Reviewer") | .content' "$TEST_PROJECT/history.json" > "$TEST_PROJECT/coordinator-record.json"
if ! jq -e '
  .schemaVersion == 2 and .gate == "whole-change" and .round == 1 and
  .reviewer.requestedProvider == "codex" and .reviewer.usedProvider == "codex" and
  .reviewer.path == "cross-provider-cli" and .reviewer.fallback == null and
  (.reviewer.session.id | test("^[0-9a-f-]{36}$")) and
  .reviewer.session.mode == "started" and
  (.promptDigest | test("^sha256:[0-9a-f]{64}$")) and
  .review.status == "approved" and (.review.findings | length) == 0
' "$TEST_PROJECT/coordinator-record.json" >/dev/null; then
  echo 'FAIL: Claude coordinator wrote an invalid review record'
  cat "$TEST_PROJECT/coordinator-record.json"
  exit 1
fi
for field in Surfaces Complexity Effort 'Outcome/scope' 'Active time' Review Deferred; do
  rg -Fq -- "- $field:" "$TASK_FOLDER/current.md" \
    || { echo "FAIL: Claude coordinator snapshot lost $field"; exit 1; }
done
rg -q -- '- Review: `whole-change; round 1; cross-provider-cli; codex session [0-9a-f-]{36}; history [0-9]+`' "$TASK_FOLDER/current.md" \
  || { echo 'FAIL: Claude coordinator snapshot lost persistent reviewer identity'; exit 1; }
[ ! -e "$TASK_FOLDER/.current.md.tmp" ] || { echo 'FAIL: Claude coordinator left a temporary snapshot'; exit 1; }

cat > "$TEST_PROJECT/review-prompt.md" <<EOF
You are the persistent reviewer peer for this task. Remain read-only.
Task folder: .joshix/tasks/claude-coordinator-flow/
Read helper: $ROOT/skills/task-context/scripts/task-context.mjs
Gate: plan
Round: 1
Review target: workflow-policy.md
Diff/log evidence: none
Focused verification: oracle-only checks passed

Read current.md and query task history as needed. Return an approved review
with no findings as JSON matching the supplied schema. Never append task
history or edit repository files.
EOF

set +e
"$LAUNCHER" review \
  --provider codex \
  --repo-root "$TEST_PROJECT" \
  --prompt-file "$TEST_PROJECT/review-prompt.md" \
  --result-schema review-result-v1 \
  --timeout-ms 120000 \
  --max-events 500 \
  --max-output-bytes 524288 \
  --max-review-bytes 65536 > "$TEST_PROJECT/review-envelope.json"
CODEX_REVIEW_EXIT=$?
set -e
if [ "$CODEX_REVIEW_EXIT" -eq 0 ]; then
  if ! jq -e '.ok == true and .provider == "codex" and .session.mode == "started" and .review.status == "approved" and (.review.findings | length) == 0' \
    "$TEST_PROJECT/review-envelope.json" >/dev/null; then
    echo 'FAIL: real Codex reviewer returned an invalid start envelope'
    cat "$TEST_PROJECT/review-envelope.json"
    exit 1
  fi
  SESSION_ID="$(jq -r '.session.id' "$TEST_PROJECT/review-envelope.json")"
  cat > "$TEST_PROJECT/resume-review-prompt.md" <<EOF
Continue as the persistent reviewer peer for .joshix/tasks/claude-coordinator-flow/.
Gate: whole-change
Round: 1
Review target: workflow-policy.md
Diff/log evidence: none
Focused verification: oracle-only checks passed

Attempt to create the repository file SHOULD_NOT_EXIST. The resumed read-only
sandbox must deny that write. After the denial, return an approved review with
no findings as JSON matching the supplied schema. Never append task history.
EOF
  if ! "$LAUNCHER" review \
    --provider codex \
    --repo-root "$TEST_PROJECT" \
    --prompt-file "$TEST_PROJECT/resume-review-prompt.md" \
    --result-schema review-result-v1 \
    --timeout-ms 120000 \
    --max-events 500 \
    --max-output-bytes 524288 \
    --max-review-bytes 65536 \
    --session-id "$SESSION_ID" > "$TEST_PROJECT/resume-review-envelope.json"; then
    echo 'FAIL: real Codex reviewer did not complete its resumed read-only turn'
    cat "$TEST_PROJECT/resume-review-envelope.json"
    exit 1
  fi
  if ! jq -e --arg session "$SESSION_ID" \
    '.ok == true and .provider == "codex" and .session.id == $session and .session.mode == "resumed" and .review.status == "approved"' \
    "$TEST_PROJECT/resume-review-envelope.json" >/dev/null; then
    echo 'FAIL: real Codex reviewer returned an invalid resume envelope'
    cat "$TEST_PROJECT/resume-review-envelope.json"
    exit 1
  fi
  [ ! -e "$TEST_PROJECT/SHOULD_NOT_EXIST" ] || { echo 'FAIL: real Codex reviewer crossed read-only boundary'; exit 1; }
  (
    cd "$TEST_PROJECT"
    node "$ROOT/skills/task-context/scripts/task-context.mjs" recent .joshix/tasks/claude-coordinator-flow --full
  ) | jq -e '[.[] | select(.speaker == "Reviewer")] | length == 1' >/dev/null \
    || { echo 'FAIL: real Codex reviewer wrote coordinator history'; exit 1; }
elif jq -e '.failure.kind == "unavailable"' "$TEST_PROJECT/review-envelope.json" >/dev/null 2>&1; then
  echo '  [SKIP] No compatible Codex CLI is discoverable; fake transport and oracle coverage remain active'
else
  echo 'FAIL: discovered Codex reviewer path failed'
  cat "$TEST_PROJECT/review-envelope.json"
  exit 1
fi
echo 'STATUS: PASSED'
