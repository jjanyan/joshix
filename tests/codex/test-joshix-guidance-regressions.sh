#!/usr/bin/env bash
# Behavior test: core workflow guidance uses joshix defaults, not old upstream defaults.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: joshix guidance"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

read -r -d '' PROMPT <<'EOF' || true
Use the using-joshix, writing-plans, and subagent-driven-development skills from this repo.

Answer these questions in concise bullets:
1. Where should specs and plans be saved?
2. Which exact skill names should a plan handoff use for subagent-driven execution and inline execution?
3. What is the default git behavior for branch, worktree, staging, and commits?
4. What model selection guidance should delegated work follow?
EOF

has_explicit_git_authorization() {
  local output="$1"
  local line mutation_context=0

  while IFS= read -r line; do
    if [ -z "${line//[[:space:]]/}" ]; then
      mutation_context=0
      continue
    fi

    # A wrapped bullet may span many lines, but a new bullet starts new context.
    if printf '%s\n' "$line" | grep -Eq \
        '^[[:space:]]*([-+*][[:space:]]+|[0-9]+[.)][[:space:]]+)'; then
      mutation_context=0
    fi

    if printf '%s\n' "$line" | grep -Eiq '(stage|commit)'; then
      if line_has_affirmative_git_authorization "$line"; then
        return 0
      fi
      mutation_context=1
      continue
    fi

    if printf '%s\n' "$line" | grep -Eiq 'Git operations?' \
        && line_has_affirmative_git_authorization "$line"; then
      return 0
    fi

    if [ "$mutation_context" -eq 1 ] \
        && printf '%s\n' "$line" | grep -Eiq '(those|these|such Git operations?)' \
        && line_has_affirmative_git_authorization "$line"; then
      return 0
    fi
  done <<< "$output"

  return 1
}

line_has_affirmative_git_authorization() {
  local line="$1"
  local affirmative negative
  affirmative='((unless|only when)[[:space:]]+explicit(ly)?[[:space:]]+(requested|asked|approved)|(requires?|needs?)[[:space:]]+(an?[[:space:]]+|the[[:space:]]+)?explicit[[:space:]]+(user[[:space:]]+)?(request|approval|instruction))'
  negative='(((do|does)[[:space:]]+not|don.t|need[[:space:]]+not)[^.!?]{0,40}(require|need)|(requires?|needs?)[[:space:]]+no[[:space:]]+explicit|without[^.!?]{0,40}explicit)'

  if printf '%s\n' "$line" | grep -Eiq "$negative"; then
    return 1
  fi

  printf '%s\n' "$line" | grep -Eiq "$affirmative"
}

VALID_SAME_LINE='Do not stage or commit unless explicitly requested.'
VALID_GIT_LINE='Any such Git operation requires an explicit user request.'
VALID_PRONOUN_LINES=$'Do not stage or commit.\nPerform any of those only when explicitly requested.'
VALID_LONG_PRONOUN=$'Do not stage or commit.\nThis keeps the current checkout unchanged.\nIt also keeps review work reversible.\nThose operations require explicit user approval.'
INVALID_NEGATED_REQUEST=$'Do not stage or commit.\nThose Git operations require no explicit request.'
INVALID_DO_NOT_REQUIRE='Git operations do not require an explicit user request.'
INVALID_UNRELATED_REQUEST=$'Do not stage or commit.\nChange models only when explicitly requested.'
INVALID_CROSS_PARAGRAPH=$'Do not stage or commit.\n\nThose operations require explicit user approval.'

if ! has_explicit_git_authorization "$VALID_SAME_LINE" \
    || ! has_explicit_git_authorization "$VALID_GIT_LINE" \
    || ! has_explicit_git_authorization "$VALID_PRONOUN_LINES" \
    || ! has_explicit_git_authorization "$VALID_LONG_PRONOUN" \
    || has_explicit_git_authorization "$INVALID_NEGATED_REQUEST" \
    || has_explicit_git_authorization "$INVALID_DO_NOT_REQUIRE" \
    || has_explicit_git_authorization "$INVALID_UNRELATED_REQUEST" \
    || has_explicit_git_authorization "$INVALID_CROSS_PARAGRAPH"; then
  echo '  [FAIL] Deterministic Git-authorization oracle fixtures'
  exit 1
fi
echo '  [PASS] Deterministic Git-authorization oracle fixtures'

if [ "${JOSHIX_GUIDANCE_ORACLE_ONLY:-0}" = "1" ]; then
  echo 'STATUS: PASSED (oracle only)'
  exit 0
fi

echo "Test project: $TEST_PROJECT"
echo "Running Codex guidance query..."
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "read-only"

FINAL_FILE="$OUTPUT_DIR/final.md"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"

echo ""
echo "Verifying joshix guidance..."
FAILED=0

assert_contains "$FINAL_OUTPUT" "\\.joshix/specs" "Uses .joshix/specs for specs" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "\\.joshix/plans" "Uses .joshix/plans for plans" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "joshix:subagent-driven-development" "Uses joshix SDD skill name" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "joshix:executing-plans" "Uses joshix executing-plans skill name" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "current.*checkout|current.*branch|work in.*current" "Defaults to current checkout/branch" || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "(do not|don.t).*(stage|commit)" "Does not stage or commit" || FAILED=$((FAILED + 1))
if has_explicit_git_authorization "$FINAL_OUTPUT"; then
  echo '  [PASS] Requires an explicit request for Git mutations'
else
  echo '  [FAIL] Requires an explicit request for Git mutations'
  FAILED=$((FAILED + 1))
fi
assert_contains "$FINAL_OUTPUT" "current/default model|default model|current model|do not downgrade|without downgrading" "Uses current/default model guidance" || FAILED=$((FAILED + 1))

assert_not_contains "$FINAL_OUTPUT" "s[u]perpowers:" "Does not emit old skill namespace" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "docs/s[u]perpowers" "Does not use old docs paths" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "using-git-worktrees|finishing-a-development-branch" "Does not reference removed workflow skills" || FAILED=$((FAILED + 1))
assert_not_contains "$FINAL_OUTPUT" "use.*least powerful|choose.*least powerful|cheap model|cheaper model|fast, cheap" "Does not recommend least-powerful model selection" || FAILED=$((FAILED + 1))

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
