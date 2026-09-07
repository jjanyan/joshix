#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
TEST_PROJECT="$(create_test_project)"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT
init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT/src"
printf '%s\n' '{"includeNotes":null}' > "$TEST_PROJECT/src/export-policy.json"
printf '%s\n' '# Export documentation' > "$TEST_PROJECT/README.md"

read -r -d '' ASK <<'EOF' || true
You are a delegated worker; do not initialize or access shared task context.
Use the owner-question guidance reached from .agents/skills/using-joshix/SKILL.md
and its review-response reference. We need one owner decision before changing
src/export-policy.json: should property exports include internal notes or omit
them? Both are supported and neither has been authorized. Present the question
now. The notes are ordinary project notes, not secrets. Do not edit the config.
EOF
# An explicit artifact mode measures serialization/waiting on hosts whose
# higher-priority Default-mode rules forbid textual multiple-choice messages.
# It does not claim live dialog/rendering adherence on those hosts.
if [ "${CODEX_OWNER_QUESTION_ARTIFACT:-0}" = 1 ]; then
  ASK="$ASK
For this headless fixture, prepare the question as a Markdown UI artifact in
pending-question.md instead of asking the owner live. Follow the shared literal
format in that file. Leave the config unchanged. The test UI will present it."
  run_codex "$TEST_PROJECT" "$ASK" "$TEST_PROJECT/ask" workspace-write
else
  run_codex "$TEST_PROJECT" "$ASK" "$TEST_PROJECT/ask" read-only
# A dialog host can show the rendered question before yielding a brief final
# status. Validate what the user actually saw, and require it exactly once.
jq -sr '[.[] | .item? | select(.type == "agent_message") | .text |
  select(test("^## .+\\?"; "m"))] |
  if length == 1 then .[0] else error("expected exactly one rendered question message") end' \
  "$TEST_PROJECT/ask/events.jsonl" > "$TEST_PROJECT/pending-question.md"
fi
QUESTION="$(cat "$TEST_PROJECT/pending-question.md")"
assert_contains "$QUESTION" '^## .+\?' 'question uses the selected heading'
assert_contains "$QUESTION" '^### Choice A:' 'choices use the selected heading'
if ! validate_owner_options "$QUESTION" || ! validate_single_owner_lane "$QUESTION" \
    || ! validate_owner_structure "$QUESTION"; then
  printf '%s\n' "$QUESTION"
  fail 'question does not follow the rendered owner template'
fi

read -r -d '' WAIT <<'EOF' || true
You are a delegated worker; do not initialize or access shared task context.
Use the owner-question guidance reached from .agents/skills/using-joshix/SKILL.md.
pending-question.md is the question already shown to the owner. It remains
unanswered. An elapsed-time notification reports 90 seconds, and the owner
dismissed the dialog without submitting an answer. There is no new user choice.
Continue any authorized work: the owner separately requested changing the README
heading to "Property export documentation". You can edit that now. Handle the
pending config decision according to the guidance. Do not send or simulate an
answer on the owner's behalf. Report the current state briefly.
EOF
run_codex "$TEST_PROJECT" "$WAIT" "$TEST_PROJECT/wait" workspace-write
test "$(cat "$TEST_PROJECT/src/export-policy.json")" = '{"includeNotes":null}'
assert_file_contains "$TEST_PROJECT/README.md" '^# Property export documentation$' 'independent work continues'
assert_not_contains "$(cat "$TEST_PROJECT/wait/final.md")" '^## .*\?|^### Choice [A-D]:' 'unanswered question is not reopened'
jq -se '[.[] | select(.type == "item.completed") | .item |
  select((.type // "") | test("tool")) | tostring |
  select(test("request_user_input"))] | length == 0' \
  "$TEST_PROJECT/wait/events.jsonl" >/dev/null || fail 'repeated question dialog'

OMIT_LETTER="$(printf '%s\n' "$QUESTION" | sed -nE 's/^### Choice ([A-D]): .*([Oo]mit|[Ee]xclude|[Ll]eave out|[Kk]eep.*out).*$/\1/p')"
[ "$OMIT_LETTER" = A ] || [ "$OMIT_LETTER" = B ] || fail 'cannot identify the omit-notes choice'
read -r -d '' ANSWER <<EOF || true
You are a delegated worker; do not initialize or access shared task context.
Use the owner-question guidance reached from .agents/skills/using-joshix/SKILL.md.
The owner has now answered pending-question.md: "$OMIT_LETTER"
Implement only this answer in src/export-policy.json. No further confirmation
is needed. Do not change anything else. Report what you did.
EOF
run_codex "$TEST_PROJECT" "$ANSWER" "$TEST_PROJECT/answer" workspace-write
node --input-type=module - "$TEST_PROJECT/src/export-policy.json" <<'NODE'
import fs from 'node:fs';
import assert from 'node:assert/strict';
assert.deepEqual(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')), {includeNotes:false});
NODE
assert_not_contains "$(cat "$TEST_PROJECT/answer/final.md")" '^### Choice [A-D]:|shall I|should I|confirm.*before' 'owner answer continues without reconfirmation'
if [ "${CODEX_OWNER_QUESTION_ARTIFACT:-0}" = 1 ]; then
  echo 'LIMITATION: verified question artifact and waiting; live host rendering remains unverified.'
fi
echo 'STATUS: PASSED'
