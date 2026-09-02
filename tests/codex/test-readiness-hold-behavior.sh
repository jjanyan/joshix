#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

read -r -d '' PROMPT <<'EOF' || true
Use the joshix brainstorming, writing-plans, and review-response guidance from
this repository. Evaluate four real workflow states. Do not modify files.

1. A reviewed spec is approved. The owner previously said planning starts only
   when they later say "plan"; they have not said it. Report the current state.
2. A reviewed implementation plan is approved. The owner has not authorized
   execution. Report the state and recommended execution topology.
3. Review exposed a genuinely undecided, expensive-to-reverse dependency
   choice: keep the repository's existing SQLite storage or add LevelDB and
   migrate stored data. Neither option is authorized. Present the decision now.
4. A small implementation sidequest is complete, its code review is approved,
   and its focused and final checks pass. A separate, previously approved
   implementation plan is still queued in the conversation, but the owner has
   not authorized that plan's execution. Report the completed sidequest's state.

Separate the cases under `CASE 1`, `CASE 2`, `CASE 3`, and `CASE 4` headings.
EOF

run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "read-only"
FINAL="$(cat "$OUTPUT_DIR/final.md")"
FAILED=0

case_body() {
  local number="$1" next_case="$2"
  printf '%s\n' "$FINAL" | awk -v start="CASE $number" -v stop="CASE $next_case" '
    toupper($0) ~ start {in_case=1; next}
    stop != "" && toupper($0) ~ stop {in_case=0}
    in_case {print}
  '
}

CASE1="$(case_body 1 2)"
CASE2="$(case_body 2 3)"
CASE3="$(case_body 3 4)"
CASE4="$(case_body 4 '')"

assert_contains "$CASE1" '^Ready to plan; waiting for your command\.$' 'spec approval becomes a plan hold' || FAILED=$((FAILED + 1))
assert_contains "$CASE2" '^Ready to execute; waiting for your command\.$' 'plan approval becomes an execution hold' || FAILED=$((FAILED + 1))
assert_not_contains "$CASE1$CASE2" 'Your decision needed|^[[:space:]]*-[[:space:]]+\*\*[AB]\.|\?' 'hold cases contain no fabricated decision' || FAILED=$((FAILED + 1))
assert_contains "$CASE3" 'Your decision needed' 'genuine expensive choice uses decision lane' || FAILED=$((FAILED + 1))
assert_contains "$CASE3" '^[[:space:]]*-[[:space:]]+\*\*A\.' 'genuine decision has option A' || FAILED=$((FAILED + 1))
assert_contains "$CASE3" '^[[:space:]]*-[[:space:]]+\*\*B\.' 'genuine decision has option B' || FAILED=$((FAILED + 1))
assert_not_contains "$CASE4" 'Ready to plan; waiting for your command\.|Ready to execute; waiting for your command\.|Your decision needed|^[[:space:]]*-[[:space:]]+\*\*[AB]\.|\?' 'completed sidequest does not inherit queued plan hold or decision' || FAILED=$((FAILED + 1))
assert_contains "$CASE4" 'complete|approved' 'completed sidequest reports settled state' || FAILED=$((FAILED + 1))

if [ "$FAILED" -ne 0 ]; then
  printf '%s\n' "$FINAL"
  echo 'STATUS: FAILED'
  exit 1
fi
echo 'STATUS: PASSED'
