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
cp "$CODEX_REPO_ROOT/AGENTS.md" "$TEST_PROJECT/AGENTS.md"

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

git -C "$TEST_PROJECT" add AGENTS.md .joshix/specs/import-widget-design.md .joshix/plans/import-widget.md
git -C "$TEST_PROJECT" commit --quiet -m "Add import widget plan"

read -r -d '' PROMPT <<'EOF' || true
Here is a Plan Review from another agent. What do you think?

## Plan Review

**Status:** Issues Found

**Issues:**
1. [Task 1]: The plan skips test-first development because it implements the parser before adding any test coverage.
2. [Task 2, Step 2]: `recordAuditTrail` is called but never created, imported, or defined anywhere in the plan.
3. [Task 3]: Rename this task to "Rendering accepted and rejected counts" because gerund-style headings are cleaner.

Please evaluate the review against the current repository. Review only; do not edit the plan.
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
echo "Verifying plan review-review behavior..."
FAILED=0

if [ "$FIRST_AGENT_LINE" = "I'm reviewing the plan review as feedback to evaluate, not as approval to edit the plan." ]; then
    echo "  [PASS] Emits the exact plan-review mode sentence first"
else
    echo "  [FAIL] Expected first emitted agent sentence to be the exact plan-review mode sentence"
    echo "  Actual: ${FIRST_AGENT_LINE:-<empty>}"
    FAILED=$((FAILED + 1))
fi
if [ "$FIRST_NONEMPTY_LINE" = "I'm reviewing the plan review as feedback to evaluate, not as approval to edit the plan." ]; then
    echo "  [PASS] Uses the exact plan-review mode sentence as the first non-empty line"
else
    echo "  [FAIL] Expected exact plan-review mode sentence as the first non-empty line"
    echo "  Actual: ${FIRST_NONEMPTY_LINE:-<empty>}"
    FAILED=$((FAILED + 1))
fi
assert_contains "$FINAL_OUTPUT" 'No decision needed.*no changes made' 'Uses review-only heading' || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" '^### Handled without asking$' 'Review-only mode never uses the automatic-application heading' || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" '^### Applied as requested$' 'Review-only mode never uses the explicit-application heading' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "$COMPACT_ITEM" 'Uses complete compact item lines' || FAILED=$((FAILED + 1))
if validate_compact_bounds "$FINAL_OUTPUT" 3; then
    echo '  [PASS] Keeps all compact items within shorthand and reason bounds'
else
    echo '  [FAIL] Expected at least three compact items with unique normalized 1-5-word shorthand and reasons of at most 40 words'
    FAILED=$((FAILED + 1))
fi
assert_contains "$FINAL_OUTPUT" '^[[:space:]]*-[[:space:]]+\*\*[^*]+ — REJECT\*\* — .*([Ss]tep 1|test.*first|already.*test)' 'Rejects false plan-order finding with evidence' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" '^[[:space:]]*-[[:space:]]+\*\*[^*]+ — VALID( · (CRITICAL|IMPORTANT|MINOR))?\*\* — .*(recordAuditTrail|audit.*missing|undefined)' 'Accepts missing plan dependency' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" '^[[:space:]]*-[[:space:]]+\*\*[^*]+ — DEFER\*\* — .*(gerund|heading|style|naming)' 'Defers plan naming preference' || FAILED=$((FAILED + 1))
assert_git_path_clean "$TEST_PROJECT" ".joshix/plans" "Does not edit plan files" || FAILED=$((FAILED + 1))
if validate_review_outcome "$FINAL_OUTPUT" 'Rereview required'; then
    echo '  [PASS] Accepted but unapplied objective finding requires rereview'
else
    echo '  [FAIL] Expected exactly one Rereview required outcome'
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
