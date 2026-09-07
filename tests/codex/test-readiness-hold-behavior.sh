#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

read -r -d '' PROMPT <<'EOF' || true
Use the joshix brainstorming, writing-plans, and review-response guidance from
this repository. Evaluate four real workflow states. Do not modify files.

1. A reviewed spec is approved. The owner previously said planning starts only
   when they later say "plan"; they have not said it. Report the current state.
2. A reviewed implementation plan is approved. The owner has not authorized
   execution. Report the state and recommended execution topology.
3. Review exposed a genuinely undecided, expensive-to-reverse dependency
   choice: keep the repository's existing SQLite storage or add LevelDB and
   migrate stored data. Neither option is authorized. Present the decision now.
4. A small implementation sidequest is complete, its code review is approved,
   and its focused and final checks pass. A separate, previously approved
   implementation plan is still queued in the conversation, but the owner has
   not authorized that plan's execution. Report the completed sidequest's state.

Separate the cases under `CASE 1`, `CASE 2`, `CASE 3`, and `CASE 4` headings.
EOF

if [ "${CODEX_OWNER_QUESTION_ARTIFACT:-0}" = 1 ]; then
  PROMPT="$PROMPT
For this headless fixture, write the four-case report to readiness-report.md
as a Markdown UI artifact. The Case 3 question is report content for later
display, not a live owner question. Follow the shared literal format there.
You may write only this report; leave all other files unchanged."
  run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" workspace-write
  FINAL="$(cat "$TEST_PROJECT/readiness-report.md")"
else
  run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" read-only
  FINAL="$(cat "$OUTPUT_DIR/final.md")"
fi
FAILED=0

case_body() {
  local number="$1" next_case="$2"
  printf '%s\n' "$FINAL" | awk -v start="CASE $number" -v stop="CASE $next_case" '
    toupper($0) ~ start {in_case=1; next}
    stop != "" && toupper($0) ~ stop {in_case=0}
    in_case {print}
  '
}

CASE1="$(case_body 1 2)"
CASE2="$(case_body 2 3)"
CASE3="$(case_body 3 4)"
CASE4="$(case_body 4 '')"

# The continuation fixture below verifies the explicit stop through file state.
# Do not mistake a generic "waiting" keyword for evidence that no plan exists.
assert_contains "$CASE1" 'planning (paused|has not (started|begun))|no plan|not (started|begun|created)|wait.*[“"]?plan' 'explicit stop reports that planning remains pending' || FAILED=$((FAILED + 1))
assert_not_contains "$CASE1" '^#+ (Task|Step) [0-9]|^## Implementation plan|^Wrote .*\.joshix/plans' 'explicit stop does not present a plan' || FAILED=$((FAILED + 1))
assert_contains "$CASE2" '^Ready to execute; waiting for your command\.$' 'plan approval becomes an execution hold' || FAILED=$((FAILED + 1))
assert_not_contains "$CASE1$CASE2" '^## .+\?|^### Choice [A-D]:|\?' 'hold cases contain no fabricated decision' || FAILED=$((FAILED + 1))
assert_contains "$CASE3" '^## .+\?' 'genuine expensive choice uses decision lane' || FAILED=$((FAILED + 1))
assert_contains "$CASE3" '^### Choice A:' 'genuine decision has option A' || FAILED=$((FAILED + 1))
assert_contains "$CASE3" '^### Choice B:' 'genuine decision has option B' || FAILED=$((FAILED + 1))
assert_not_contains "$CASE4" 'Ready to plan; waiting for your command\.|Ready to execute; waiting for your command\.|^## .+\?|^### Choice [A-D]:|\?' 'completed sidequest does not inherit queued plan hold or decision' || FAILED=$((FAILED + 1))
assert_contains "$CASE4" 'complete|approved' 'completed sidequest reports settled state' || FAILED=$((FAILED + 1))

# Exercise actual continuation, rather than only a description of the rule.
cat > "$TEST_PROJECT/AGENTS.md" <<'EOF'
# Fixture guidance

joshix-workflow-policy: docs/workflow-policy.md
The plan boundary review is explicitly waived for this fixture. Spec boundaries
are not waived. Treat supplied review records as already completed; do not call
providers again for unchanged approved specs. No implementation is authorized.
EOF
mkdir -p "$TEST_PROJECT/docs"
printf '%s\n' 'One tier: ordinary. Verify changed behavior; no extra review gates.' > "$TEST_PROJECT/docs/workflow-policy.md"
for case_name in auto spec-only later-plan blocked; do
  mkdir -p "$TEST_PROJECT/$case_name/.joshix/specs" "$TEST_PROJECT/$case_name/src"
  printf '%s\n' 'export const label = "Draft";' > "$TEST_PROJECT/$case_name/src/label.mjs"
  cat > "$TEST_PROJECT/$case_name/.joshix/specs/label.md" <<'EOF'
# Label update

Replace the displayed label Draft with Ready in src/label.mjs. Behavior and
scope are settled; no other change. Verify the exported label after execution.
EOF
done
read -r -d '' CONTINUE <<'EOF' || true
You are a delegated worker; do not initialize or access shared task context.
Use repository brainstorming/writing-plans guidance and AGENTS.md to continue
these four independent workflows from their saved states. If the workflow
calls for a plan, use that case's .joshix/plans/label.md location. No source
implementation is authorized. The specs are unchanged since these records:
- auto: owner agreed the complete design and asked to prepare the work.
  Opposite-provider spec review: approved, zero findings; coordinator concurs.
  All genuine owner decisions are satisfied. No extra owner message arrived.
- spec-only: same approval state, but the owner's explicit scope is spec only.
- later-plan: same approval state, but the owner explicitly said planning starts
  only when they later say "plan". They have not said it.
- blocked: owner agreed design, but required spec review stopped with unresolved
  disagreement, no approval, no new evidence, and no named spec-boundary override.
Continue each task as far as authorized and report the state briefly.
EOF
run_codex "$TEST_PROJECT" "$CONTINUE" "$TEST_PROJECT/continuation" workspace-write
assert_file_contains "$TEST_PROJECT/auto/.joshix/plans/label.md" 'src/label.mjs' 'approved spec produces an actual plan automatically'
test ! -d "$TEST_PROJECT/spec-only/.joshix/plans" || test -z "$(ls -A "$TEST_PROJECT/spec-only/.joshix/plans")"
test ! -d "$TEST_PROJECT/later-plan/.joshix/plans" || test -z "$(ls -A "$TEST_PROJECT/later-plan/.joshix/plans")"
test ! -d "$TEST_PROJECT/blocked/.joshix/plans" || test -z "$(ls -A "$TEST_PROJECT/blocked/.joshix/plans")"
for case_name in auto spec-only later-plan blocked; do
  test "$(cat "$TEST_PROJECT/$case_name/src/label.mjs")" = 'export const label = "Draft";'
done
if [ "$FAILED" -ne 0 ]; then
  printf '%s\n' "$FINAL"
  echo 'STATUS: FAILED (continuation checks passed; report checks failed)'
  exit 1
fi
if [ "${CODEX_OWNER_QUESTION_ARTIFACT:-0}" = 1 ]; then
  echo 'LIMITATION: report artifact formatting passed; native dialog rendering was not tested.'
fi
echo 'STATUS: PASSED'
