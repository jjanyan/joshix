#!/usr/bin/env bash
# Behavior test: joshix code-review skill reviews current changes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: code-review"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

mkdir -p "$TEST_PROJECT/src"
cat > "$TEST_PROJECT/src/auth.js" <<'EOF'
export function findUserByEmail(db, email) {
  return db.query("select * from users where email = ?", [email]);
}
EOF

git -C "$TEST_PROJECT" add src/auth.js
git -C "$TEST_PROJECT" commit --quiet -m "Add auth lookup"

cat > "$TEST_PROJECT/src/auth.js" <<'EOF'
export function findUserByEmail(db, email) {
  return db.query(`select * from users where email = '${email}'`);
}
EOF

STATUS_BEFORE="$(git -C "$TEST_PROJECT" status --porcelain -- src)"

read -r -d '' PROMPT <<'EOF' || true
Use the joshix:code-review skill to review my current changes.
EOF

echo "Test project: $TEST_PROJECT"
echo "Running Codex code-review request..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "read-only"

FINAL_FILE="$OUTPUT_DIR/final.md"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"
STATUS_AFTER="$(git -C "$TEST_PROJECT" status --porcelain -- src)"

echo ""
echo "Verifying code-review behavior..."
FAILED=0

assert_contains "$FINAL_OUTPUT" "using joshix:code-review|joshix code review" "Announces joshix code-review skill" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "# Code Review|Code Review" "Uses code review report format" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "src/auth\\.js|auth\\.js" "References reviewed file" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "SQL injection|injection|parameterized|template literal" "Flags SQL injection risk" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "Critical|Important" "Classifies finding severity" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "output/events|output/stderr|generated/session logs" "Ignores generated harness logs" || FAILED=$((FAILED + 1))

critical_line="$(grep -n "## Critical" "$FINAL_FILE" | head -1 | cut -d: -f1 || true)"
summary_line="$(grep -n "## Summary" "$FINAL_FILE" | head -1 | cut -d: -f1 || true)"
if [ -n "$critical_line" ] && [ -n "$summary_line" ] && [ "$critical_line" -lt "$summary_line" ]; then
    echo "  [PASS] Findings appear before summary"
else
    echo "  [FAIL] Findings should appear before summary"
    echo "  Critical line: ${critical_line:-missing}"
    echo "  Summary line: ${summary_line:-missing}"
    FAILED=$((FAILED + 1))
fi

if [ "$STATUS_AFTER" = "$STATUS_BEFORE" ]; then
    echo "  [PASS] Code review did not edit files"
else
    echo "  [FAIL] Git status changed during review"
    echo "  Before:"
    printf '%s\n' "$STATUS_BEFORE" | sed 's/^/    /'
    echo "  After:"
    printf '%s\n' "$STATUS_AFTER" | sed 's/^/    /'
    FAILED=$((FAILED + 1))
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
