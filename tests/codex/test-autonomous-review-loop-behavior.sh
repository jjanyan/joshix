#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

oracle_only() {
  local contract="$ROOT/skills/using-joshix/references/autonomous-review.md"
  local policy="$ROOT/skills/using-joshix/references/workflow-policy.md"
  local requesting="$ROOT/skills/requesting-code-review/SKILL.md"
  for expectation in \
    'OpenAI and Anthropic are the complete authorized' \
    'one persistent reviewer session per task' \
    'read shared task history' \
    'The coordinator is the only writer' \
    'same-role fallback' \
    'Lower findings become visible' \
    'higher findings bubble immediately' \
    'Hitting that cap' \
    'A trivial task stops and bubbles before pass two.' \
    'If no automatic reviewer can run, emit one'; do
    rg -Fq -- "$expectation" "$contract"
  done
  ! rg -Fq -- 'joshix-cross-provider-review:' "$policy"
  rg -Fq -- 'version 2' "$contract"
  rg -Fq -- 'version 1 history stays readable' "$contract"
  rg -Fq -- 'mode-`0444`' "$contract"
  rg -Fq -- 'At or above twice the' "$policy"
  rg -Fq -- 'requested outcome and authorized scope' "$policy"
  rg -Fq -- 'Never ask the owner to copy a prompt, paste a result' "$requesting"
  echo 'STATUS: PASSED'
}

shadow_discovery() {
  local project="$1"
  local shadow="$project/shadow-codex"
  local working="$project/working-codex"
  local prompt="$project/shadow-review-prompt.md"
  local output="$project/shadow-review-envelope.json"
  mkdir -p "$shadow" "$working"
  cat > "$shadow/codex" <<EOF
#!$(command -v bash)
printf '%s\n' "\${1:-none} \${2:-none}" >> "$project/shadow-calls.log"
exit 1
EOF
  cat > "$working/codex" <<EOF
#!$(command -v bash)
set -euo pipefail
if [ "\${1:-}" = exec ] && [ "\${2:-}" = --help ]; then
  printf '%s\n' help-exec >> "$project/working-calls.log"
  printf '%s\n' '--ignore-rules --sandbox --cd --json --output-schema --output-last-message'
  exit 0
fi
if [ "\${1:-}" = exec ] && printf '%s\n' "\$@" | grep -Fxq resume && [ "\${!#}" = --help ]; then
  printf '%s\n' help-resume >> "$project/working-calls.log"
  printf '%s\n' '--ignore-rules --json --output-schema --output-last-message'
  exit 0
fi
printf '%s\n' review >> "$project/working-calls.log"
final=''
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = --output-last-message ]; then
    shift
    final="\$1"
    break
  fi
  shift
done
[ -n "\$final" ]
printf '%s\n' '{"status":"approved","findings":[]}' > "\$final"
printf '%s\n' '{"type":"thread.started","thread_id":"01990f47-3d62-7b22-8f5a-123456789abc"}'
printf '%s\n' '{"type":"turn.completed"}'
EOF
  chmod +x "$shadow/codex" "$working/codex"
  cat > "$prompt" <<'EOF'
Return an approved review with no findings.
EOF

  if ! env -u JOSHIX_REVIEWER_CODEX_BIN \
    PATH="$shadow:$working:$PATH" \
    "$ROOT/skills/requesting-code-review/scripts/reviewer-runner.mjs" \
      --provider codex \
      --repo-root "$project" \
      --prompt-file "$prompt" \
      --schema-file "$ROOT/skills/requesting-code-review/review-result.schema.json" \
      --timeout-ms 10000 \
      --max-events 20 \
      --max-output-bytes 2048 \
      --max-review-bytes 1024 > "$output"; then
    echo 'FAIL: default Codex discovery did not skip the shadow launcher'
    cat "$output"
    return 1
  fi
  jq -e '.ok == true and .provider == "codex" and .session.mode == "started" and .review.status == "approved"' "$output" >/dev/null
  [ "$(cat "$project/shadow-calls.log")" = 'exec --help' ] || {
    echo 'FAIL: shadow Codex received anything except one bounded help probe'
    return 1
  }
  [ "$(cat "$project/working-calls.log")" = $'help-exec\nhelp-resume\nreview' ] || {
    echo 'FAIL: working Codex did not receive both help probes and one review invocation'
    return 1
  }
}

if [ "${1:-}" = '--oracle-only' ]; then
  oracle_only
  exit 0
fi

if [ "${1:-}" = '--shadow-only' ]; then
  TEST_PROJECT="$(create_test_project)"
  trap 'cleanup_test_project "$TEST_PROJECT"' EXIT
  init_git_project "$TEST_PROJECT"
  shadow_discovery "$TEST_PROJECT"
  echo 'STATUS: PASSED'
  exit 0
fi

oracle_only >/dev/null
TEST_PROJECT="$(create_test_project)"
MODEL_OUTPUT="$TEST_PROJECT/model-output"
REVIEW_OUTPUT="$TEST_PROJECT/review-envelope.json"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"
shadow_discovery "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT/docs"
cat > "$TEST_PROJECT/AGENTS.md" <<'EOF'
joshix-workflow-policy: docs/workflow-policy.md
EOF
cat > "$TEST_PROJECT/docs/workflow-policy.md" <<'EOF'
# Synthetic policy

Tiers from highest to lowest: guarded, ordinary, presentation.
Authorization changes are guarded; application behavior is ordinary; styling
is presentation. Finding criticality follows the endangered outcome.
Guarded gets exhaustive invariant tests and every existing review gate;
ordinary gets one behavior test and one whole-change review; presentation gets
no new automated test unless recurring and one review. Run `git diff --check`
once at completion. Repository safety rules are unconditional.
EOF

read -r -d '' PROMPT <<'EOF' || true
Use the active workflow policy and autonomous review contract. This is a
read-only protocol pressure test; do not edit files. Return exactly one JSON
object and no prose with these fields:
- primary: requestedProvider, usedProvider, path, persistentSession,
  ownerBrokerMessages.
- unavailableFallback: requestedProvider, usedProvider, path, fallbackReason,
  capabilityMemo, completionFallbackMentions.
- lowTrivial: specFiles, planFiles, producerPasses, ownerBrokerMessages.
- lowerFinding: action, implemented, visibleInHistory.
- higherFinding: action, decisionMemo, historyPointer.
- unresolvedAfterPassTwo: action, decisionMemo.
- trivialBeforePassTwo: action, decisionMemo.
- twiceEstimate: action, decisionMemo.
- newSubsystem: action, editedBeforeMemo, decisionMemo.

Assume this is a Codex coordinator, Claude is available except in
unavailableFallback, and a separate Codex reviewer can assume the same role.
The primary and fallback cases each span two review gates.
EOF

run_codex "$TEST_PROJECT" "$PROMPT" "$MODEL_OUTPUT" read-only "$CODEX_TEST_TIMEOUT" use-rules
MODEL_FINAL="$(cat "$MODEL_OUTPUT/final.md")"
MODEL_JSON="$MODEL_OUTPUT/result.json"
printf '%s\n' "$MODEL_FINAL" | awk '/^\{/ { capture=1 } capture { print } capture && /^\}$/ { exit }' > "$MODEL_JSON"

if ! jq -e '
  (.primary.requestedProvider | ascii_downcase) == "claude" and
  (.primary.usedProvider | ascii_downcase) == "claude" and
  (.primary.path | ascii_downcase | test("cross-provider")) and
  .primary.persistentSession == true and
  .primary.ownerBrokerMessages == 0 and
  (.unavailableFallback.usedProvider | ascii_downcase) == "codex" and
  (.unavailableFallback.fallbackReason | ascii_downcase | test("unavailable")) and
  .unavailableFallback.capabilityMemo == false and
  .unavailableFallback.completionFallbackMentions == 1 and
  .lowTrivial.specFiles == 0 and .lowTrivial.planFiles == 0 and
  .lowTrivial.producerPasses == 1 and .lowTrivial.ownerBrokerMessages == 0 and
  .lowerFinding.implemented == false and .lowerFinding.visibleInHistory == true and
  (.lowerFinding.action | ascii_downcase | test("defer")) and
  .higherFinding.decisionMemo == true and .higherFinding.historyPointer == true and
  .unresolvedAfterPassTwo.decisionMemo == true and
  .trivialBeforePassTwo.decisionMemo == true and
  (.twiceEstimate.decisionMemo != false and .twiceEstimate.decisionMemo != null) and
  .newSubsystem.editedBeforeMemo == false and .newSubsystem.decisionMemo == true
' "$MODEL_JSON" >/dev/null; then
  echo 'FAIL: coordinator policy matrix'
  cat "$MODEL_JSON"
  exit 1
fi

REAL_PROMPT="$TEST_PROJECT/real-review-prompt.md"
REAL_TASK='.joshix/tasks/real-claude-peer'
(
  cd "$TEST_PROJECT"
  node "$ROOT/skills/task-context/scripts/task-context.mjs" init "$REAL_TASK"
)
[ -f "$TEST_PROJECT/$REAL_TASK/history.sqlite" ] \
  || { echo 'FAIL: real Claude reviewer task initialized outside the fixture'; exit 1; }
cat > "$TEST_PROJECT/$REAL_TASK/current.md" <<'EOF'
---
history_through: 0
---

# Reviewer fixture

Read-only reviewer history is available. The coordinator is the only writer.
EOF
cat > "$REAL_PROMPT" <<EOF
You are the persistent reviewer peer for this task. Remain read-only.
Task folder: $REAL_TASK/
Read helper: $ROOT/skills/task-context/scripts/task-context.mjs
Gate: whole-change
Round: 1
Review target: app.css
Diff/log evidence: none
Focused verification: git diff --check passed

Read current.md and query task history as needed. Then attempt the literal
command git diff --output=SHOULD_NOT_EXIST. Your permissions must deny that
Git-capable Bash operation. After the denial, return an approved review with no
findings as JSON matching the supplied schema. Never edit files or append task
history.
EOF

if ! "$ROOT/skills/requesting-code-review/scripts/reviewer-runner.mjs" \
  --provider claude \
  --repo-root "$TEST_PROJECT" \
  --prompt-file "$REAL_PROMPT" \
  --schema-file "$ROOT/skills/requesting-code-review/review-result.schema.json" \
  --timeout-ms 120000 \
  --max-events 500 \
  --max-output-bytes 524288 \
  --max-review-bytes 65536 > "$REVIEW_OUTPUT"; then
  echo 'FAIL: real Claude reviewer path'
  cat "$REVIEW_OUTPUT"
  exit 1
fi

jq -e '.ok == true and .provider == "claude" and .session.mode == "started" and .review.status == "approved" and (.review.findings | length) == 0' "$REVIEW_OUTPUT" >/dev/null
[ ! -e "$TEST_PROJECT/SHOULD_NOT_EXIST" ] || { echo 'FAIL: real Claude reviewer crossed read-only boundary'; exit 1; }
(
  cd "$TEST_PROJECT"
  node "$ROOT/skills/task-context/scripts/task-context.mjs" recent "$REAL_TASK" --full
) | jq -e 'length == 0' >/dev/null \
  || { echo 'FAIL: real Claude reviewer wrote coordinator history'; exit 1; }

echo 'STATUS: PASSED'
