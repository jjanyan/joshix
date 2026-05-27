#!/usr/bin/env bash
# Static regression: receiving-code-review must stop before product/owner or
# new architecture decisions raised by review feedback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Static Test: receiving-code-review owner gate"
echo "========================================"
echo ""

SKILL_FILE="$CODEX_REPO_ROOT/skills/receiving-code-review/SKILL.md"

FAILED=0

assert_file_contains "$SKILL_FILE" "Owner Decision Gate" "Defines an explicit owner decision gate" || FAILED=$((FAILED + 1))
assert_file_contains "$SKILL_FILE" "Objective fixes" "Separates objective fixes from decision items" || FAILED=$((FAILED + 1))
assert_file_contains "$SKILL_FILE" "Product/owner decisions" "Names product and owner decisions" || FAILED=$((FAILED + 1))
assert_file_contains "$SKILL_FILE" "Architecture decisions" "Names new architecture decisions" || FAILED=$((FAILED + 1))
assert_file_contains "$SKILL_FILE" "Do not edit.*until the owner answers|must ask.*before editing" "Blocks edits until owner answers" || FAILED=$((FAILED + 1))
assert_file_contains "$SKILL_FILE" "question.*recommendation|recommendation.*question" "Requires a question with a recommendation" || FAILED=$((FAILED + 1))

if [ "$FAILED" -eq 0 ]; then
    echo ""
    echo "STATUS: PASSED"
    exit 0
fi

echo ""
echo "STATUS: FAILED"
exit 1
