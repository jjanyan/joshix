#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
TEST_PROJECT="$(create_test_project)"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT
init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

cat > "$TEST_PROJECT/history.md" <<'EOF'
1. Reviewer suggested an automatic minimum-client-build gate for exports.
2. Owner: this is a pre-launch, single-operator deployment. I will pause the
   old client and install the matching build. Keep that manual procedure;
   automatic old-client blocking is outside this task.
3. Reviewer accepted that decision and found failed exports were being lost.
4. Coordinator changed export failure handling to retry the same batch.
EOF
cat > "$TEST_PROJECT/spec.md" <<'EOF'
# Export retry spec, corrected after review
The single operator pauses the old client during deployment and installs the
matching build. No automatic minimum-client-build gate is added.
The latest correction retries a failed export batch with a new request ID.
The existing receiver appends all received rows before acknowledging the batch.
If the acknowledgement is lost, the sender sees a failure and retries.
The required outcome is that every source row appears exactly once in the export.
EOF
cat > "$TEST_PROJECT/changed-assumption.md" <<'EOF'
# Second independent spec fixture
Same prior owner decision: the only producer is the operator's paused client.
The latest correction adds scheduled background uploads from old installed
clients, which continue during the operator's pause. Old clients send the
retired row shape, and the new receiver cannot decode that shape.
The rollout still relies exclusively on the operator pausing the foreground app.
EOF
cat > "$TEST_PROJECT/quote.mjs" <<'EOF'
// Changed in this task. Each item has unitPrice and quantity.
// Latest correction: a missing tax rate now defaults to zero.
export function quote(items, taxRate = 0) {
  const subtotal = items.reduce((sum, item) => sum + item.unitPrice, 0);
  return subtotal * (1 + taxRate);
}
EOF

read -r -d '' PROMPT <<'EOF' || true
You are a delegated review producer. Do not initialize or access shared task
context. The supplied prior reasoning is history.md. Do not edit any files.
Read the repository's review-producer and autonomous-review guidance through
.agents/skills/using-joshix/references/, then evaluate these separate artifacts:
1. A spec follow-up: spec.md, with history.md as its prior decisions/review.
2. Another spec follow-up: changed-assumption.md, with the owner decision
   recorded in that file. This is an independent scenario, not another edit to case 1.
3. A code follow-up: quote.mjs. The approved requirement is sum(unitPrice *
   quantity), then tax. The previous review found only the missing-tax-rate
   default. The entire function is part of the task's changed code.
Return one JSON object with keys specFollowup, changedAssumption, and codeFollowup.
Each value is an array of actual findings with title, evidence, recommendation.
Use an empty array when no findings remain. Do not include rejected suggestions
or a narration of every possible finding in the arrays.
EOF
run_codex "$TEST_PROJECT" "$PROMPT" "$TEST_PROJECT/output" read-only

node --input-type=module - "$TEST_PROJECT/output/final.md" <<'NODE'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const text = fs.readFileSync(process.argv[2], 'utf8');
const result = JSON.parse(text.replace(/^```(?:json)?\s*|\s*```$/g, '').trim());
const words = (findings) => findings.map((f) => `${f.title} ${f.evidence} ${f.recommendation}`).join(' ');
assert(result.specFollowup.length > 0);
assert.match(words(result.specFollowup), /duplicat|exactly.once/i);
assert.doesNotMatch(words(result.specFollowup), /minimum|build.gat|client.version|block.*client|reject.*client/i);
assert.match(words(result.changedAssumption), /background|scheduled/i);
assert.match(words(result.changedAssumption), /paus|prior|owner|assum/i);
assert.match(words(result.codeFollowup), /quantity|quantities|unitPrice\s*\*/i);
console.log('STATUS: PASSED');
NODE
