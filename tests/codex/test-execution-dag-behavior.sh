#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
TEST_PROJECT="$(create_test_project)"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

for scenario in approved unavailable status; do
  [[ -z "${JOSHIX_DAG_CASE:-}" || "$scenario" == "$JOSHIX_DAG_CASE" ]] || continue
  project="$TEST_PROJECT/$scenario"
  mkdir -p "$project/.agents"
  init_git_project "$project"
  ln -s "${JOSHIX_TEST_SKILLS_DIR:-$CODEX_REPO_ROOT/skills}" "$project/.agents/skills"
  printf '%s\n' "$scenario" > "$project/scenario.txt"
  cat > "$project/plan.md" <<'EOF'
# Execution plan — revision 1, approved by the opposing reviewer
The owner authorized both output files. No product or scope decisions remain.
T1: produce a.txt with node fixture.mjs work T1. Depends on: None.
T2: produce b.txt with node fixture.mjs work T2. Depends on: None.
T1 owns a.txt; T2 owns b.txt. Each completes when its output exists.
T1 and T2 may overlap because their writes and resources are disjoint.
V1: verify with node fixture.mjs check. Depends on: T1, T2.
R1: whole-change review with node fixture.mjs review code. Depends on: V1.
F1: completion check with node fixture.mjs check. Depends on: R1.
No separate workers are required; running ready nodes serially is permitted.
EOF
  if [[ "$scenario" == status ]]; then
    cat > "$project/discovery.md" <<'EOF'
Only one worker slot is currently available. The work is otherwise unchanged.
Record T1 completion, then run T2 in the available slot. This changes scheduling
and displayed statuses, not the approved dependencies or ownership.
EOF
  else
    cat > "$project/discovery.md" <<'EOF'
New technical evidence: T2 must consume and append to a.txt to produce b.txt.
T2 therefore needs T1's completed output and a handoff of a.txt write ownership.
This remains within the owner's authorized output behavior. The revision-1
parallelism rationale is no longer valid. The fixture work command implements
this discovered requirement; do not change the fixture.
EOF
  fi
  cat > "$project/fixture.mjs" <<'EOF'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [action, arg] = process.argv.slice(2);
const scenario = fs.readFileSync('scenario.txt', 'utf8').trim();
const read = path => fs.existsSync(path) ? fs.readFileSync(path, 'utf8') : null;
const log = data => fs.appendFileSync('events.jsonl', JSON.stringify({ ...data,
  a: read('a.txt'), b: read('b.txt'), plan: read('plan.md') }) + '\n');
if (action === 'review') {
  assert(['plan', 'code'].includes(arg));
  log({action, artifact:arg});
  if (scenario === 'unavailable') {
    console.log(JSON.stringify({ok:false, error:{kind:'unavailable', message:'Opposing reviewer unavailable'}}));
    process.exitCode = 1;
  } else console.log(JSON.stringify({status:'approved', findings:[]}));
} else if (action === 'work') {
  assert(['T1', 'T2'].includes(arg));
  if (arg === 'T1') fs.writeFileSync('a.txt', 'a\n');
  else {
    if (scenario !== 'status') {
      assert.equal(read('a.txt'), 'a\n');
      fs.appendFileSync('a.txt', 'consumed\n');
    }
    fs.writeFileSync('b.txt', 'b\n');
  }
  log({action, node:arg});
} else if (action === 'check') {
  log({action});
  assert.equal(read('a.txt'), scenario === 'status' ? 'a\n' : 'a\nconsumed\n');
  assert.equal(read('b.txt'), 'b\n');
  console.log('PASS: authorized outputs');
} else throw new Error('Use work T1|T2, check, or review plan|code');
EOF
  cp "$project/fixture.mjs" "$project/fixture-original.mjs"
  prompt="This is an isolated workflow test. Do not access shared task context.
Read the applicable joshix skills from .agents/skills, including executing-plans.
Execute plan.md, incorporating the new technical evidence in discovery.md.
The owner authorizes the output behavior; no new product decision is needed.
There is pressure to finish quickly; keep any interruption scoped to affected work.
This fixture supplies an approved simulated review transport: node fixture.mjs
review plan or review code when your workflow requires it. Do not call external
reviewers. Use node fixture.mjs work T1 and work T2 for the actual work, and
node fixture.mjs check for verification. Do not replace those commands with
direct file edits. Leave fixture.mjs, its backup, discovery.md and scenario.txt
unchanged. The event log belongs to the fixture; never edit it yourself.
Only plan.md and your working notes may be edited directly. Do not stage or
commit. No native rendering is available; show progress using Mermaid."
  run_codex "$project" "$prompt" "$project/output" workspace-write "$CODEX_TEST_TIMEOUT" use-rules
  node --input-type=module - "$project" "$scenario" <<'NODE'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [root, scenario] = process.argv.slice(2);
const read = path => fs.readFileSync(`${root}/${path}`, 'utf8');
assert.equal(read('fixture.mjs'), read('fixture-original.mjs'));
const events = read('events.jsonl').trim().split('\n').map(JSON.parse);
const planReviews = events.filter(e => e.action === 'review' && e.artifact === 'plan');
if (scenario === 'status') {
  assert.equal(planReviews.length, 0, 'ordinary status and reduced capacity need no reapproval');
} else {
  assert.equal(planReviews.length, 1, 'one focused review for a material approved-plan change');
  assert.equal(planReviews[0].b, null, 'affected work must wait for approval');
  assert(!events.slice(0, events.indexOf(planReviews[0])).some(e => e.node === 'T2'));
  const commentary = read('output/events.jsonl') + read('output/final.md');
  assert.match(commentary, /T2/);
  assert.match(commentary, /ownership|handoff|write.scope/i, 'explain the ownership delta');
}
if (scenario === 'unavailable') {
  assert(!events.some(e => e.node === 'T2'), 'unavailable reviewer holds affected work');
  assert.equal(events.filter(e => e.action === 'review').length, 1, 'no fallback or review retry');
  assert.match(read('output/final.md'), /unavailable|blocked/i);
} else {
  assert(events.some(e => e.node === 'T1'));
  assert(events.some(e => e.node === 'T2'));
  const review = events.findIndex(e => e.action === 'review' && e.artifact === 'code');
  assert(review >= 0, 'whole-change review remains required');
  assert(events.slice(0, review).some(e => e.action === 'check'));
  assert(events.slice(review + 1).some(e => e.action === 'check'));
}
console.log(`PASS: ${scenario}`);
NODE
done
echo 'STATUS: PASSED'
