#!/usr/bin/env bash
# Behavior test: pasted spec reviews are evaluated, not applied.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: receiving-spec-review"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"
cp "$CODEX_REPO_ROOT/AGENTS.md" "$TEST_PROJECT/AGENTS.md"

mkdir -p "$TEST_PROJECT/.joshix/specs"
cat > "$TEST_PROJECT/.joshix/specs/workspace-access-design.md" <<'EOF'
# Workspace Access Design

## Requirements

- Guests may view public workspaces.
- Failed invitations retry at most three times.

## Access Rules

- Only signed-in members may view any workspace.
EOF

git -C "$TEST_PROJECT" add AGENTS.md .joshix/specs/workspace-access-design.md
git -C "$TEST_PROJECT" commit --quiet -m 'Add workspace access design'

read -r -d '' PROMPT <<'EOF' || true
Here is a spec review from another agent. What do you think?

1. The spec contradicts itself: guests may view public workspaces, but the
   access rules say only signed-in members may view any workspace.
2. The spec never limits failed invitation retries.
3. Rename Access Rules to Authorization Rules because it sounds better.

Evaluate the review against .joshix/specs/workspace-access-design.md. Do not
edit the spec unless I explicitly ask you to.
EOF

echo "Test project: $TEST_PROJECT"
echo "Running Codex with workspace-write so accidental edits are observable..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"

FINAL_FILE="$OUTPUT_DIR/final.md"
EVENTS_FILE="$OUTPUT_DIR/events.jsonl"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"
FIRST_NONEMPTY_LINE="$(first_nonempty_trimmed_line < "$FINAL_FILE")"
FIRST_AGENT_MESSAGE="$(jq -rs 'map(select(.type == "item.completed" and .item.type == "agent_message"))[0].item.text // ""' "$EVENTS_FILE")"
FIRST_AGENT_LINE="$(printf '%s\n' "$FIRST_AGENT_MESSAGE" | first_nonempty_trimmed_line)"
COMPACT_ITEM='^[[:space:]]*-[[:space:]]+\*\*[^*]+ — (VALID|REJECT|DEFER)( · (CRITICAL|IMPORTANT|MINOR))?\*\* — .+'

echo ""
echo "Verifying spec review-review behavior..."
FAILED=0

if [ "$FIRST_AGENT_LINE" = "I'm reviewing the spec review as feedback to evaluate, not as approval to edit the spec." ]; then
  echo "  [PASS] Emits the exact spec-review mode sentence first"
else
  echo "  [FAIL] Expected first emitted agent sentence to be the exact spec-review mode sentence"
  echo "  Actual: ${FIRST_AGENT_LINE:-<empty>}"
  FAILED=$((FAILED + 1))
fi
if [ "$FIRST_NONEMPTY_LINE" = "I'm reviewing the spec review as feedback to evaluate, not as approval to edit the spec." ]; then
  echo "  [PASS] Uses the exact spec-review mode sentence as the first non-empty line"
else
  echo "  [FAIL] Expected exact spec-review mode sentence as the first non-empty line"
  echo "  Actual: ${FIRST_NONEMPTY_LINE:-<empty>}"
  FAILED=$((FAILED + 1))
fi
assert_contains "$FINAL_OUTPUT" 'No decision needed.*no changes made' 'Uses review-only heading' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "$COMPACT_ITEM" 'Uses complete compact item lines' || FAILED=$((FAILED + 1))
if validate_compact_bounds "$FINAL_OUTPUT" 3; then
  echo '  [PASS] Keeps all compact items within shorthand and reason bounds'
else
    echo '  [FAIL] Expected at least three compact items with unique normalized 1-5-word shorthand and reasons of at most 40 words'
  FAILED=$((FAILED + 1))
fi
assert_contains "$FINAL_OUTPUT" '^[[:space:]]*-[[:space:]]+\*\*[^*]+ — VALID( · (CRITICAL|IMPORTANT|MINOR))?\*\* — .*(guest|public).*(signed|member|contradict)' 'Accepts the guest access contradiction' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" '^[[:space:]]*-[[:space:]]+\*\*[^*]+ — REJECT\*\* — .*(((three|3).*(retr|limit|already))|((retr|limit|already).*(three|3)))' 'Rejects the false unlimited-retry claim' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" '^[[:space:]]*-[[:space:]]+\*\*[^*]+ — DEFER\*\* — .*(Access|Authorization|heading|name|naming|style|taste)' 'Defers the heading preference' || FAILED=$((FAILED + 1))
assert_git_path_clean "$TEST_PROJECT" ".joshix/specs" "Does not edit spec files" || FAILED=$((FAILED + 1))

if [ "$FAILED" -eq 0 ]; then
  echo ""
  echo "STATUS: PASSED"
  exit 0
fi

echo ""
echo "STATUS: FAILED"
echo "Final output: $FINAL_FILE"
echo "Events: $OUTPUT_DIR/events.jsonl"
echo "stderr: $OUTPUT_DIR/stderr.txt"
exit 1
