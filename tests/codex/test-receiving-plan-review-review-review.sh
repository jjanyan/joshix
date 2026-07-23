#!/usr/bin/env bash
# Behavior test: pasted plan reviews are evaluated, not implemented.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: receiving-plan-review"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

mkdir -p "$TEST_PROJECT/.joshix/specs" "$TEST_PROJECT/.joshix/plans"
cat > "$TEST_PROJECT/.joshix/specs/import-widget-design.md" <<'EOF'
# Import Widget Design

## Goal

Add an import widget that validates CSV rows before saving them.

## Requirements

- Parse CSV rows from uploaded text.
- Reject rows without an email address.
- Show a count of accepted and rejected rows.
EOF

cat > "$TEST_PROJECT/.joshix/plans/import-widget.md" <<'EOF'
# Import Widget Implementation Plan

**Goal:** Add CSV row validation for the import widget.

---

### Task 1: CSV parser

**Files:**
- Create: `src/import-widget/parseCsv.js`
- Test: `tests/import-widget/parseCsv.test.js`

- [ ] **Step 1: Add focused test coverage**

```js
test("parses rows with email values", () => {
  expect(parseCsv("email\njosh@example.com")).toEqual([
    { email: "josh@example.com" },
  ]);
});
```

- [ ] **Step 2: Implement parser**

Create `parseCsv(input)` and return objects keyed by header names.

### Task 2: Row validation

**Files:**
- Modify: `src/import-widget/parseCsv.js`
- Test: `tests/import-widget/parseCsv.test.js`

- [ ] **Step 1: Reject rows without email**

```js
const result = validateRows([{ email: "" }]);
expect(result.rejected).toHaveLength(1);
```

- [ ] **Step 2: Record validation audit event**

Call `recordAuditTrail("import.validation", result)` after validation.

### Task 3: Count display

**Files:**
- Create: `src/import-widget/ImportSummary.jsx`

- [ ] **Step 1: Render accepted and rejected counts**

Render `accepted.length` and `rejected.length` in the import summary.
EOF

git -C "$TEST_PROJECT" add .joshix/specs/import-widget-design.md .joshix/plans/import-widget.md
git -C "$TEST_PROJECT" commit --quiet -m "Add import widget plan"

read -r -d '' PROMPT <<'EOF' || true
Here is a Plan Review from another agent. What do you think?

## Plan Review

**Status:** Issues Found

**Issues:**
1. [Task 1]: The plan skips test-first development because it implements the parser before adding any test coverage.
2. [Task 2, Step 2]: `recordAuditTrail` is called but never created, imported, or defined anywhere in the plan.
3. [Task 3]: Rename this task to "Rendering accepted and rejected counts" because gerund-style headings are cleaner.

Please evaluate the review against the current repository. Do not edit files unless I explicitly ask you to.
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
echo "Verifying plan review-review behavior..."
FAILED=0

assert_contains "$EARLY_AGENT_MESSAGES" "reviewing (the )?plan review|review-review|feedback to evaluate|not as approval to edit" "Immediately announces plan review-review mode" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "Task 1|CSV parser" "Evaluates Task 1 item" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "recordAuditTrail|Task 2" "Evaluates Task 2 item" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "Task 3|gerund|Rendering accepted and rejected counts" "Evaluates Task 3 item" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "valid|invalid|needs investigation|needs clarification|already handled|optional|taste" "Classifies at least one item" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_ONE_LINE" "Task 1.*(invalid|incorrect|not valid|wrong|false positive|already handled|does add.*test|Step 1)" "Rejects false test-first finding with plan evidence" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_ONE_LINE" "recordAuditTrail.*(valid|needs investigation|undefined|never created|never defined|missing)" "Accepts or investigates missing recordAuditTrail issue" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_ONE_LINE" "gerund|optional|taste|non-blocking|style" "Treats heading rename as optional/taste" || FAILED=$((FAILED + 1))
assert_git_path_clean "$TEST_PROJECT" ".joshix/plans" "Does not edit plan files" || FAILED=$((FAILED + 1))

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
