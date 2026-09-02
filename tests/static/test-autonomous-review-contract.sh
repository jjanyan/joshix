#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONTRACT="$ROOT/skills/using-joshix/references/autonomous-review.md"
SCHEMA="$ROOT/skills/requesting-code-review/review-result.schema.json"
RECORD="$ROOT/skills/requesting-code-review/review-record.schema.json"
RUNNER="$ROOT/skills/requesting-code-review/scripts/reviewer-runner.mjs"
INSTALLER="$ROOT/skills/requesting-code-review/scripts/install-reviewer-host.mjs"
LAUNCHER="$ROOT/skills/requesting-code-review/scripts/reviewer-host-launcher.mjs"
PRODUCER="$ROOT/skills/using-joshix/references/review-producer-contract.md"
RECEPTION="$ROOT/skills/using-joshix/references/review-reception-contract.md"
REQUESTING="$ROOT/skills/requesting-code-review/SKILL.md"
SUBAGENT="$ROOT/skills/subagent-driven-development/SKILL.md"
DISPATCHING="$ROOT/skills/dispatching-parallel-agents/SKILL.md"
EXECUTING="$ROOT/skills/executing-plans/SKILL.md"
BOOTSTRAP="$ROOT/skills/using-joshix/SKILL.md"
README="$ROOT/README.md"
TESTING="$ROOT/docs/testing.md"

all_text() {
  for file in "$@"; do [ -f "$file" ] && cat "$file"; done
}
require_collective() {
  local text="$1" label="$2"
  all_text "$CONTRACT" "$SCHEMA" "$RECORD" "$RUNNER" "$INSTALLER" "$LAUNCHER" "$PRODUCER" "$RECEPTION" "$REQUESTING" "$SUBAGENT" "$DISPATCHING" "$EXECUTING" \
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
require_collective '| Event | Producer pass | Recovery repair | Review required |' 'one central pass and recovery table exists'
require_collective 'Transport retry/session replacement/fallback' 'transport attempts do not consume producer passes'
require_collective 'Mechanical stale expectation meeting all four conditions' 'mechanical stale repairs are distinct from producer passes'
require_collective 'Zero-diagnostic infrastructure retry' 'infrastructure retry is distinct from producer passes'
require_collective 'Production/invariant/behavior recovery' 'production recovery consumes the remaining producer pass'
require_collective 'no production code changes' 'mechanical repair cannot change production code'
require_collective 'no assertion is weakened' 'mechanical repair cannot weaken assertions'
require_collective 'no invariant or user-visible behavior changes' 'mechanical repair cannot change behavior'
require_collective 'coverage is not reduced' 'mechanical repair cannot reduce coverage'
require_collective 'failure occurred before workload start' 'infrastructure retry must precede workload start'
require_collective 'emitted no product or test diagnostic' 'infrastructure retry requires zero diagnostics'
require_collective 'repository is unchanged since sign-off' 'infrastructure retry preserves reviewed state'
require_collective 'focused health check' 'infrastructure retry requires positive evidence'
require_collective 'two recovery repairs total' 'automatic recovery is globally bounded'
require_collective 'gate budget never resets after sign-off' 'sign-off does not reset review budget'
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
require_collective 'Provider-reported runtime metadata is diagnostic-only' 'effective reviewer settings are recorded without trusting reviewer prose'
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
require_collective 'joshix-review review' 'coordinator uses the typed host launcher'
require_collective 'configuration-stale' 'stale host configuration is distinct'
require_collective '`configuration-stale` is recorded once, then starts a persistent same-role' 'stale configuration falls back once'
require_collective 'fallback and produces one completion notice' 'stale configuration produces one notice'
reject_fixed "$CONTRACT" 'persistent rule for Node' 'contract forbids a broad Node allow rule'
reject_fixed "$RECEPTION" 'Make one bounded recovery pass for that failure' 'artifact reception does not duplicate completion recovery policy'
reject_fixed "$RECEPTION" 'Across one review application, Agent 1 may make at most two recovery passes' 'artifact reception does not own the recovery ceiling'
grep -Fq -- 'install-reviewer-host.mjs' "$README" \
  || { echo 'FAIL: README omits reviewer-host setup'; exit 1; }
grep -Fq -- 'Bash(<absolute-launcher> review:*)' "$README" \
  || { echo 'FAIL: README omits exact Claude launcher permission'; exit 1; }
grep -Fq -- 'https://developers.openai.com/codex/rules' "$README" \
  || { echo 'FAIL: README omits official Codex rules reference'; exit 1; }
grep -Fq -- 'tests/reviewer-host/real-codex-claude-smoke.mjs' "$TESTING" \
  || { echo 'FAIL: testing docs omit real sandbox smoke'; exit 1; }

echo 'STATUS: PASSED'
