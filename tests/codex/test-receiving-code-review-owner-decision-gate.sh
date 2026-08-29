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
CONTRACT_FILE="$CODEX_REPO_ROOT/skills/using-joshix/references/review-reception-contract.md"
FORMAT_FILE="$CODEX_REPO_ROOT/skills/using-joshix/references/review-response-format.md"

FAILED=0

assert_file_contains "$SKILL_FILE" "Owner Decision Gate" "Defines an explicit owner decision gate" || FAILED=$((FAILED + 1))
assert_file_contains "$SKILL_FILE" "review-reception-contract\.md" "Links the canonical decision table" || FAILED=$((FAILED + 1))
assert_file_contains "$CONTRACT_FILE" "Agent 2 finding is verified and objective" "Separates objective findings from decision items" || FAILED=$((FAILED + 1))
assert_file_contains "$SKILL_FILE" "Product/owner decisions" "Names product and owner decisions" || FAILED=$((FAILED + 1))
assert_file_contains "$SKILL_FILE" "Architecture decisions" "Names new architecture decisions" || FAILED=$((FAILED + 1))
assert_file_contains "$CONTRACT_FILE" "leave the gated item unchanged, then ask exactly one owner question" "Blocks the gated item until owner answers" || FAILED=$((FAILED + 1))
assert_file_contains "$FORMAT_FILE" "exactly one recommended option" "Requires an owner question with a recommendation" || FAILED=$((FAILED + 1))
assert_file_contains "$SKILL_FILE" "using-joshix/references/review-response-format\.md" "Links the canonical receiver response format" || FAILED=$((FAILED + 1))

if [ "$FAILED" -eq 0 ]; then
    echo ""
    echo "STATUS: PASSED"
    exit 0
fi

echo ""
echo "STATUS: FAILED"
exit 1
