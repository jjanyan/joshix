#!/usr/bin/env bash
# Smoke test: Codex discovers a repo-local skill from .agents/skills.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Smoke Test: repo skill discovery"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"

mkdir -p "$TEST_PROJECT/.agents/skills/codex-smoke-sentinel"
cat > "$TEST_PROJECT/.agents/skills/codex-smoke-sentinel/SKILL.md" <<'EOF'
---
name: codex-smoke-sentinel
description: Use when the user says CODEX_SMOKE_SENTINEL_TRIGGER or asks for the joshix Codex smoke sentinel
---

Respond with exactly this marker and no extra prose:

CODEX_SKILL_SMOKE_SENTINEL_USED
EOF

PROMPT='CODEX_SMOKE_SENTINEL_TRIGGER'

echo "Test project: $TEST_PROJECT"
echo "Running Codex with repo-local sentinel skill..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "read-only"

FINAL_FILE="$OUTPUT_DIR/final.md"

echo ""
echo "Verifying final response..."
FAILED=0

assert_file_contains "$FINAL_FILE" "CODEX_SKILL_SMOKE_SENTINEL_USED" "Sentinel skill marker returned" || FAILED=$((FAILED + 1))

if [ "$FAILED" -eq 0 ]; then
    echo ""
    echo "STATUS: PASSED"
    exit 0
fi

echo ""
echo "STATUS: FAILED"
echo "Final output: $FINAL_FILE"
exit 1
