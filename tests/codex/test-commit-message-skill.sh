#!/usr/bin/env bash
# Behavior test: joshix commit-message skill drafts from staged changes only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: commit-message"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

mkdir -p "$TEST_PROJECT/src" "$TEST_PROJECT/docs"
cat > "$TEST_PROJECT/src/login.js" <<'EOF'
export function login(email, password) {
  return { email, password };
}
EOF
cat > "$TEST_PROJECT/docs/deploy.md" <<'EOF'
# Deploy

Run the deploy script.
EOF

git -C "$TEST_PROJECT" add src/login.js docs/deploy.md
git -C "$TEST_PROJECT" commit --quiet -m "Add login and deploy docs"

cat > "$TEST_PROJECT/src/login.js" <<'EOF'
export function login(email, password, rememberMe = false) {
  return { email, password, rememberMe };
}
EOF
git -C "$TEST_PROJECT" add src/login.js

cat > "$TEST_PROJECT/docs/deploy.md" <<'EOF'
# Deploy

Run the deploy script after setting DEPLOY_TOKEN.
EOF

read -r -d '' PROMPT <<'EOF' || true
Use the joshix:commit-message skill to draft a commit message for my staged changes.
EOF

echo "Test project: $TEST_PROJECT"
echo "Running Codex commit-message request..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "read-only"

FINAL_FILE="$OUTPUT_DIR/final.md"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"

echo ""
echo "Verifying commit-message behavior..."
FAILED=0

assert_contains "$FINAL_OUTPUT" '```text' "Returns fenced text block" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "Why:" "Includes Why label" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "What:" "Includes What label" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "Risk:" "Includes Risk label" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "remember|login" "Summarizes staged login change" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "DEPLOY_TOKEN|deploy script|deploy docs|docs/deploy" "Ignores unstaged deploy docs change" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "git add|git commit|staged the|committed" "Does not mutate git state or claim mutation" || FAILED=$((FAILED + 1))

if git -C "$TEST_PROJECT" diff --cached --quiet -- src/login.js; then
    echo "  [FAIL] Staged login change disappeared"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] Staged login change preserved"
fi

if git -C "$TEST_PROJECT" diff --quiet -- docs/deploy.md; then
    echo "  [FAIL] Unstaged docs change disappeared"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] Unstaged docs change preserved"
fi

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
