#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONTRACT="$ROOT/skills/using-joshix/references/autonomous-review.md"
SCHEMA="$ROOT/skills/requesting-code-review/review-result.schema.json"
RECORD="$ROOT/skills/requesting-code-review/review-record.schema.json"
RUNNER="$ROOT/skills/requesting-code-review/scripts/reviewer-runner.mjs"
PRODUCER="$ROOT/skills/using-joshix/references/review-producer-contract.md"
RECEPTION="$ROOT/skills/using-joshix/references/review-reception-contract.md"
REQUESTING="$ROOT/skills/requesting-code-review/SKILL.md"
SUBAGENT="$ROOT/skills/subagent-driven-development/SKILL.md"
DISPATCHING="$ROOT/skills/dispatching-parallel-agents/SKILL.md"
EXECUTING="$ROOT/skills/executing-plans/SKILL.md"
BOOTSTRAP="$ROOT/skills/using-joshix/SKILL.md"

all_text() {
  for file in "$@"; do [ -f "$file" ] && cat "$file"; done
}
require_collective() {
  local text="$1" label="$2"
  all_text "$CONTRACT" "$SCHEMA" "$RECORD" "$RUNNER" "$PRODUCER" "$RECEPTION" "$REQUESTING" "$SUBAGENT" "$DISPATCHING" "$EXECUTING" \
    | tr '\n\r\t' '   ' | tr -s ' ' | grep -Fq "$text" \
    || { printf 'FAIL: %s\nMissing: %s\n' "$label" "$text"; exit 1; }
}
reject_fixed() {
  local file="$1" text="$2" label="$3"
  [ -f "$file" ] || return 0
  ! grep -Fq -- "$text" "$file" \
    || { printf 'FAIL: %s\nUnexpected: %s\n' "$label" "$text"; exit 1; }
}

require_collective 'OpenAI and Anthropic' 'provider authorization is fixed in joshix'
require_collective 'one persistent reviewer session per task' 'reviewer continuity is task-scoped'
require_collective 'persistent reviewer peer' 'automatic reviewer role is explicit'
require_collective 'read shared task history' 'reviewer receives shared reasoning directly'
require_collective 'coordinator is the only writer' 'task state keeps one writer'
require_collective 'shell: false' 'runner forbids shell interpolation'
require_collective 'read-only' 'reviewers are read-only'
require_collective 'delegated producer' 'delegated role is explicit'
require_collective 'at most two producer passes' 'review cap is explicit'
require_collective 'trivial task' 'trivial second-pass alarm is explicit'
require_collective 'idempotency key' 'review append is idempotent'
require_collective 'one JSON object only, with no timestamp, Markdown fence, heading, or prose' 'review history payload is directly machine-parseable'
require_collective 'sha256(task-identity + "\0" + gate + "\0" + round + "\0" + reviewer-path + "\0" + promptDigest)' 'idempotency formula is canonical'
require_collective 'same-role' 'fallback assumes the unavailable reviewer role'
require_collective 'capability decision memo' 'missing capability bubbles once'
require_collective 'tier-defined review rigor is authoritative' 'active policy controls review gates'
require_collective 'Do not start full completion verification before review' 'inline execution waits for review sign-off'
require_collective 'Do not probe the unavailable provider again during the task.' 'failed cross-provider path stays disabled'
require_collective 'quality gate alone' 'quality-only tier does not require spec review'
require_collective 'coordinator configuration failure' 'pre-spawn errors are not reviewer failures'
require_collective 'internal runner failure' 'internal runner failures stay local'
require_collective 'Personal provider configuration supplies reviewer model and reasoning-effort defaults.' 'reviewers inherit machine-specific model defaults'
require_collective '"schemaVersion": {"const": 2}' 'review records use the persistent-session schema'
require_collective '"mode": {"enum": ["started", "resumed", "replaced"]}' 'review records preserve session transitions'
require_collective 'version 1' 'legacy review records remain readable'
require_collective 'You are the persistent reviewer peer for this task. Remain read-only.' 'review prompt declares the persistent role'
require_collective 'Diff/log evidence:' 'review prompt identifies bounded evidence'
require_collective 'Review: `<gate>; round <n>; <path>; <provider> session <uuid>; history <id>`' 'snapshot keeps the current reviewer identity'
reject_fixed "$BOOTSTRAP" '--allowedTools' 'bootstrap does not embed Claude commands'
reject_fixed "$BOOTSTRAP" '--sandbox read-only' 'bootstrap does not embed Codex commands'
reject_fixed "$RUNNER" 'task-context.mjs append' 'runner never appends task history'
reject_fixed "$RUNNER" 'current.md' 'runner never writes snapshots'
reject_fixed "$RUNNER" 'Bash(git diff:' 'Claude cannot invoke git diff through Bash'
reject_fixed "$RUNNER" 'Bash(git log:' 'Claude cannot invoke git log through Bash'
reject_fixed "$RUNNER" "'--ignore-user-config'" 'Codex reviewer does not suppress personal defaults'
reject_fixed "$RUNNER" "'--ephemeral'" 'Codex reviewer sessions persist'
reject_fixed "$RUNNER" "'--no-session-persistence'" 'Claude reviewer sessions persist'
reject_fixed "$RECORD" '"isolation"' 'task-history access is not a fallback failure'
reject_fixed "$CONTRACT" 'joshix-cross-provider-review: allow' 'review no longer requires repo opt-in'
reject_fixed "$CONTRACT" 'self-contained delegated producer prompt' 'persistent peer reads shared context'
require_collective 'bounded diff/log scratch file' 'Claude receives current Git evidence without Bash'
require_collective 'resumed Codex reviewer remains read-only' 'personal config cannot widen the resumed sandbox'

echo 'STATUS: PASSED'
