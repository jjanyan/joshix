#!/usr/bin/env bash
# Behavior test: pasted reviews are evaluated, not implemented.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: receiving-code-review"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"
cp "$CODEX_REPO_ROOT/AGENTS.md" "$TEST_PROJECT/AGENTS.md"

mkdir -p "$TEST_PROJECT/src"
cat > "$TEST_PROJECT/src/users.js" <<'EOF'
export function getDisplayName(user) {
  if (!user || typeof user.name !== "string") {
    return "Anonymous";
  }

  return user.name.trim() || "Anonymous";
}

export function canViewAdminPanel(user) {
  return Boolean(user && user.role === "admin" && user.active === true);
}

export function canEditUsers(user) {
  return Boolean(user && user.active === true && (user.role === "admin" || "owner"));
}
EOF

git -C "$TEST_PROJECT" add AGENTS.md src/users.js
git -C "$TEST_PROJECT" commit --quiet -m "Add user helpers"

read -r -d '' PROMPT <<'EOF' || true
Here is a code review from another agent. What do you think?

Code review:

1. Important: `canEditUsers` allows every active user to edit users because the literal `"owner"` makes the role expression truthy. Require an active admin or active owner explicitly.
2. Critical: `canViewAdminPanel` allows inactive admins into the admin panel because it only checks `role === "admin"`.
3. Minor: Rename `getDisplayName` to `displayName` because shorter function names are cleaner.

Please evaluate the review against the current repository.
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
echo "Verifying review-review behavior..."
FAILED=0

if [ "$FIRST_AGENT_LINE" = "I'm reviewing the review as feedback to evaluate, not as approval to edit files." ]; then
    echo "  [PASS] Emits the exact mode sentence first"
else
    echo "  [FAIL] Expected first emitted agent sentence to be the exact mode sentence"
    echo "  Actual: ${FIRST_AGENT_LINE:-<empty>}"
    FAILED=$((FAILED + 1))
fi
if [ "$FIRST_NONEMPTY_LINE" = "I'm reviewing the review as feedback to evaluate, not as approval to edit files." ]; then
    echo "  [PASS] Uses the exact mode sentence as the first non-empty line"
else
    echo "  [FAIL] Expected exact mode sentence as the first non-empty line"
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
assert_contains "$FINAL_OUTPUT" '^[[:space:]]*-[[:space:]]+\*\*[^*]+ — REJECT\*\* — .*(((active|inactive).*(check|true|already))|((check|true|already).*(active|inactive)))' 'Rejects false admin finding with evidence' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" '^[[:space:]]*-[[:space:]]+\*\*[^*]+ — VALID( · (CRITICAL|IMPORTANT|MINOR))?\*\* — .*(role|truthy|owner)' 'Accepts objective role bug with evidence' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" '^[[:space:]]*-[[:space:]]+\*\*[^*]+ — DEFER\*\* — .*(name|naming|shorter|style|taste)' 'Defers code naming preference' || FAILED=$((FAILED + 1))
assert_git_path_clean "$TEST_PROJECT" "src" "Does not edit source files" || FAILED=$((FAILED + 1))

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
