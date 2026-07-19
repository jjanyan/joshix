#!/usr/bin/env bash
# Test: subagent-driven-development skill
# Verifies that the skill is loaded and follows correct workflow
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

TASK3_START_LABEL_PATTERN='^[[:space:][:punct:]]*TASK[[:space:]]+3[[:space:]]+START[[:space:]]*:'
TASK3_START_DECISION_PATTERN="${TASK3_START_LABEL_PATTERN}[[:space:][:punct:]]*AFTER[[:space:]]+SPEC[[:space:]]+AND[[:space:]]+QUALITY[[:space:]]+REVIEWS[[:space:][:punct:]]+FOR[[:space:][:punct:]]*TASKS[[:space:]]+1[[:space:]]+AND[[:space:]]+2[[:space:][:punct:]]*$"

task3_start_decision_matches() {
    local candidate="$1"
    local decision_count
    decision_count=$(printf '%s\n' "$candidate" | grep -Eic "$TASK3_START_LABEL_PATTERN" || true)

    [ "$decision_count" -eq 1 ] &&
        printf '%s\n' "$candidate" | grep -Eiq "$TASK3_START_DECISION_PATTERN"
}

verify_task3_start_oracle() {
    local correct='TASK 3 START: AFTER SPEC AND QUALITY REVIEWS FOR TASKS 1 AND 2'
    local spec_only='TASK 3 START: AFTER SPEC REVIEW FOR TASKS 1 AND 2'
    local implementation_only='TASK 3 START: AFTER IMPLEMENTATION FOR TASKS 1 AND 2'
    local one_prerequisite='TASK 3 START: AFTER SPEC AND QUALITY REVIEWS FOR TASK 1 ONLY'
    local formatted_correct='- **task 3 start:** **after spec and quality reviews** for **tasks 1 and 2**.'
    local conflicting_decisions="${correct}"$'\n'"${implementation_only}"

    if ! task3_start_decision_matches "$correct"; then
        echo "  [FAIL] Task 3 start oracle rejected the correct decision"
        return 1
    fi

    if task3_start_decision_matches "$spec_only"; then
        echo "  [FAIL] Task 3 start oracle accepted spec-only completion"
        return 1
    fi

    if task3_start_decision_matches "$implementation_only"; then
        echo "  [FAIL] Task 3 start oracle accepted implementation-only completion"
        return 1
    fi

    if task3_start_decision_matches "$one_prerequisite"; then
        echo "  [FAIL] Task 3 start oracle accepted one prerequisite"
        return 1
    fi

    if ! task3_start_decision_matches "$formatted_correct"; then
        echo "  [FAIL] Task 3 start oracle rejected harmless case, spacing, or punctuation"
        return 1
    fi

    if task3_start_decision_matches "$conflicting_decisions"; then
        echo "  [FAIL] Task 3 start oracle accepted multiple decision lines"
        return 1
    fi

    echo "  [PASS] Task 3 start oracle samples"
}

verify_task3_start_oracle

if [ "${1:-}" = "--oracle-only" ]; then
    exit 0
fi

echo "=== Test: subagent-driven-development skill ==="
echo ""

# Test 1: Verify skill can be loaded
echo "Test 1: Skill loading..."

output=$(run_claude "Use the ${CLAUDE_PLUGIN_NAME}:subagent-driven-development skill. Describe its key steps briefly." 30)

if assert_contains "$output" "subagent-driven-development\|Subagent-Driven Development\|Subagent Driven" "Skill is recognized"; then
    : # pass
else
    exit 1
fi

if assert_contains "$output" "Load Plan\|read.*plan\|extract.*tasks" "Mentions loading plan"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 2: Verify skill describes correct workflow order
echo "Test 2: Workflow ordering..."

output=$(run_claude "Use the ${CLAUDE_PLUGIN_NAME}:subagent-driven-development skill. What comes first: spec compliance review or code quality review? Be specific about the order." 30)

if echo "$output" | grep -Eiq "spec[[:space:]-]*compliance.*(before|first|then).*code[[:space:]-]*quality|code[[:space:]-]*quality.*after.*spec[[:space:]-]*compliance"; then
    echo "  [PASS] Spec compliance before code quality"
    : # pass
else
    echo "  [FAIL] Spec compliance before code quality"
    echo "  Expected output to say spec compliance review happens before code quality review"
    echo "  In output:"
    echo "$output" | sed 's/^/    /'
    exit 1
fi

echo ""

# Test 3: Verify self-review is mentioned
echo "Test 3: Self-review requirement..."

output=$(run_claude "Use the ${CLAUDE_PLUGIN_NAME}:subagent-driven-development skill and its implementer-prompt.md template. Does it require implementers to do self-review? What should they check?" 30)

if assert_contains "$output" "self-review\|self review" "Mentions self-review"; then
    : # pass
else
    exit 1
fi

if assert_contains "$output" "completeness\|Completeness" "Checks completeness"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 4: Verify plan is read once
echo "Test 4: Plan reading efficiency..."

output=$(run_claude "Use the ${CLAUDE_PLUGIN_NAME}:subagent-driven-development skill. How many times should the controller read the plan file? When does this happen?" 30)

if assert_contains "$output" "once\|one time\|single" "Read plan once"; then
    : # pass
else
    exit 1
fi

if assert_contains "$output" "Step 1\|beginning\|start\|Load Plan" "Read at beginning"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 5: Verify spec compliance reviewer is skeptical
echo "Test 5: Spec compliance reviewer mindset..."

output=$(run_claude "Use the ${CLAUDE_PLUGIN_NAME}:subagent-driven-development skill. What is the spec compliance reviewer's attitude toward the implementer's report?" 30)

if assert_contains "$output" "not trust\|don't trust\|skeptical\|skepticism\|strict\|zero-tolerance\|independent.*verif\|verif.*independent\|rather than trusting\|suspicious" "Reviewer is skeptical"; then
    : # pass
else
    exit 1
fi

if assert_contains "$output" "read.*code\|inspect.*code\|verify.*code\|checks.*work\|verify.*work\|verifies.*work\|against.*spec\|against.*requirements" "Reviewer reads code"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 6: Verify review loops
echo "Test 6: Review loop requirements..."

output=$(run_claude "Use the ${CLAUDE_PLUGIN_NAME}:subagent-driven-development skill. What happens if a reviewer finds issues? Is it a one-time review or a loop?" 30)

if assert_contains "$output" "loop\|again\|repeat\|until.*approved\|until.*compliant" "Review loops mentioned"; then
    : # pass
else
    exit 1
fi

if assert_contains "$output" "implementer.*fix\|fix.*issues" "Implementer fixes issues"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 7: Verify full task text is provided
echo "Test 7: Task context provision..."

output=$(run_claude "Use the ${CLAUDE_PLUGIN_NAME}:subagent-driven-development skill. How does the controller provide task information to the implementer subagent? Does it make them read a file or provide it directly?" 30)

if assert_contains "$output" "provide.*directly\|full.*text\|paste\|include.*prompt" "Provides text directly"; then
    : # pass
else
    exit 1
fi

if assert_not_contains "$output" "make.*subagent.*read.*plan\|subagent.*must.*read.*file\|ask.*subagent.*open.*file" "Doesn't make subagent read file"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 8: Verify no worktree prerequisite
echo "Test 8: No worktree prerequisite..."

output=$(run_claude "Use the ${CLAUDE_PLUGIN_NAME}:subagent-driven-development skill. List the required workflow skills. Do not mention skills that are not required." 30)

if assert_not_contains "$output" "using-git-worktrees\|requires.*worktree\|worktree.*required\|prerequisite.*worktree" "Does not require using-git-worktrees"; then
    : # pass
else
    exit 1
fi

if assert_contains "$output" "verification-before-completion\|Verification Before Completion" "Requires verification-before-completion"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 9: Verify current branch default
echo "Test 9: Current branch default..."

output=$(run_claude "Use the ${CLAUDE_PLUGIN_NAME}:subagent-driven-development skill. Should implementation create or switch branches/worktrees by default, or work in the current checkout and branch?" 30)

if assert_contains "$output" "current.*checkout\|current.*branch\|unless.*user.*request\|explicitly.*request" "Uses current branch by default"; then
    : # pass
else
    exit 1
fi

echo ""

# Test 10: Verify independent ready lanes and lane-scoped review gates
echo "Test 10: Independent ready lanes..."

output=$(run_claude "Use the ${CLAUDE_PLUGIN_NAME}:subagent-driven-development skill. An approved plan has Task 1 and Task 2 with Depends on: None, disjoint files, no shared mutable resources, and safe focused tests. Task 3 depends on Tasks 1 and 2. How does the controller execute and review these tasks? End your answer with exactly one decision line using this format, selecting one option from each angle-bracket group based on the skill: TASK 3 START: <AFTER IMPLEMENTATION | AFTER SPEC REVIEW | AFTER SPEC AND QUALITY REVIEWS> FOR <TASK 1 ONLY | TASK 2 ONLY | TASKS 1 AND 2>. Do not reproduce the angle brackets or option lists in the decision line." 60)

if assert_contains "$output" "dispatching-parallel-agents\|[Pp]arallel.*ready\|ready.*[Pp]arallel" "Invokes parallel dispatch for ready lanes"; then
    :
else
    exit 1
fi

if assert_contains "$output" "[Ss]pec.*before.*quality\|[Ss]pec.*then.*quality\|[Qq]uality.*after.*spec" "Preserves spec-before-quality order within each lane"; then
    :
else
    exit 1
fi

if assert_contains "$output" "[Uu]nrelated.*continue\|[Oo]ther.*lane.*continue\|[Ii]ndependent.*continue" "Allows unrelated lanes to continue"; then
    :
else
    exit 1
fi

if task3_start_decision_matches "$output"; then
    echo "  [PASS] Starts Task 3 only after both prerequisite lane gates pass spec and quality review"
else
    echo "  [FAIL] Starts Task 3 only after both prerequisite lane gates pass spec and quality review"
    echo "  Expected one normalized decision line selecting AFTER SPEC AND QUALITY REVIEWS for TASKS 1 AND 2"
    echo "  In output:"
    printf '%s\n' "$output" | sed 's/^/    /'
    exit 1
fi

echo ""

echo "=== All subagent-driven-development skill tests passed ==="
