#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

oracle_only() {
  local using="$ROOT/skills/using-joshix/SKILL.md"
  local contract="$ROOT/skills/using-joshix/references/review-reception-contract.md"
  local format="$ROOT/skills/using-joshix/references/review-response-format.md"
  local normalized_using
  normalized_using="$(tr '\n\r\t' '   ' < "$using" | tr -s ' ')"
  for expected in \
    'concrete code or diff' \
    'named plan' \
    'named spec' \
    'product discussion' \
    'proposed architecture' \
    'normal conversational response' \
    'phrase `review` alone does not select artifact reception'; do
    [[ "$normalized_using" == *"$expected"* ]] || {
      printf 'FAIL: bootstrap discussion routing missing: %s\n' "$expected"
      return 1
    }
  done
  rg -Fq -- 'concrete code or diff' "$contract"
  rg -Fq -- 'named plan' "$contract"
  rg -Fq -- 'named spec' "$contract"
  local normalized_format
  normalized_format="$(tr '\n\r\t' '   ' < "$format" | tr -s ' ')"
  [[ "$normalized_format" == *'does not apply to task history, `current.md`, product discussion, proposed architecture, or general chat'* ]]
  echo 'STATUS: PASSED'
}

if [ "${1:-}" = '--oracle-only' ]; then
  oracle_only
  exit 0
fi

oracle_only >/dev/null
TEST_PROJECT="$(create_test_project)"
DISCUSSION_OUTPUT="$TEST_PROJECT/discussion-output"
SPEC_OUTPUT="$TEST_PROJECT/spec-output"
TASK_REL='.joshix/tasks/discussion-routing'
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"
cp "$ROOT/AGENTS.md" "$TEST_PROJECT/AGENTS.md"
mkdir -p "$TEST_PROJECT/.joshix/context" "$TEST_PROJECT/.joshix/specs"
(
  cd "$TEST_PROJECT"
  node "$ROOT/skills/task-context/scripts/task-context.mjs" init "$TASK_REL"
)
cat > "$TEST_PROJECT/.joshix/context/discussion-one.txt" <<'EOF'
We are deciding how a host launcher should work. No spec, plan, or code exists.
EOF
cat > "$TEST_PROJECT/.joshix/context/discussion-two.txt" <<'EOF'
I agree with the launcher design. Add one automatic retry for an infrastructure failure before workload start.
EOF
(
  cd "$TEST_PROJECT"
  node "$ROOT/skills/task-context/scripts/task-context.mjs" append "$TASK_REL" --speaker Codex --content-file .joshix/context/discussion-one.txt
  node "$ROOT/skills/task-context/scripts/task-context.mjs" append "$TASK_REL" --speaker Claude --content-file .joshix/context/discussion-two.txt
)

read -r -d '' DISCUSSION_PROMPT <<'EOF' || true
Read the shared chat and respond to the review. The other agent agrees with the
launcher and suggests one automatic infrastructure retry. Continue the product
and architecture discussion; there is no document or code yet.
EOF
run_codex "$TEST_PROJECT" "$DISCUSSION_PROMPT" "$DISCUSSION_OUTPUT" read-only "$CODEX_TEST_TIMEOUT" use-rules
DISCUSSION_FINAL="$(cat "$DISCUSSION_OUTPUT/final.md")"

cat > "$TEST_PROJECT/.joshix/specs/retry-design.md" <<'EOF'
# Retry design

One automatic pre-workload infrastructure retry is allowed.
EOF
read -r -d '' SPEC_PROMPT <<'EOF' || true
Here is a review of the named spec `.joshix/specs/retry-design.md`: approved,
with no findings. Evaluate the review. Do not edit the spec.
EOF
run_codex "$TEST_PROJECT" "$SPEC_PROMPT" "$SPEC_OUTPUT" read-only "$CODEX_TEST_TIMEOUT" use-rules
SPEC_FINAL="$(cat "$SPEC_OUTPUT/final.md")"

FAILED=0
assert_contains "$DISCUSSION_FINAL" 'agree|agreed' 'discussion response states agreement' || FAILED=$((FAILED + 1))
assert_contains "$DISCUSSION_FINAL" 'automatic.*retry|retry.*automatic|retry once|one.*retry|single retry' 'discussion response states the design change' || FAILED=$((FAILED + 1))
assert_not_contains "$DISCUSSION_FINAL" '### Handled without asking|### Applied as requested|### No decision needed|### Review outcome|Rereview required|^## .+\?$|^### Choice [A-D]:' 'discussion response avoids artifact grammar and fabricated decisions' || FAILED=$((FAILED + 1))
assert_not_contains "$DISCUSSION_FINAL" '\bedited\b|\bupdated\b.*\bfiles?\b|\bchanged\b.*\bfiles?\b' 'discussion response does not claim a file edit' || FAILED=$((FAILED + 1))
assert_contains "$SPEC_FINAL" '^I.m reviewing the spec review as feedback to evaluate, not as approval to edit the spec\.$' 'named spec keeps artifact reception opening' || FAILED=$((FAILED + 1))
assert_contains "$SPEC_FINAL" 'Review outcome' 'named spec keeps artifact response grammar' || FAILED=$((FAILED + 1))

if [ "$FAILED" -ne 0 ]; then
  printf '%s\n' "$DISCUSSION_FINAL" "$SPEC_FINAL"
  echo 'STATUS: FAILED'
  exit 1
fi
echo 'STATUS: PASSED'
