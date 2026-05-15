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

mkdir -p "$TEST_PROJECT/src"
cat > "$TEST_PROJECT/src/users.js" <<'EOF'
export function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

export function getDisplayName(user) {
  if (!user || typeof user.name !== "string") {
    return "Anonymous";
  }

  return user.name.trim() || "Anonymous";
}

export function canViewAdminPanel(user) {
  return Boolean(user && user.role === "admin" && user.active === true);
}
EOF

git -C "$TEST_PROJECT" add src/users.js
git -C "$TEST_PROJECT" commit --quiet -m "Add user helpers"

read -r -d '' PROMPT <<'EOF' || true
Here is a code review from another agent. What do you think?

Code review:

1. Important: `normalizeEmail` will throw when `email` is null or not a string. Add input validation or document the contract.
2. Critical: `canViewAdminPanel` allows inactive admins into the admin panel because it only checks `role === "admin"`.
3. Minor: Rename `getDisplayName` to `displayName` because shorter function names are cleaner.

Please evaluate the review against the current repository.
EOF

echo "Test project: $TEST_PROJECT"
echo "Running Codex with workspace-write so accidental edits are observable..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "workspace-write"

FINAL_FILE="$OUTPUT_DIR/final.md"
EVENTS_FILE="$OUTPUT_DIR/events.jsonl"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"
EARLY_AGENT_MESSAGES="$(
    jq -r 'select(.type == "item.completed" and .item.type == "agent_message") | .item.text | gsub("\n"; " ")' "$EVENTS_FILE" \
        | head -2 \
        | tr '\n' ' '
)"
FINAL_ONE_LINE="$(printf '%s\n' "$FINAL_OUTPUT" | tr '\n' ' ')"

echo ""
echo "Verifying review-review behavior..."
FAILED=0

assert_contains "$EARLY_AGENT_MESSAGES" "reviewing (the )?review|review-review|reviewing this review" "Immediately announces review-review mode" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "normalizeEmail" "Evaluates normalizeEmail item" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "canViewAdminPanel" "Evaluates canViewAdminPanel item" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "getDisplayName|displayName" "Evaluates naming item" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "valid|invalid|needs investigation|needs clarification|already handled|optional|taste" "Classifies at least one item" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_ONE_LINE" "canViewAdminPanel.*(invalid|incorrect|not valid|wrong|false positive|already handled|does check active|active === true)" "Rejects false admin-panel finding with code evidence" || FAILED=$((FAILED + 1))
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
