#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONTRACT="$ROOT/skills/using-joshix/references/autonomous-review.md"
SCHEMA="$ROOT/skills/requesting-code-review/review-result.schema.json"
RECORD="$ROOT/skills/requesting-code-review/review-record.schema.json"
FAILURE_RECORD="$ROOT/skills/requesting-code-review/review-failure-record.schema.json"
RUNNER="$ROOT/skills/requesting-code-review/scripts/reviewer-runner.mjs"
FLOW_FIXTURE="$ROOT/tests/autonomous-review/autonomous-review-flow.test.mjs"
LIVE_SMOKE="$ROOT/tests/reviewer-host/real-codex-claude-smoke.mjs"
INSTALLER="$ROOT/skills/requesting-code-review/scripts/install-reviewer-host.mjs"
LAUNCHER="$ROOT/skills/requesting-code-review/scripts/reviewer-host-launcher.mjs"
PRODUCER="$ROOT/skills/using-joshix/references/review-producer-contract.md"
RECEPTION="$ROOT/skills/using-joshix/references/review-reception-contract.md"
REQUESTING="$ROOT/skills/requesting-code-review/SKILL.md"
SUBAGENT="$ROOT/skills/subagent-driven-development/SKILL.md"
DISPATCHING="$ROOT/skills/dispatching-parallel-agents/SKILL.md"
EXECUTING="$ROOT/skills/executing-plans/SKILL.md"
VERIFICATION="$ROOT/skills/verification-before-completion/SKILL.md"
README="$ROOT/README.md"
TESTING="$ROOT/docs/testing.md"

ACTIVE=(
  "$CONTRACT" "$SCHEMA" "$INSTALLER" "$LAUNCHER" "$PRODUCER" "$RECEPTION"
  "$REQUESTING" "$SUBAGENT" "$DISPATCHING" "$EXECUTING"
  "$VERIFICATION"
)

all_text() {
  for file in "$@"; do [ -f "$file" ] && cat "$file"; done
}
require_collective() {
  local text="$1" label="$2"
  all_text "${ACTIVE[@]}" | tr '\n\r\t' '   ' | tr -s ' ' | grep -F -- "$text" >/dev/null \
    || { printf 'FAIL: %s\nMissing: %s\n' "$label" "$text"; exit 1; }
}
reject_collective() {
  local text="$1" label="$2"
  ! all_text "${ACTIVE[@]}" | grep -F -- "$text" >/dev/null \
    || { printf 'FAIL: %s\nUnexpected: %s\n' "$label" "$text"; exit 1; }
}
require_fixed() {
  local file="$1" text="$2" label="$3"
  grep -Fq -- "$text" "$file" \
    || { printf 'FAIL: %s\nMissing: %s\n' "$label" "$text"; exit 1; }
}
require_exact_count() {
  local file="$1" text="$2" expected="$3" label="$4"
  local actual
  actual="$({ grep -Fo -- "$text" "$file" || true; } | wc -l | tr -d '[:space:]')"
  [ "$actual" -eq "$expected" ] \
    || { printf 'FAIL: %s (expected %s, found %s)\n' "$label" "$expected" "$actual"; exit 1; }
}

CANONICAL='Challenge assumptions in the spec, plan, and implementation when they create concrete risk; do not treat prior approval as proof of correctness. Read the shared chat and review'
require_exact_count "$CONTRACT" "$CANONICAL" 1 'autonomous review keeps the exact instruction once'
require_collective 'OpenAI and Anthropic' 'provider authorization remains fixed in joshix'
require_collective 'fresh reviewer' 'every review pass starts without provider session state'
require_collective 'ordinary SQLite message' 'the review result is normal task history'
require_collective 'one provider attempt' 'the bridge invokes exactly once'
require_collective 'repeats a rebutted disagreement without new evidence' 'semantic repetition stops the loop'
require_collective 'same concrete defect is materially unchanged' 'lack of measurable progress stops the loop'
require_collective 'owner decision' 'owner-gated changes stop the loop'
require_collective 'shell: false' 'provider and Git invocations forbid shell interpolation'
require_collective 'ignore-user-config' 'Codex review ignores unrelated ambient tools and configuration'
require_collective 'ephemeral' 'Codex review does not persist provider sessions'
require_collective 'read-only' 'reviewers are read-only'
require_collective 'joshix-review review' 'coordinator uses the installed bridge'
require_collective 'Cancellation' 'explicit cancellation has a first-class branch'
require_collective 'starts no retry or fallback' 'cancellation never relaunches review'
require_collective '512 KiB' 'completed review size is bounded after provider exit'
require_collective '16 KiB' 'diagnostics retain only a rolling tail'

for removed in \
  'correction rounds' \
  'recovery repairs' \
  'producer and recovery budgets' \
  'pass cap' \
  'session-unavailable' \
  'started, resumed, or replaced' \
  'requestedProviderDiagnostic' \
  'promptDigest' \
  'ReviewerTransport' \
  'configuration-stale' \
  'max-events' \
  'max-output-bytes' \
  'timeout-ms'
do
  reject_collective "$removed" "removed review-engine concept: $removed"
done

test ! -e "$RECORD" || { echo 'FAIL: review record envelope still exists'; exit 1; }
test ! -e "$FAILURE_RECORD" || { echo 'FAIL: failure record envelope still exists'; exit 1; }
test ! -e "$RUNNER" || { echo 'FAIL: standalone reviewer runner still exists'; exit 1; }
test ! -e "$FLOW_FIXTURE" || { echo 'FAIL: self-referential autonomous flow fixture still exists'; exit 1; }
! grep -Fq 'timeout:' "$LIVE_SMOKE" \
  || { echo 'FAIL: live review smoke still imposes a caller deadline'; exit 1; }

node --input-type=module - "$SCHEMA" "$ROOT/skills/requesting-code-review/scripts/reviewer-host-launcher.mjs" <<'NODE'
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
const schema = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const launcher = process.argv[3];
process.argv[1] = process.argv[2];
const { REVIEW_SCHEMA } = await import(pathToFileURL(launcher).href);
const finding = schema.properties.findings.items;
const exact = (actual, expected) => JSON.stringify([...actual].sort()) === JSON.stringify([...expected].sort());
if (!exact(schema.required, ['status', 'findings'])) throw new Error('root required keys are not exact');
if (!exact(Object.keys(schema.properties), ['status', 'findings'])) throw new Error('root properties are not exact');
if (!exact(finding.required, ['title', 'severity', 'evidence', 'recommendation'])) throw new Error('finding required keys are not exact');
if (!exact(Object.keys(finding.properties), ['title', 'severity', 'evidence', 'recommendation'])) throw new Error('finding properties are not exact');
if (JSON.stringify(schema) !== JSON.stringify(REVIEW_SCHEMA)) {
  throw new Error('review-result.schema.json and the bridge review schema have drifted');
}
NODE

require_fixed "$README" 'install-reviewer-host.mjs' 'README keeps reviewer bridge setup'
require_fixed "$TESTING" 'tests/reviewer-host/real-codex-claude-smoke.mjs' 'testing docs keep the real sandbox smoke'

echo 'STATUS: PASSED'
