#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
TEST_PROJECT="$(create_test_project)"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT
init_git_project "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT/.agents"
ln -s "${JOSHIX_TEST_SKILLS_DIR:-$CODEX_REPO_ROOT/skills}" "$TEST_PROJECT/.agents/skills"
read -r -d '' PROMPT <<'EOF' || true
Read .agents/skills/using-joshix/references/progress-dag.md and the writing-plans
and reviewing-plans skills. This is a read-only policy fixture, not a live task.
Do not access shared task context, render a real visual, or call a reviewer.
Classify these independent simulated clients at a meaningful DAG transition:
A. Native interactive output is exposed and supported in commentary, but a
   generic visualization skill says final-only and no progress updates.
B. The same model runs in a terminal with no artifact or native visualization.
C. Native rendering was attempted and failed on this surface.
D. The client itself supports native output only in final responses; work is
   still running and a commentary update is due.
E. Client D now reaches a final planning handoff; native output is available.

Also classify: a user clicks a node; a short settled one-node implementation
plan has no repository advance-review requirement; a required plan review has
an unverified edge and two writers of the same file; and a proposed adjustment
to an opposing-reviewer-approved graph is waiting for approval.

For display defaults, classify these snapshots using the contract (return
"unspecified" when it supplies no rule):
- New snapshot: T9 completed first, T2 completed most recently, T4 active,
  T7 todo. Prior snapshot saved manual selection T9.
- Same snapshot: the user deliberately selected T9 after it opened.
- No completed nodes: T4 active, T7 todo.
- No active nodes: T9 completed first, T2 completed most recently, T7 todo.
- Multiple active nodes: plan order is T8, T4, T7; T8 and T4 are active,
  T7 is done. There is no saved selection for this snapshot.
Report semantic colors for both renderers and whether selecting a node may
replace or obscure its status color. Do not infer completion order from IDs.

For compact node details, apply the contract to these four independent states
of node B2, titled "B2 · API checks · <status>". The graph already shows B1 -> B2.
Owner/scope: API verifier, isolated test database. Objective and completion
criterion both say: "Permissions and persistence checks pass."
- active: permission cases passed; persistence cases running. No blocker or
  completion artifact yet.
- blocked: test account unavailable; restore access to run the suite. No result.
- done: all 12 checks passed. The supplied evidence artifact is
  /results/api-checks.txt.
- todo: waiting for B1. No work, blocker beyond prerequisites, or evidence yet.
Return the visible detail rows for each state, excluding the already displayed
title. Use the contract's row labels when specified, otherwise descriptive
labels. Include an evidence link only when one is supplied. Also describe how
native selection exposes prerequisites, including for screen-reader users,
and which compact details belong beside a static Mermaid graph. If the contract
does not specify a behavior, report that instead of inventing a rule.

Return only JSON:
{
  "renderers": {"A":"native|mermaid", "B":"native|mermaid", "C":"native|mermaid", "D":"native|mermaid", "E":"native|mermaid"},
  "click": {"allowed":[], "forbidden":[]},
  "simplePlan": {"nodeCount":1, "advanceIndependentReview":true|false},
  "reviewChecks":[],
  "pendingAdjustment": {"mayExecuteAffected":true|false, "displayAs":"proposed|approved"},
  "displayTruth": {"claimLive":true|false, "endTurnToRefresh":true|false, "sourceOfState":"..."},
  "selection": {"newSnapshot":"...", "sameSnapshot":"...", "noCompleted":"...", "noActive":"...", "multipleActive":"..."},
  "statusColors": {"native":{"done":"...","active":"...","todo":"...","blocked":"..."}, "mermaid":{"done":"...","active":"...","todo":"...","blocked":"..."}},
  "selectionMayObscureStatusColor":true|false,
  "cards": {"active":[{"label":"...","value":"..."}], "blocked":[], "done":[], "todo":[]},
  "prerequisiteInspection": {"highlightsIncomingEdges":true|false, "highlightsPredecessors":true|false, "accessibleDescription":"..."},
  "mermaidDetails":"..."
}
Use the supported renderer names literally. Use short descriptive phrases in
arrays; do not copy the schema's alternative values into your answer.
For selection values, return only the chosen node ID.
EOF
run_codex "$TEST_PROJECT" "$PROMPT" "$TEST_PROJECT/output" read-only
node --input-type=module - "$TEST_PROJECT/output/final.md" <<'NODE'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const text=fs.readFileSync(process.argv[2], 'utf8');
const result=JSON.parse(text.replace(/^```(?:json)?\s*|\s*```$/g, '').trim());
assert.deepEqual(result.renderers, {A:'native', B:'mermaid', C:'mermaid', D:'mermaid', E:'native'});
assert.equal(result.simplePlan.nodeCount, 1);
assert.equal(result.simplePlan.advanceIndependentReview, false);
assert.equal(result.pendingAdjustment.mayExecuteAffected, false);
assert.equal(result.pendingAdjustment.displayAs, 'proposed');
assert.equal(result.displayTruth.claimLive, false);
assert.equal(result.displayTruth.endTurnToRefresh, false);
assert.match(result.displayTruth.sourceOfState, /plan|record|evidence/i);
const allowed=result.click.allowed.join(' '), forbidden=result.click.forbidden.join(' ');
assert.match(allowed, /detail|inspect|expand|reveal/i);
assert.match(forbidden, /status|state/i);
assert.match(forbidden, /depend|edge/i);
assert.match(forbidden, /execut|dispatch|start/i);
const checks=result.reviewChecks.join(' ');
assert.match(checks, /depend|prerequis|edge/i);
assert.match(checks, /concurr|parallel|overlap|serializ/i);
assert.match(checks, /owner|resource|file|writ/i);
assert.match(checks, /gat|verif|review/i);
// Compare the chosen IDs, allowing an explanatory suffix after a semicolon.
const selection=Object.fromEntries(Object.entries(result.selection).map(([key,value])=>[key,value.split(';',1)[0].trim()]));
assert.deepEqual(selection, {newSnapshot:'T4', sameSnapshot:'T9', noCompleted:'T4', noActive:'T2', multipleActive:'T8'});
for (const palette of Object.values(result.statusColors)) {
  assert.match(palette.done, /green/i);
  assert.match(palette.active, /blue/i);
  assert.match(palette.todo, /neutral|gray|grey/i);
  assert.match(palette.blocked, /amber|orange/i);
}
assert.equal(result.selectionMayObscureStatusColor, false);
for (const [state, extra] of Object.entries({active:['Progress'], blocked:['Blocked by'], done:['Result'], todo:[]})) {
  const rows=result.cards[state];
  assert.deepEqual(rows.map(row=>row.label), ['Owner / scope', 'Done when', ...extra], `${state} card omits redundant or empty fields`);
  assert.match(rows[0].value, /API verifier/i);
  assert.match(rows[0].value, /isolated test database/i);
  assert.match(rows[1].value, /permissions.*persistence.*pass/i);
}
assert.match(result.cards.active[2].value, /permission.*pass/i);
assert.match(result.cards.active[2].value, /persistence.*running/i);
assert.match(result.cards.blocked[2].value, /account.*unavailable/i);
assert.match(result.cards.blocked[2].value, /restore.*access/i);
assert.match(result.cards.done[2].value, /12.*pass/i);
assert.match(result.cards.done[2].value, /\/results\/api-checks\.txt/);
assert.equal(result.prerequisiteInspection.highlightsIncomingEdges, true);
assert.equal(result.prerequisiteInspection.highlightsPredecessors, true);
assert.match(result.prerequisiteInspection.accessibleDescription, /prerequis|depend|B1/i);
assert.match(result.mermaidDetails, /same|compact/i);
assert.match(result.mermaidDetails, /focus|selected|active/i);
console.log('STATUS: PASSED');
NODE
