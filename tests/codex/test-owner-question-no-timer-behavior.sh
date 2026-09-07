#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
TEST_PROJECT="$(create_test_project)"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT
init_git_project "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT/.agents" "$TEST_PROJECT/src"
SKILLS_DIR="${JOSHIX_TEST_SKILLS_DIR:-$CODEX_REPO_ROOT/skills}"
ln -s "$SKILLS_DIR" "$TEST_PROJECT/.agents/skills"
printf '%s\n' '{"includeNotes":null}' > "$TEST_PROJECT/src/export-policy.json"
printf '%s\n' '# Export documentation' > "$TEST_PROJECT/README.md"

# Test actual questioning/waiting, independently of the host's choice-format
# restrictions. The harness deadline only catches stuck tests; it never supplies
# an owner answer. Agent-created timers and silent dependent edits are failures.
read -r -d '' ASK <<'EOF' || true
You are a delegated worker; do not initialize or access shared task context.
Use .agents/skills/using-joshix/SKILL.md and its owner-question guidance.
Prepare the property export settings. I want to decide whether internal project
notes should be included or omitted, so ask me before setting includeNotes in
src/export-policy.json. Both choices are supported. Separately, rename the README
heading to "Property export documentation". I may be away when you ask.
EOF
run_codex "$TEST_PROJECT" "$ASK" "$TEST_PROJECT/ask" workspace-write
test "$(cat "$TEST_PROJECT/src/export-policy.json")" = '{"includeNotes":null}'
assert_file_contains "$TEST_PROJECT/README.md" '^# Property export documentation$' 'independent work completes before waiting'
jq -sr '[.[] | .item? | select(.type == "agent_message") | .text] | join("\n\n")' \
  "$TEST_PROJECT/ask/events.jsonl" > "$TEST_PROJECT/pending-question.md"
assert_file_contains "$TEST_PROJECT/pending-question.md" '\?' 'agent asks a real question'

read -r -d '' UNANSWERED <<'EOF' || true
You are a delegated worker; do not initialize or access shared task context.
Use .agents/skills/using-joshix/SKILL.md and its owner-question guidance.
pending-question.md contains the question already presented to the owner.
The question tool has returned no submitted answer. The dialog was dismissed;
120 seconds have elapsed. Continue this task from that state.
EOF
run_codex "$TEST_PROJECT" "$UNANSWERED" "$TEST_PROJECT/unanswered" workspace-write
test "$(cat "$TEST_PROJECT/src/export-policy.json")" = '{"includeNotes":null}'

node --input-type=module - "$TEST_PROJECT" <<'NODE'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const root = process.argv[2];
for (const phase of ['ask', 'unanswered']) {
  const events = fs.readFileSync(`${root}/${phase}/events.jsonl`, 'utf8').trim().split('\n').map(JSON.parse);
  const completed = events.filter(event => event.type === 'item.completed').map(event => event.item);
  const messages = completed.filter(item => item.type === 'agent_message').map(item => item.text).join('\n');
  const commands = completed.filter(item => item.type === 'command_execution').map(item => item.command).join('\n');
  assert.doesNotMatch(messages, /(?:I['’]ll|I will|going to)\s+(?:wait|allow|give you)\s+(?:\w+\s+){0,4}\d+\s*(?:seconds?|minutes?)/i,
    `${phase}: agent announced a response timer`);
  assert.doesNotMatch(messages, /(?:if|unless)\s+(?:you|I).*?(?:hear|reply|respond|answer).*?(?:assume|default|proceed|choose|select)/i,
    `${phase}: agent announced an assumed answer`);
  assert.doesNotMatch(commands, /\bsleep\s+\d|\b(?:time|asyncio)\.sleep\s*\(|\bsetTimeout\s*\(|clock[._]+sleep/i,
    `${phase}: agent started a timer while awaiting a decision`);
  if (phase === 'unanswered') {
    assert.doesNotMatch(messages, /\?/, 'agent reissued the unanswered question');
    assert(!completed.some(item => /tool/.test(item.type) && /request_user_input/.test(JSON.stringify(item))),
      'agent reopened the question tool');
  }
}
console.log('PASS: no timer, deadline, assumed answer, or repeated question in either turn');
NODE

read -r -d '' ANSWER <<'EOF' || true
You are a delegated worker; do not initialize or access shared task context.
Use .agents/skills/using-joshix/SKILL.md and its owner-question guidance.
My answer to pending-question.md: omit the notes. Apply my answer.
EOF
run_codex "$TEST_PROJECT" "$ANSWER" "$TEST_PROJECT/answer" workspace-write
node --input-type=module - "$TEST_PROJECT/src/export-policy.json" <<'NODE'
import fs from 'node:fs';
import assert from 'node:assert/strict';
assert.deepEqual(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')), { includeNotes: false });
NODE
echo 'STATUS: PASSED (live Codex turns; native desktop dialog chrome not inspected)'
