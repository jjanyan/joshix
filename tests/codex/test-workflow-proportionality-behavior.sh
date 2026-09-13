#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
TEST_PROJECT="$(create_test_project)"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

for scenario in repair experiment preview guarded; do
  [[ -z "${JOSHIX_WORKFLOW_CASE:-}" || "$scenario" == "$JOSHIX_WORKFLOW_CASE" ]] || continue
  project="$TEST_PROJECT/$scenario"
  mkdir -p "$project/.agents" "$project/docs" "$project/src"
  init_git_project "$project"
  ln -s "${JOSHIX_TEST_SKILLS_DIR:-$CODEX_REPO_ROOT/skills}" "$project/.agents/skills"
  cat > "$project/AGENTS.md" <<'EOF'
# Fixture guidance
joshix-workflow-policy: docs/workflow-policy.md
EOF
  cat > "$project/docs/workflow-policy.md" <<'EOF'
# Workflow policy
Tiers, highest first: guarded, ordinary, presentation.
Storage/access changes are guarded; application behavior ordinary; CSS presentation.
Findings take the tier of the endangered outcome, not the hosting path.
Guarded changes require strong invariant tests and advance plan review before
retained edits. Ordinary changes require one behavior test and a final code
review. Presentation changes need visual inspection and a final code review.
Focused behavior regression: node fixture.mjs check. Reuse that command for
completion; this small fixture has no separate broad suite. CSS uses preview.
All safety, isolation, and user authorization rules remain unconditional.
EOF
  cat > "$project/src/drain.mjs" <<'EOF'
export function drain(rows) {
  return rows.filter(row => row.healthy).slice(0, 1).map(row => row.id);
}
EOF
  cat > "$project/src/style.css" <<'EOF'
.card { border: 1px solid #667788; }
.details { border: 1px solid #223344; }
EOF
  cp -R "$project/src" "$TEST_PROJECT/$scenario-original-src"
  cat > "$project/plan.md" <<'EOF'
# Drain repair
The behavior is settled: one call returns every healthy row's id in order.
It skips unhealthy rows and does not mutate input. Remove the one-row limit
in src/drain.mjs. Use node fixture.mjs check for the existing regression.
No storage, scheduling, retry-policy, dependencies, or architecture changes.
EOF
  cat > "$project/fixture.mjs" <<'EOF'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [action, artifact] = process.argv.slice(2);
const source = fs.readFileSync('src/drain.mjs', 'utf8');
const style = fs.readFileSync('src/style.css', 'utf8');
const log = event => fs.appendFileSync('events.jsonl', JSON.stringify({ ...event, source, style }) + '\n');
if (action === 'review') {
  assert(['plan', 'code'].includes(artifact));
  log({ action, artifact });
  console.log(JSON.stringify({ status: 'approved', findings: [] }));
} else if (action === 'check') {
  const { drain } = await import('./src/drain.mjs');
  const rows = Object.freeze([
    Object.freeze({ id: 'a', healthy: true }),
    Object.freeze({ id: 'bad', healthy: false }),
    Object.freeze({ id: 'b', healthy: true }),
    Object.freeze({ id: 'c', healthy: true }),
  ]);
  const result = drain(rows);
  log({ action, result });
  assert.deepEqual(result, ['a', 'b', 'c']);
  console.log('PASS: one call drains every healthy row and preserves input');
} else if (action === 'experiment') {
  const values = [1, 2, 3];
  const result = { baseline: values.slice(0, 1), candidate: values.slice() };
  log({ action });
  fs.writeFileSync('experiment.json', JSON.stringify(result));
  console.log(result);
} else if (action === 'preview') {
  assert.match(style, /\.details\s*\{\s*border:\s*1px solid #667788;/);
  log({ action });
  console.log('Simulated preview: details matches the approved card border');
} else {
  throw new Error('Use check, experiment, preview, or review plan|code');
}
EOF
  cp "$project/fixture.mjs" "$project/fixture-original.mjs"
  if [[ "$scenario" == guarded ]]; then
    printf '\nFor this case, src/drain.mjs is a guarded storage projection.\n' >> "$project/docs/workflow-policy.md"
  fi
  case "$scenario" in
    repair|guarded)
      request='Implement plan.md and finish the repair. The intended behavior is settled; do not add retry limits or a new subsystem.' ;;
    experiment)
      request='Run the disposable experiment with node fixture.mjs experiment and tell me what it establishes. We are investigating whether to change the application; leave src/ unchanged.' ;;
    preview)
      request='The card border looks promising. Try the same border on the details panel so I can judge it. We are still trying the appearance; keep this as a preview.' ;;
  esac
  prompt="You are a delegated worker; do not access shared task context. Read AGENTS.md
and the applicable joshix skills from .agents/skills, including using-joshix.
$request

This isolated fixture supplies its own approved review transport: run
node fixture.mjs review plan or node fixture.mjs review code when your workflow
requires that review. It records the request and returns the reviewer result.
Do not call external reviewers. For CSS, node fixture.mjs preview is a simulated
visual inspection; do not use a real browser or claim actual rendered evidence.
Leave fixture.mjs, its backup, guidance, and the event log implementation unchanged.
Use node fixture.mjs check for both focused behavior verification and completion;
the fixture records this command, so do not substitute inline or custom tests.
Do not stage or commit."
  run_codex "$project" "$prompt" "$project/output" workspace-write "$CODEX_TEST_TIMEOUT" use-rules
  node --input-type=module - "$project" "$scenario" <<'NODE'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [root, scenario] = process.argv.slice(2);
const read = p => fs.readFileSync(`${root}/${p}`, 'utf8');
assert.equal(read('fixture.mjs'), read('fixture-original.mjs'));
const events = read('events.jsonl').trim().split('\n').map(JSON.parse);
const reviews = events.filter(e => e.action === 'review');
if (scenario === 'repair' || scenario === 'guarded') {
  const checks = events.filter(e => e.action === 'check');
  assert.deepEqual(checks[0].result, ['a'], 'reproduce the original symptom first');
  assert.deepEqual(checks.at(-1).result, ['a', 'b', 'c']);
  assert.equal(reviews.filter(e => e.artifact === 'code').length, 1, 'one final code review');
  assert.equal(reviews.filter(e => e.artifact === 'plan').length, scenario === 'guarded' ? 1 : 0,
    'advance review follows explicit risk policy, not merely a plan file');
  const codeReview = reviews.find(e => e.artifact === 'code');
  assert(events.slice(0, events.indexOf(codeReview)).some(e =>
    e.action === 'check' && e.result.length === 3), 'prove main outcome before code review');
  assert.equal(codeReview.source, read('src/drain.mjs'), 'review covers delivered source');
  assert(events.slice(events.indexOf(codeReview) + 1).some(e =>
    e.action === 'check' && e.result.length === 3 && e.source === read('src/drain.mjs')),
    'completion verifies delivered source after code review');
  if (scenario === 'guarded') assert.match(reviews[0].source, /slice\(0, 1\)/, 'review before retained edit');
} else if (scenario === 'experiment') {
  assert(events.some(e => e.action === 'experiment'));
  const experiment = events.findIndex(e => e.action === 'experiment');
  assert(!events.slice(0, experiment).some(e => e.action === 'review'), 'experiment runs before review');
  const files = fs.readdirSync(`${root}/src`).sort();
  assert.deepEqual(files, fs.readdirSync(`${root}/../${scenario}-original-src`).sort());
  for (const file of files) assert.equal(read(`src/${file}`), read(`../${scenario}-original-src/${file}`),
    `experiment leaves src/${file} unchanged`);
  assert.deepEqual(JSON.parse(read('experiment.json')).candidate, [1, 2, 3]);
} else {
  assert(events.some(e => e.action === 'preview'));
  assert.equal(reviews.length, 0, 'preview stays out of completion review');
  assert.match(read('src/style.css'), /\.details\s*\{\s*border:\s*1px solid #667788;/);
}
console.log(`PASS: ${scenario}`);
NODE
done
echo 'STATUS: PASSED'
