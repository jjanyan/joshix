#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Codex Behavior Test: parallel dispatcher guidance ==="

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

read -r -d '' PROMPT <<'EOF' || true
Use the dispatching-parallel-agents skill from this repo.

Execution is already authorized. Decide how the skill handles these cases:
- Task 1 and Task 2 are independent, each declares `Depends on: None`, owns
  disjoint files, shares no unsafe mutable resources, and has safe focused
  checks.
- Other tasks overlap files or unsafe mutable resources.
- One host exposes individual worker completion events, another can observe
  only the end of a whole concurrent wave, and another has no concurrent
  workers.
- Delegated model and reasoning, start/completion reporting, unsupported
  timing, the Mermaid threshold, and git recommendations must follow the skill.

Return exactly twelve non-empty, unformatted lines in this order. Replace each
angle-bracketed placeholder with one concise answer and do not include the angle
brackets:

INDEPENDENT: <PARALLEL or SERIAL>
OVERLAP: <PARALLEL or SERIAL>
EVENT HOST: <COMPLETION-AWARE, JOIN-ALL, or SERIAL>
WAVE HOST: <COMPLETION-AWARE, JOIN-ALL, or SERIAL>
NO CONCURRENCY: <COMPLETION-AWARE, JOIN-ALL, or SERIAL>
MODEL: <delegated model and reasoning choice>
START REPORT: <required start-report content>
COMPLETION REPORT: <required completion-report content>
TIMING: <OMIT NUMBERS or REPORT NUMBERS>
MERMAID THRESHOLD: <complete lane and meaningful-work-item threshold>
MERMAID AT THRESHOLD: <EMIT FENCE or NO FENCE>
GIT: <NONE or REQUIRED>

Do not add explanations, headings, bullets, blank lines, or any other prose.
EOF

INDEPENDENT_PATTERN='^INDEPENDENT[[:space:]]*:[[:space:]]*PARALLEL[[:space:]]*[.]?[[:space:]]*$'
OVERLAP_PATTERN='^OVERLAP[[:space:]]*:[[:space:]]*SERIAL[[:space:]]*[.]?[[:space:]]*$'
EVENT_HOST_PATTERN='^EVENT HOST[[:space:]]*:[[:space:]]*COMPLETION-AWARE[[:space:]]*[.]?[[:space:]]*$'
WAVE_HOST_PATTERN='^WAVE HOST[[:space:]]*:[[:space:]]*JOIN-ALL[[:space:]]*[.]?[[:space:]]*$'
NO_CONCURRENCY_PATTERN='^NO CONCURRENCY[[:space:]]*:[[:space:]]*SERIAL[[:space:]]*[.]?[[:space:]]*$'
TIMING_PATTERN='^TIMING[[:space:]]*:[[:space:]]*OMIT NUMBERS[[:space:]]*[.]?[[:space:]]*$'
MERMAID_AT_THRESHOLD_PATTERN='^MERMAID AT THRESHOLD[[:space:]]*:[[:space:]]*EMIT FENCE[[:space:]]*[.]?[[:space:]]*$'
GIT_PATTERN='^GIT[[:space:]]*:[[:space:]]*NONE[[:space:]]*[.]?[[:space:]]*$'
DOWNGRADE_PATTERN='least powerful|cheap model|cheaper model|lower-capability model'
AFFIRMATIVE_GIT_PATTERN='(must|should|need to|required to)[[:space:]]+((create|use)[[:space:]]+(a[[:space:]]+)?(new[[:space:]]+)?(branch|worktree)|(stage|commit))|(branch|worktree)[[:space:]]+is[[:space:]]+required'

output_line() {
  local output="$1"
  local number="$2"
  printf '%s\n' "$output" | sed -n "${number}p"
}

line_matches() {
  local line="$1"
  local pattern="$2"
  printf '%s\n' "$line" | grep -Eiq "$pattern"
}

oracle_accepts() {
  local output="$1"
  local line_count
  line_count="$(printf '%s\n' "$output" | wc -l | tr -d '[:space:]')"
  [ "$line_count" -eq 12 ] || return 1

  line_matches "$(output_line "$output" 1)" "$INDEPENDENT_PATTERN" || return 1
  line_matches "$(output_line "$output" 2)" "$OVERLAP_PATTERN" || return 1
  line_matches "$(output_line "$output" 3)" "$EVENT_HOST_PATTERN" || return 1
  line_matches "$(output_line "$output" 4)" "$WAVE_HOST_PATTERN" || return 1
  line_matches "$(output_line "$output" 5)" "$NO_CONCURRENCY_PATTERN" || return 1
  line_matches "$(output_line "$output" 6)" '^MODEL[[:space:]]*:' || return 1
  line_matches "$(output_line "$output" 6)" '(current/default|current|default)[[:space:]]+model' || return 1
  line_matches "$(output_line "$output" 6)" 'reasoning effort' || return 1
  line_matches "$(output_line "$output" 7)" '^START REPORT[[:space:]]*:' || return 1
  line_matches "$(output_line "$output" 7)" 'parallel lanes' || return 1
  line_matches "$(output_line "$output" 7)" 'serial phases.*reasons' || return 1
  line_matches "$(output_line "$output" 7)" 'expected critical path' || return 1
  line_matches "$(output_line "$output" 7)" 'expected peak concurrency' || return 1
  line_matches "$(output_line "$output" 8)" '^COMPLETION REPORT[[:space:]]*:' || return 1
  line_matches "$(output_line "$output" 8)" '(what actually overlapped|actual overlap)' || return 1
  line_matches "$(output_line "$output" 8)" 'actual critical path' || return 1
  line_matches "$(output_line "$output" 8)" 'serial waits' || return 1
  line_matches "$(output_line "$output" 8)" 'retries' || return 1
  line_matches "$(output_line "$output" 8)" 're-serialization' || return 1
  line_matches "$(output_line "$output" 8)" 'topology variance' || return 1
  line_matches "$(output_line "$output" 9)" "$TIMING_PATTERN" || return 1
  line_matches "$(output_line "$output" 10)" '^MERMAID THRESHOLD[[:space:]]*:' || return 1
  line_matches "$(output_line "$output" 10)" '(two|2)[[:space:]]+(parallel|concurrent)[[:space:]]+lanes' || return 1
  line_matches "$(output_line "$output" 10)" '(three|3)[[:space:]]+meaningful work items' || return 1
  line_matches "$(output_line "$output" 11)" "$MERMAID_AT_THRESHOLD_PATTERN" || return 1
  line_matches "$(output_line "$output" 12)" "$GIT_PATTERN" || return 1
  if line_matches "$output" "$DOWNGRADE_PATTERN"; then return 1; fi
  if line_matches "$output" "$AFFIRMATIVE_GIT_PATTERN"; then return 1; fi
}

read -r -d '' CORRECT_FIXTURE <<'EOF' || true
INDEPENDENT: PARALLEL
OVERLAP: SERIAL
EVENT HOST: COMPLETION-AWARE
WAVE HOST: JOIN-ALL
NO CONCURRENCY: SERIAL
MODEL: current/default model and reasoning effort
START REPORT: expected critical path, parallel lanes, expected peak concurrency, serial phases and reasons
COMPLETION REPORT: actual critical path, serial waits, retries, re-serialization, topology variance, and what actually overlapped
TIMING: OMIT NUMBERS
MERMAID THRESHOLD: three meaningful work items and two parallel lanes
MERMAID AT THRESHOLD: EMIT FENCE
GIT: NONE
EOF

REVERSED_FIXTURE="${CORRECT_FIXTURE/INDEPENDENT: PARALLEL/INDEPENDENT: SERIAL}"
CONTRADICTORY_FIXTURE="${CORRECT_FIXTURE}"$'\n''INDEPENDENT: SERIAL'

oracle_accepts "$CORRECT_FIXTURE" || {
  echo "Oracle self-test failed: correct fixture was rejected"
  exit 1
}
if oracle_accepts "$REVERSED_FIXTURE"; then
  echo "Oracle self-test failed: reversed decision was accepted"
  exit 1
fi
if oracle_accepts "$CONTRADICTORY_FIXTURE"; then
  echo "Oracle self-test failed: contradictory extra prose was accepted"
  exit 1
fi
echo "  [PASS] Deterministic oracle fixtures"

if [ "${DISPATCHER_GUIDANCE_ORACLE_ONLY:-0}" = "1" ]; then
  echo "STATUS: PASSED (oracle only)"
  exit 0
fi

run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "read-only"
FINAL_OUTPUT="$(cat "$OUTPUT_DIR/final.md")"
FAILED=0

LINE_COUNT="$(printf '%s\n' "$FINAL_OUTPUT" | wc -l | tr -d '[:space:]')"
if [ "$LINE_COUNT" -eq 12 ]; then
  echo "  [PASS] Uses exactly twelve normalized lines"
else
  echo "  [FAIL] Uses exactly twelve normalized lines"
  echo "  Actual line count: $LINE_COUNT"
  FAILED=$((FAILED + 1))
fi

INDEPENDENT_LINE="$(output_line "$FINAL_OUTPUT" 1)"
OVERLAP_LINE="$(output_line "$FINAL_OUTPUT" 2)"
EVENT_HOST_LINE="$(output_line "$FINAL_OUTPUT" 3)"
WAVE_HOST_LINE="$(output_line "$FINAL_OUTPUT" 4)"
NO_CONCURRENCY_LINE="$(output_line "$FINAL_OUTPUT" 5)"
MODEL_LINE="$(output_line "$FINAL_OUTPUT" 6)"
START_REPORT_LINE="$(output_line "$FINAL_OUTPUT" 7)"
COMPLETION_REPORT_LINE="$(output_line "$FINAL_OUTPUT" 8)"
TIMING_LINE="$(output_line "$FINAL_OUTPUT" 9)"
MERMAID_THRESHOLD_LINE="$(output_line "$FINAL_OUTPUT" 10)"
MERMAID_AT_THRESHOLD_LINE="$(output_line "$FINAL_OUTPUT" 11)"
GIT_LINE="$(output_line "$FINAL_OUTPUT" 12)"

assert_contains "$INDEPENDENT_LINE" "$INDEPENDENT_PATTERN" "Independent tasks run in parallel" || FAILED=$((FAILED + 1))
assert_contains "$OVERLAP_LINE" "$OVERLAP_PATTERN" "Overlapping or unsafe tasks run serially" || FAILED=$((FAILED + 1))
assert_contains "$EVENT_HOST_LINE" "$EVENT_HOST_PATTERN" "Individual events use completion-aware scheduling" || FAILED=$((FAILED + 1))
assert_contains "$WAVE_HOST_LINE" "$WAVE_HOST_PATTERN" "Whole-wave observation uses join-all scheduling" || FAILED=$((FAILED + 1))
assert_contains "$NO_CONCURRENCY_LINE" "$NO_CONCURRENCY_PATTERN" "No concurrency uses serial scheduling" || FAILED=$((FAILED + 1))
assert_contains "$MODEL_LINE" "^MODEL[[:space:]]*:" "Uses the model label" || FAILED=$((FAILED + 1))
assert_contains "$MODEL_LINE" "(current/default|current|default)[[:space:]]+model" "Preserves the current/default model" || FAILED=$((FAILED + 1))
assert_contains "$MODEL_LINE" "reasoning effort" "Preserves reasoning effort" || FAILED=$((FAILED + 1))
assert_contains "$START_REPORT_LINE" "^START REPORT[[:space:]]*:" "Uses the start-report label" || FAILED=$((FAILED + 1))
assert_contains "$START_REPORT_LINE" "parallel lanes" "Start report identifies parallel lanes" || FAILED=$((FAILED + 1))
assert_contains "$START_REPORT_LINE" "serial phases.*reasons" "Start report identifies serial phases and reasons" || FAILED=$((FAILED + 1))
assert_contains "$START_REPORT_LINE" "expected critical path" "Start report identifies expected critical path" || FAILED=$((FAILED + 1))
assert_contains "$START_REPORT_LINE" "expected peak concurrency" "Start report identifies expected peak concurrency" || FAILED=$((FAILED + 1))
assert_contains "$COMPLETION_REPORT_LINE" "^COMPLETION REPORT[[:space:]]*:" "Uses the completion-report label" || FAILED=$((FAILED + 1))
assert_contains "$COMPLETION_REPORT_LINE" "(what actually overlapped|actual overlap)" "Completion report identifies actual overlap" || FAILED=$((FAILED + 1))
assert_contains "$COMPLETION_REPORT_LINE" "actual critical path" "Completion report identifies actual critical path" || FAILED=$((FAILED + 1))
assert_contains "$COMPLETION_REPORT_LINE" "serial waits" "Completion report identifies serial waits" || FAILED=$((FAILED + 1))
assert_contains "$COMPLETION_REPORT_LINE" "retries" "Completion report identifies retries" || FAILED=$((FAILED + 1))
assert_contains "$COMPLETION_REPORT_LINE" "re-serialization" "Completion report identifies re-serialization" || FAILED=$((FAILED + 1))
assert_contains "$COMPLETION_REPORT_LINE" "topology variance" "Completion report identifies topology variance" || FAILED=$((FAILED + 1))
assert_contains "$TIMING_LINE" "$TIMING_PATTERN" "Unsupported timing omits numbers" || FAILED=$((FAILED + 1))
assert_contains "$MERMAID_THRESHOLD_LINE" "^MERMAID THRESHOLD[[:space:]]*:" "Uses the Mermaid-threshold label" || FAILED=$((FAILED + 1))
assert_contains "$MERMAID_THRESHOLD_LINE" "(two|2)[[:space:]]+(parallel|concurrent)[[:space:]]+lanes" "Mermaid threshold requires two parallel lanes" || FAILED=$((FAILED + 1))
assert_contains "$MERMAID_THRESHOLD_LINE" "(three|3)[[:space:]]+meaningful work items" "Mermaid threshold requires three meaningful work items" || FAILED=$((FAILED + 1))
assert_contains "$MERMAID_AT_THRESHOLD_LINE" "$MERMAID_AT_THRESHOLD_PATTERN" "Mermaid fence is emitted at threshold" || FAILED=$((FAILED + 1))
assert_contains "$GIT_LINE" "$GIT_PATTERN" "Does not recommend git operations" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "$DOWNGRADE_PATTERN" "Does not downgrade delegated work" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "$AFFIRMATIVE_GIT_PATTERN" "Does not require git operations" || FAILED=$((FAILED + 1))

if [ "$FAILED" -eq 0 ]; then
  echo "STATUS: PASSED"
  exit 0
fi

echo "STATUS: FAILED"
echo "Final output: $OUTPUT_DIR/final.md"
echo "Events: $OUTPUT_DIR/events.jsonl"
exit 1
