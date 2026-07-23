#!/usr/bin/env bash
# Integration Test: subagent-driven-development workflow
# Executes a disjoint plan and verifies real implementation overlap and review order
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

OVERLAP_DECISION_LABEL_PATTERN='OVERLAP[[:space:]]+OBSERVED[[:space:]]*:'
OVERLAP_DECISION_LINE_PREFIX='^[[:space:]]*([[:digit:]]+[.)][[:space:]]+)?[[:space:][:punct:]]*'
OVERLAP_DECISION_AFFIRMATIVE_PATTERN="${OVERLAP_DECISION_LINE_PREFIX}${OVERLAP_DECISION_LABEL_PATTERN}[[:space:][:punct:]]*TASKS[[:space:][:punct:]]+1[[:space:][:punct:]]+AND[[:space:][:punct:]]+2[[:space:][:punct:]]*$"

overlap_decision_matches() {
    local candidate="$1"
    local label_matches
    local decision_count
    label_matches=$(grep -Eio "$OVERLAP_DECISION_LABEL_PATTERN" \
        <<< "$candidate" || true)

    if [ -n "$label_matches" ]; then
        decision_count=$(grep -Ec '^' <<< "$label_matches")
    else
        decision_count=0
    fi

    [ "$decision_count" -eq 1 ] &&
        grep -Ei "$OVERLAP_DECISION_AFFIRMATIVE_PATTERN" \
            <<< "$candidate" >/dev/null
}

verify_overlap_decision_oracle() {
    local correct='OVERLAP OBSERVED: TASKS 1 AND 2'
    local formatted='- **overlap observed:** **tasks  1 and 2**.'
    local ordered='1. **overlap observed:** **tasks  1 and 2**.'
    local none='OVERLAP OBSERVED: NONE'
    local duplicate="${correct}"$'\n'"${correct}"
    local conflicting="${correct}"$'\n'"${none}"
    local embedded_duplicate="${correct}"$'\n''Summary: OVERLAP OBSERVED: TASKS 1 AND 2'
    local embedded_conflict="${correct}"$'\n''Debug: OVERLAP OBSERVED: NONE'
    local unrelated='Summary: OVERLAP OBSERVED: TASKS 1 AND 2'
    local large_diagnostics='diagnostic'
    local marker_then_large
    while [ "${#large_diagnostics}" -lt 131072 ]; do
        large_diagnostics+="$large_diagnostics"
    done
    marker_then_large="${correct}"$'\n'"${large_diagnostics}"

    if ! overlap_decision_matches "$correct"; then
        echo "  [FAIL] Overlap decision oracle rejected the correct decision"
        return 1
    fi

    if ! overlap_decision_matches "$ordered"; then
        echo "  [FAIL] Overlap decision oracle rejected an ordered-list marker"
        return 1
    fi

    if ! overlap_decision_matches "$marker_then_large"; then
        echo "  [FAIL] Overlap decision oracle rejected large trailing diagnostics"
        return 1
    fi

    if ! overlap_decision_matches "$formatted"; then
        echo "  [FAIL] Overlap decision oracle rejected harmless formatting"
        return 1
    fi

    if overlap_decision_matches "$embedded_duplicate"; then
        echo "  [FAIL] Overlap decision oracle accepted an embedded duplicate"
        return 1
    fi

    if overlap_decision_matches "$embedded_conflict"; then
        echo "  [FAIL] Overlap decision oracle accepted an embedded conflict"
        return 1
    fi

    if overlap_decision_matches "$none"; then
        echo "  [FAIL] Overlap decision oracle accepted NONE"
        return 1
    fi

    if overlap_decision_matches "$duplicate"; then
        echo "  [FAIL] Overlap decision oracle accepted duplicate markers"
        return 1
    fi

    if overlap_decision_matches "$conflicting"; then
        echo "  [FAIL] Overlap decision oracle accepted conflicting markers"
        return 1
    fi

    if overlap_decision_matches "$unrelated"; then
        echo "  [FAIL] Overlap decision oracle accepted unrelated prose"
        return 1
    fi

    echo "  [PASS] Overlap decision oracle samples"
}

verify_overlap_decision_oracle

if [ "${1:-}" = "--oracle-only" ]; then
    exit 0
fi

echo "========================================"
echo " Integration Test: subagent-driven-development"
echo "========================================"
echo ""
echo "This test executes a real plan using the skill and verifies:"
echo "  1. The skill is invoked"
echo "  2. Independent implementers actually overlap"
echo "  3. Each lane completes spec review before quality review starts"
echo "  4. A working integrated implementation is produced"
echo "  5. Work remains in the current checkout without extra commits"
echo "  6. The final report names observed overlap and includes Mermaid"
echo ""
echo "WARNING: This test may take 10-30 minutes to complete."
echo ""

TEST_PROJECT=$(create_test_project)
echo "Test project: $TEST_PROJECT"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

cd "$TEST_PROJECT"

cat > package.json <<'EOF'
{
  "name": "test-project",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "test": "node --test"
  }
}
EOF

mkdir -p src test .joshix/plans

cat > .joshix/plans/implementation-plan.md <<'EOF'
# Parallel Fixture Implementation Plan

### Task 1: Add operation

**Depends on:** None

**Files:**
- Create: `src/add.js`
- Create: `test/add.test.js`

Create `src/add.js`:

```javascript
export function add(a, b) {
  return a + b;
}
```

Create `test/add.test.js`:

```javascript
import test from 'node:test';
import assert from 'node:assert/strict';
import { add } from '../src/add.js';

test('add returns the sum', () => {
  assert.equal(add(2, 3), 5);
  assert.equal(add(-1, 1), 0);
});
```

Focused verification: `node --test test/add.test.js`

### Task 2: Multiply operation

**Depends on:** None

**Files:**
- Create: `src/multiply.js`
- Create: `test/multiply.test.js`

Create `src/multiply.js`:

```javascript
export function multiply(a, b) {
  return a * b;
}
```

Create `test/multiply.test.js`:

```javascript
import test from 'node:test';
import assert from 'node:assert/strict';
import { multiply } from '../src/multiply.js';

test('multiply returns the product', () => {
  assert.equal(multiply(2, 3), 6);
  assert.equal(multiply(-2, 3), -6);
});
```

Focused verification: `node --test test/multiply.test.js`

### Task 3: Public module integration

**Depends on:** Tasks 1, 2

**Files:**
- Create: `src/index.js`
- Create: `test/index.test.js`

Create `src/index.js`:

```javascript
export { add } from './add.js';
export { multiply } from './multiply.js';
```

Create `test/index.test.js`:

```javascript
import test from 'node:test';
import assert from 'node:assert/strict';
import { add, multiply } from '../src/index.js';

test('public module exports both operations', () => {
  assert.equal(add(4, 5), 9);
  assert.equal(multiply(4, 5), 20);
});
```

Verification: `npm test`
EOF

git init --quiet
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial commit" --quiet

echo ""
echo "Project setup complete. Starting execution..."
echo ""

OUTPUT_FILE="$TEST_PROJECT/claude-output.txt"

PROMPT="Execute the implementation plan at .joshix/plans/implementation-plan.md using the ${CLAUDE_PLUGIN_NAME}:subagent-driven-development skill.

IMPORTANT: Follow the skill exactly. I will be verifying that you:
1. Read the plan once at the beginning
2. Provide full task text to subagents (don't make them read files)
3. Dispatch the two independent implementation lanes so they overlap
4. Run spec compliance review before code quality review within each lane
5. Respect Task 3's dependencies before integrating
6. Do not stage or commit; leave implementation as working tree changes
7. Report what actually overlapped and include the final Mermaid topology
8. Require each spec reviewer to end with exactly one line: SPEC OUTCOME: <PASS or FAIL>
9. Require each quality reviewer to end with exactly one line: QUALITY OUTCOME: <APPROVED or CHANGES REQUIRED>
10. Include exactly one final decision line: OVERLAP OBSERVED: <TASKS 1 AND 2 or NONE>

Choose the decision value from the execution evidence. Do not repeat the
OVERLAP OBSERVED marker elsewhere in the final response.

Work in the current checkout and branch. Begin now. Execute the plan."

echo "Running Claude (plugin-dir: $CLAUDE_PLUGIN_DIR, cwd: $TEST_PROJECT)..."
echo "================================================================================"
cd "$TEST_PROJECT"
# 1680s leaves 120s of headroom under the runner's 1800s integration timeout.
if ! run_claude_stream "$PROMPT" 1680 "$OUTPUT_FILE" \
    --allowed-tools=all --permission-mode bypassPermissions; then
    echo ""
    echo "================================================================================"
    echo "EXECUTION FAILED"
    exit 1
fi
echo "================================================================================"

echo ""
echo "Execution complete. Analyzing results..."
echo ""

TEST_PROJECT_REAL=$(cd "$TEST_PROJECT" && pwd -P)
SESSION_DIR="$HOME/.claude/projects/$(echo "$TEST_PROJECT_REAL" | sed 's|[^a-zA-Z0-9]|-|g')"
SESSION_FILE=$(ls -t "$SESSION_DIR"/*.jsonl 2>/dev/null | head -1 || true)

if [ -z "$SESSION_FILE" ]; then
    echo "ERROR: Could not find session transcript file"
    echo "Looked in: $SESSION_DIR"
    exit 1
fi

echo "Analyzing session transcript: $(basename "$SESSION_FILE")"
echo ""

FAILED=0

echo "=== Verification Tests ==="
echo ""

if grep -q "\"skill\":\"${CLAUDE_PLUGIN_NAME}:subagent-driven-development\"" \
    "$SESSION_FILE"; then
    echo "  [PASS] subagent-driven-development skill was invoked"
else
    echo "  [FAIL] Skill was not invoked"
    FAILED=$((FAILED + 1))
fi

# Task tracking: older harnesses expose TodoWrite; Claude Code >= 2.1 uses
# TaskCreate/TaskUpdate instead.
todo_count=$(grep -cE '"name":"(TodoWrite|TaskCreate|TaskUpdate)"' "$SESSION_FILE" || true)
if [ "$todo_count" -ge 1 ]; then
    echo "  [PASS] Task tracking used $todo_count time(s)"
else
    echo "  [INFO] No task tracking tool observed; this harness may expose task tools only on demand"
fi

if python3 "$SCRIPT_DIR/assert-parallel-transcript.py" \
    "$SESSION_FILE" independent; then
    echo "  [PASS] Implementers overlapped; lane and whole-change reviews stayed ordered"
else
    echo "  [FAIL] Transcript did not prove overlap and required review order"
    FAILED=$((FAILED + 1))
fi

for path in \
    src/add.js \
    test/add.test.js \
    src/multiply.js \
    test/multiply.test.js \
    src/index.js \
    test/index.test.js; do
    if [ -f "$TEST_PROJECT/$path" ]; then
        echo "  [PASS] $path exists"
    else
        echo "  [FAIL] $path was not created"
        FAILED=$((FAILED + 1))
    fi
done

if grep -Fq "export { add } from './add.js';" "$TEST_PROJECT/src/index.js" &&
   grep -Fq "export { multiply } from './multiply.js';" \
     "$TEST_PROJECT/src/index.js"; then
    echo "  [PASS] Public module exports both operations"
else
    echo "  [FAIL] Public module exports are incomplete"
    FAILED=$((FAILED + 1))
fi

if cd "$TEST_PROJECT" && npm test > test-output.txt 2>&1; then
    echo "  [PASS] Tests pass"
else
    echo "  [FAIL] Tests failed"
    cat test-output.txt
    FAILED=$((FAILED + 1))
fi

if overlap_decision_matches "$(cat "$OUTPUT_FILE")"; then
    echo "  [PASS] Final response records overlap for Tasks 1 and 2"
else
    echo "  [FAIL] Final response has no single affirmative overlap decision"
    FAILED=$((FAILED + 1))
fi

if grep -Fq '```mermaid' "$OUTPUT_FILE"; then
    echo "  [PASS] Final response includes Mermaid source"
else
    echo "  [FAIL] Final response does not include Mermaid source"
    FAILED=$((FAILED + 1))
fi

commit_count=$(git -C "$TEST_PROJECT" log --oneline | wc -l)
if [ "$commit_count" -eq 1 ]; then
    echo "  [PASS] No extra commits created"
else
    echo "  [FAIL] Unexpected commits created ($commit_count total, expected 1)"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "========================================="
echo " Token Usage Analysis"
echo "========================================="
echo ""
python3 "$SCRIPT_DIR/analyze-token-usage.py" "$SESSION_FILE"
echo ""

echo "========================================"
echo " Test Summary"
echo "========================================"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo "STATUS: PASSED"
    echo "All verification tests passed!"
    exit 0
fi

echo "STATUS: FAILED"
echo "Failed $FAILED verification tests"
echo "Output saved to: $OUTPUT_FILE"
exit 1
