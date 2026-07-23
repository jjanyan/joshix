#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

EXECUTION_DECISION_LABEL_PATTERN='EXECUTION[[:space:]]+MODE[[:space:]]*:'
EXECUTION_DECISION_LINE_PREFIX='^[[:space:]]*([[:digit:]]+[.)][[:space:]]+)?[[:space:][:punct:]]*'
EXECUTION_DECISION_INLINE_PATTERN="${EXECUTION_DECISION_LINE_PREFIX}${EXECUTION_DECISION_LABEL_PATTERN}[[:space:][:punct:]]*INLINE[[:space:][:punct:]]*;[[:space:][:punct:]]*REASON[[:space:]]*:[[:space:][:punct:]]*SHARED[[:space:]]+FILE[[:space:]]+OWNERSHIP[[:space:][:punct:]]*$"

execution_decision_matches() {
    local candidate="$1"
    local label_matches
    local decision_count
    label_matches=$(grep -Eio "$EXECUTION_DECISION_LABEL_PATTERN" \
        <<< "$candidate" || true)

    if [ -n "$label_matches" ]; then
        decision_count=$(grep -Ec '^' <<< "$label_matches")
    else
        decision_count=0
    fi

    [ "$decision_count" -eq 1 ] &&
        grep -Ei "$EXECUTION_DECISION_INLINE_PATTERN" \
            <<< "$candidate" >/dev/null
}

verify_execution_decision_oracle() {
    local correct='EXECUTION MODE: INLINE; REASON: SHARED FILE OWNERSHIP'
    local formatted='- **execution mode:** **inline**; **reason:** **shared file ownership**.'
    local ordered='1. **execution mode:** **inline**; **reason:** **shared file ownership**.'
    local warning_and_correct="warning: optional telemetry unavailable"$'\n'"${correct}"
    local duplicate="${correct}"$'\n'"${correct}"
    local mixed_format_duplicate="${correct}"$'\n'"${formatted}"
    local embedded_duplicate="${correct}"$'\n''Summary: EXECUTION MODE: INLINE; REASON: SHARED FILE OWNERSHIP'
    local embedded_conflict="${correct}"$'\n''Debug: EXECUTION MODE: PARALLEL; REASON: DISJOINT OWNERSHIP'
    local missing='Execution stayed inline because both tasks edit the same files.'
    local embedded='Summary: EXECUTION MODE: INLINE; REASON: SHARED FILE OWNERSHIP'
    local parallel='EXECUTION MODE: PARALLEL; REASON: SHARED FILE OWNERSHIP'
    local wrong_reason='EXECUTION MODE: INLINE; REASON: DISJOINT OWNERSHIP'
    local large_diagnostics='diagnostic'
    local marker_then_large
    while [ "${#large_diagnostics}" -lt 131072 ]; do
        large_diagnostics+="$large_diagnostics"
    done
    marker_then_large="${correct}"$'\n'"${large_diagnostics}"

    if ! execution_decision_matches "$correct"; then
        echo "  [FAIL] Coupled decision oracle rejected the correct decision"
        return 1
    fi

    if ! execution_decision_matches "$formatted"; then
        echo "  [FAIL] Coupled decision oracle rejected harmless formatting"
        return 1
    fi

    if ! execution_decision_matches "$ordered"; then
        echo "  [FAIL] Coupled decision oracle rejected an ordered-list marker"
        return 1
    fi

    if ! execution_decision_matches "$warning_and_correct"; then
        echo "  [FAIL] Coupled decision oracle rejected harmless warning output"
        return 1
    fi

    if ! execution_decision_matches "$marker_then_large"; then
        echo "  [FAIL] Coupled decision oracle rejected large trailing diagnostics"
        return 1
    fi

    if execution_decision_matches "$duplicate"; then
        echo "  [FAIL] Coupled decision oracle accepted duplicate markers"
        return 1
    fi

    if execution_decision_matches "$embedded_duplicate"; then
        echo "  [FAIL] Coupled decision oracle accepted an embedded duplicate"
        return 1
    fi

    if execution_decision_matches "$embedded_conflict"; then
        echo "  [FAIL] Coupled decision oracle accepted an embedded conflict"
        return 1
    fi

    if execution_decision_matches "$mixed_format_duplicate"; then
        echo "  [FAIL] Coupled decision oracle accepted mixed-format duplicates"
        return 1
    fi

    if execution_decision_matches "$missing"; then
        echo "  [FAIL] Coupled decision oracle accepted a missing marker"
        return 1
    fi

    if execution_decision_matches "$embedded"; then
        echo "  [FAIL] Coupled decision oracle accepted an embedded marker"
        return 1
    fi

    if execution_decision_matches "$parallel"; then
        echo "  [FAIL] Coupled decision oracle accepted parallel execution"
        return 1
    fi

    if execution_decision_matches "$wrong_reason"; then
        echo "  [FAIL] Coupled decision oracle accepted the wrong reason"
        return 1
    fi

    echo "  [PASS] Coupled execution decision oracle samples"
}

verify_execution_decision_oracle

if [ "${1:-}" = "--oracle-only" ]; then
    exit 0
fi

echo "=== Integration Test: coupled plan stays inline ==="

TEST_PROJECT="$(create_test_project)"
OUTPUT_FILE="$TEST_PROJECT/claude-output.txt"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

cd "$TEST_PROJECT"
mkdir -p src test .joshix/plans

cat > package.json <<'EOF'
{
  "name": "coupled-plan-test",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "test": "node --test"
  }
}
EOF

cat > src/counter.js <<'EOF'
export function identity(value) {
  return value;
}
EOF

cat > test/counter.test.js <<'EOF'
import test from 'node:test';
import assert from 'node:assert/strict';
import { identity } from '../src/counter.js';

test('identity returns its input', () => {
  assert.equal(identity(3), 3);
});
EOF

cat > .joshix/plans/implementation-plan.md <<'EOF'
# Coupled Counter Plan

### Task 1: Add increment

**Depends on:** None

**Files:**
- Modify: `src/counter.js`
- Modify: `test/counter.test.js`

Add and export `increment(value)`, returning `value + 1`. Add a Node test that
asserts `increment(3) === 4`.

Verification: `node --test test/counter.test.js`

### Task 2: Add decrement

**Depends on:** None

**Files:**
- Modify: `src/counter.js`
- Modify: `test/counter.test.js`

Add and export `decrement(value)`, returning `value - 1`. Add a Node test that
asserts `decrement(3) === 2`.

Verification: `npm test`
EOF

git init --quiet
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial commit" --quiet

PROMPT="Execute the already approved plan at .joshix/plans/implementation-plan.md. Work in the current checkout and branch. Do not stage or commit. The plan is small; choose the repository's appropriate execution route.

Your final response must contain exactly one line and no other prose. Use this
neutral decision format, choosing one value from each bracket based on the
plan's actual ownership:
EXECUTION MODE: <INLINE or PARALLEL>; REASON: <SHARED FILE OWNERSHIP or DISJOINT OWNERSHIP>"

# 1680s leaves 120s of headroom under the runner's 1800s integration timeout.
if ! run_claude_stream "$PROMPT" 1680 "$OUTPUT_FILE" \
    --allowed-tools=all --permission-mode bypassPermissions; then
    echo "STATUS: FAILED"
    exit 1
fi

TEST_PROJECT_REAL=$(cd "$TEST_PROJECT" && pwd -P)
SESSION_DIR="$HOME/.claude/projects/$(echo "$TEST_PROJECT_REAL" | sed 's|[^a-zA-Z0-9]|-|g')"
SESSION_FILE=$(ls -t "$SESSION_DIR"/*.jsonl 2>/dev/null | head -1 || true)
FAILED=0

if [ -z "$SESSION_FILE" ]; then
    echo "  [FAIL] Could not find Claude session transcript"
    FAILED=$((FAILED + 1))
elif python3 "$SCRIPT_DIR/assert-parallel-transcript.py" \
    "$SESSION_FILE" coupled; then
    echo "  [PASS] No Agent/Task call was dispatched"
else
    echo "  [FAIL] Coupled work dispatched an Agent/Task call"
    FAILED=$((FAILED + 1))
fi

if npm test > test-output.txt 2>&1; then
    echo "  [PASS] Counter tests pass"
else
    echo "  [FAIL] Counter tests failed"
    cat test-output.txt
    FAILED=$((FAILED + 1))
fi

if grep -q 'export function increment' src/counter.js &&
   grep -q 'export function decrement' src/counter.js; then
    echo "  [PASS] Both coupled operations were implemented"
else
    echo "  [FAIL] Coupled operations are incomplete"
    FAILED=$((FAILED + 1))
fi

if execution_decision_matches "$(cat "$OUTPUT_FILE")"; then
    echo "  [PASS] Final response records the inline shared-ownership decision"
else
    echo "  [FAIL] Final response is not the single required inline decision"
    FAILED=$((FAILED + 1))
fi

if grep -Fq '```mermaid' "$OUTPUT_FILE" ||
   grep -Eiq \
     '^[[:space:]]*(Parallel lanes|Expected critical path|Expected peak concurrency|What actually overlapped|Actual critical path|Serial waits|Topology variance):' \
     "$OUTPUT_FILE"; then
    echo "  [FAIL] Coupled execution emitted parallel topology overhead"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] Coupled execution emitted no parallel topology claim"
fi

commit_count=$(git -C "$TEST_PROJECT" log --oneline | wc -l)
if [ "$commit_count" -ne 1 ]; then
    echo "  [FAIL] Unexpected commit created"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] No extra commits created"
fi

if [ "$FAILED" -eq 0 ]; then
    echo "STATUS: PASSED"
    exit 0
fi

echo "STATUS: FAILED"
echo "Output: $OUTPUT_FILE"
exit 1
