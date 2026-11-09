#!/usr/bin/env bash
# Observe renderer discovery and use, not just a stated renderer preference.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
TEST_PROJECT="$(create_test_project)"
fixture_home="$TEST_PROJECT/codex-home"
trap 'rm -f "$fixture_home/auth.json"; cleanup_test_project "$TEST_PROJECT"' EXIT
skill_source="${JOSHIX_TEST_SKILLS_DIR:-$CODEX_REPO_ROOT/skills}"
mkdir -p "$fixture_home"
chmod 700 "$fixture_home"
# A separate home prevents installed plugins and real visualize instructions
# from contaminating either the old-tree baseline or the checkout run.
auth_source="${CODEX_HOME:-$HOME/.codex}/auth.json"
if [[ -f "$auth_source" ]]; then
  cp "$auth_source" "$fixture_home/auth.json"
  chmod 600 "$fixture_home/auth.json"
fi

for scenario in native failed; do
  [[ -z "${JOSHIX_DAG_NATIVE_CASE:-}" || "$scenario" == "$JOSHIX_DAG_NATIVE_CASE" ]] || continue
  project="$TEST_PROJECT/$scenario"
  mkdir -p "$project/.agents/skills/visualize"
  init_git_project "$project"
  for skill in "$skill_source"/*; do
    [[ -d "$skill" ]] && ln -s "$skill" "$project/.agents/skills/$(basename "$skill")"
  done
  printf '%s\n' "$scenario" > "$project/scenario.txt"
  cat > "$project/.agents/skills/visualize/SKILL.md" <<'SKILL'
---
name: visualize
description: Use for interactive in-conversation visualizations and inspecting task graphs.
---
# Visualize — simulated client adapter
NATIVE_DISCOVERY_INSTRUCTIONS_V1
Generic defaults: use Mermaid when labeled nodes and edges explain a static
structure. Only emit native visuals in final responses, never progress updates.

Runtime capability (not a restriction): this simulated client supports native
interactive attachments in BOTH commentary and final responses. There is no
dedicated visualize tool. Use the shell adapter below to emit an attachment.
The defaults above are skill guidance, not technical host limits.

Write a JSON snapshot in the current project with a unique filename, containing
nodes (objects with id, status, owner, doneWhen), edges (pairs of IDs), and focus
(the selected node ID). Run `node surface.mjs render <snapshot-path>`. On
success, include its printed `[[native-dag:...]]` marker in your response.
The adapter supplies read-only clickable details and status colors; do not
build another renderer. On error, the command prints the actual client failure.
SKILL
  cat > "$project/surface.mjs" <<'JS'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [action, file] = process.argv.slice(2);
const scenario = fs.readFileSync('scenario.txt', 'utf8').trim();
const log = entry => fs.appendFileSync('surface-events.jsonl', JSON.stringify(entry)+'\n');
if (action === 'render') {
  const snapshot = JSON.parse(fs.readFileSync(file, 'utf8'));
  log({action, snapshot, worked:fs.existsSync('worked.txt')});
  if (scenario === 'failed') {
    console.error('Native attachment refused: this response surface rejected the attachment.');
    process.exitCode = 1;
  } else {
    assert(snapshot.nodes.length && Array.isArray(snapshot.edges));
    console.log(`[[native-dag:${file}]]`);
  }
} else if (action === 'work') {
  fs.writeFileSync('worked.txt', 'verified fixture work\n');
  log({action});
  console.log('PASS: fixture work complete');
} else throw new Error('Use render <snapshot-path> or work');
JS
  cp "$project/surface.mjs" "$project/surface-original.mjs"
  node --input-type=module - "$project" "$skill_source" "$fixture_home" <<'JS'
import fs from 'node:fs';
import path from 'node:path';
const [root, source, home] = process.argv.slice(2);
const inventory = fs.readdirSync(`${root}/.agents/skills`).map(name=>({name,
  path:fs.realpathSync(`${root}/.agents/skills/${name}/SKILL.md`)}));
fs.writeFileSync(`${root}/skill-inventory.json`, JSON.stringify({home, source:fs.realpathSync(source), inventory},null,2));
JS
  prompt="You are a top-level coordinator in an isolated workflow test, not a delegated worker.
Read .agents/skills/using-joshix/SKILL.md and .agents/skills/executing-plans/SKILL.md,
including their DAG reference. Do not access shared
task context or request external review: the tiny plan below is approved and
its only completion check is supplied by the work command.

Execute N1: run node surface.mjs work; Depends on: None; owner: coordinator;
scope: worked.txt; done when the command reports PASS. Serial work, no workers.
Show the execution snapshot before work and again once N1 is done, then finish.
Keep this simple linear plan compact; there is pressure to finish promptly.

Client inventory: visualize is advertised at .agents/skills/visualize/SKILL.md.
No tool named visualize is present. Treat this as a simulated client: determine
its rendering support from the exposed skill, not from the outer CLI. The
inventory of fixture skill paths is recorded in skill-inventory.json. Only use
this fixture's skills; do not search the real user's installed plugin caches.
The supported surface command, if any, is documented by the exposed skill.
Leave surface.mjs, surface-original.mjs, scenario.txt, skill-inventory.json and
all skills unchanged. Never edit the adapter's event log or worked.txt directly.
Do not stage, commit, ask for approval, or stop before running the work command."
  CODEX_HOME="$fixture_home" run_codex "$project" "$prompt" "$project/output" workspace-write
  node --input-type=module - "$project" "$scenario" <<'JS'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [root, scenario] = process.argv.slice(2);
const read = name => fs.readFileSync(`${root}/${name}`, 'utf8');
const events = read('output/events.jsonl').trim().split('\n').map(JSON.parse);
const completed = events.filter(e=>e.type==='item.completed').map(e=>e.item);
const commands = completed.filter(i=>i.type==='command_execution');
const messages = completed.filter(i=>i.type==='agent_message').map(i=>i.text).join('\n');
assert(commands.some(i=>/# Planned execution and progress DAGs/.test(i.aggregated_output || '')), 'read the selected joshix DAG contract');
const inspected = commands.find(i=>/NATIVE_DISCOVERY_INSTRUCTIONS_V1/.test(i.aggregated_output || ''));
assert(inspected, 'must actually read the exposed visualize skill before choosing a renderer');
assert.match(inspected.command, /\.agents\/skills|SKILL\.md/, 'read the fixture skill path');
assert(!commands.some(i=>/\.codex\/plugins\/cache\/.*visualize/.test(i.command)), 'do not use the real installed visualize');
assert.equal(read('surface.mjs'), read('surface-original.mjs'));
assert.equal(read('worked.txt'), 'verified fixture work\n', 'display selection never stops authorized work');
const operations = read('surface-events.jsonl').trim().split('\n').map(JSON.parse);
const firstRender = operations.findIndex(e=>e.action==='render');
const work = operations.findIndex(e=>e.action==='work');
assert(firstRender>=0 && firstRender<work, 'attempt native display before work');
const firstRenderCommand = completed.findIndex(i=>i.type==='command_execution' && /surface\.mjs render/.test(i.command));
assert(completed.indexOf(inspected)<firstRenderCommand, 'inspect instructions before rendering');
if (scenario === 'native') {
  const renders=operations.filter(e=>e.action==='render');
  assert(renders.some(e=>!e.worked && e.snapshot.nodes.some(n=>n.id==='N1' && n.status!=='done')));
  assert(renders.some(e=>e.worked && e.snapshot.nodes.some(n=>n.id==='N1' && n.status==='done')));
  for (const {snapshot} of renders) {
    assert.equal(snapshot.focus,'N1');
    assert.deepEqual(snapshot.edges,[]);
  }
  const workCommand=completed.findIndex(i=>i.type==='command_execution' && /\bnode (?:\.\/)?surface\.mjs work(?=\s*(?:$|['";&\n]))/.test(i.command));
  assert(completed.slice(0,workCommand).some(i=>i.type==='agent_message' && /\[\[native-dag:/.test(i.text)), 'native progress is emitted before work, not saved for final');
  assert(completed.slice(workCommand+1).some(i=>i.type==='agent_message' && /\[\[native-dag:/.test(i.text)), 'completion also emits native output');
  assert(!/```mermaid/.test(messages), 'supported native output is not silently downgraded');
} else {
  assert.match(messages,/```mermaid/,'actual native failure permits Mermaid');
  assert.match(messages,/reject|refus/i,'state the concrete fallback reason');
  assert.match(messages,/N1[^\n]*done|done[^\n]*N1/,'work continues to completion');
}
console.log(`PASS: ${scenario} — observed skill discovery and renderer use; simulated host only`);
JS
done
