#!/usr/bin/env bash
# Behavior test: received reviews automatically apply accepted objective findings.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: automatic review application"
echo "========================================"
echo ""

FAILED=0

echo "Verifying deterministic helper behavior..."
set +e
FAIL_OUTPUT="$(bash -c 'source "$1"; fail "task-folder mismatch"' _ "$SCRIPT_DIR/test-helpers.sh" 2>&1)"
FAIL_STATUS=$?
set -e
if [ "$FAIL_STATUS" -eq 1 ] && [ "$FAIL_OUTPUT" = 'FAIL: task-folder mismatch' ]; then
  echo '  [PASS] fail exits 1 with the requested diagnostic'
else
  echo "  [FAIL] fail returned $FAIL_STATUS with: $FAIL_OUTPUT"
  FAILED=$((FAILED + 1))
fi

OUTCOME_ONLY=$'### Review outcome\n\n**Approved** — Both agents agree.'
OUTCOME_WITH_DECISION=$'### Review outcome\n\n**Rereview required** — The artifact changed.\n\n## Who owns retries?\n\nRetry placement is undecided.'
OUTCOME_DUPLICATE=$'### Review outcome\n\n**Approved** — First.\n\n**Approved** — Second.'
OUTCOME_MISMATCH=$'### Review outcome\n\n**Approval disputed** — Evidence differs.'
if validate_review_outcome "$OUTCOME_ONLY" 'Approved' \
    && validate_review_outcome "$OUTCOME_WITH_DECISION" 'Rereview required' \
    && ! validate_review_outcome 'No outcome here' 'Approved' \
    && ! validate_review_outcome "$OUTCOME_DUPLICATE" 'Approved' \
    && ! validate_review_outcome "$OUTCOME_MISMATCH" 'Approved'; then
  echo '  [PASS] outcome validator accepts exact outcomes and rejects missing, duplicate, and mismatched outcomes'
else
  echo '  [FAIL] outcome validator accepted or rejected a deterministic fixture incorrectly'
  FAILED=$((FAILED + 1))
fi
if assert_exact_heading_count "$OUTCOME_WITH_DECISION" '### Review outcome' 1 \
    'Exact-heading helper counts one outcome heading' \
    && assert_exact_heading_count "$OUTCOME_WITH_DECISION" '### Applied as requested' 0 \
      'Exact-heading helper accepts an absent heading'; then
  :
else
  FAILED=$((FAILED + 1))
fi

validate_retry_plan_step_sequence() {
  local plan_output="$1"

  printf '%s\n' "$plan_output" | awk '
    function emit_step(    normalized, is_fail, is_implement, is_pass, step_index) {
      if (!in_step) return
      normalized = tolower(block)
      gsub(/[[:space:]]+/, " ", normalized)
      steps[task]++
      step_index = steps[task]
      is_fail = normalized ~ /(test|spec)/ \
        && normalized ~ /(fail(s|ing|ed)?|red[ -]?test|expected to fail|confirm.*fail)/
      is_implement = normalized ~ /(implement[^.]*retry|create[^.]*retryjob|add[^.]*retryjob)/
      is_pass = normalized ~ /((verify|confirm|test).*(pass|green)|passing verification)/ \
        && normalized ~ /node --test tests\/retry-worker[.]test[.]js/
      if (step_index == 1 && displayed_step == 1 && is_fail) first_ok[task] = 1
      if (step_index == 2 && displayed_step == 2 && is_implement) second_ok[task] = 1
      if (step_index == 3 && displayed_step == 3 && is_pass) third_ok[task] = 1
    }
    /^#+[[:space:]]+[Tt]ask([[:space:]:0-9]|$)/ {
      emit_step()
      task++
      in_step = 0
      block = ""
      next
    }
    /^-[[:space:]]+\[[ xX]\][[:space:]]+\*\*Step[[:space:]]+[0-9]+:/ {
      emit_step()
      if (task == 0) pre_task_step = 1
      in_step = 1
      displayed_step = $0
      sub(/^-[[:space:]]+\[[ xX]\][[:space:]]+\*\*Step[[:space:]]+/, "", displayed_step)
      sub(/:.*/, "", displayed_step)
      block = $0
      next
    }
    in_step { block = block " " $0 }
    END {
      emit_step()
      for (candidate = 1; candidate <= task; candidate++) {
        if (steps[candidate] == 3 \
            && first_ok[candidate] \
            && second_ok[candidate] \
            && third_ok[candidate]) valid_tasks++
      }
      exit !(task == 1 && valid_tasks == 1 && !pre_task_step)
    }
  '
}

validate_retry_limit_module() {
  local module_source="$1"

  printf '%s\n' "$module_source" | node --input-type=module -e '
    let source = "";
    for await (const chunk of process.stdin) source += chunk;
    const url = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`;
    const loaded = await import(url);
    if (typeof loaded.retryLimit !== "function" || loaded.retryLimit() !== 3) {
      process.exit(1);
    }
  '
}

validate_spec_retry_replacement() {
  local spec_output="$1"
  printf '%s\n' "$spec_output" | rg -q '^-[[:space:]]+Retry failed jobs three times' \
    && ! printf '%s\n' "$spec_output" | rg -q '^-[[:space:]]+Retry failed jobs two times'
}

VALID_CODE_MODULE='export function retryLimit() { return 3; }'
read -r -d '' UNREACHABLE_APPENDED_RETURN_MODULE <<'EOF' || true
export function retryLimit() {
  return 4;
  return 3;
}
EOF
VALID_SPEC_RETRY_STATE='- Retry failed jobs three times before reporting failure.'
read -r -d '' STALE_AND_NEW_SPEC_RETRY_STATE <<'EOF' || true
- Retry failed jobs two times before reporting failure.
- Retry failed jobs three times before reporting failure.
EOF

if ! validate_retry_limit_module "$VALID_CODE_MODULE" \
    || validate_retry_limit_module "$UNREACHABLE_APPENDED_RETURN_MODULE" \
    || ! validate_spec_retry_replacement "$VALID_SPEC_RETRY_STATE" \
    || validate_spec_retry_replacement "$STALE_AND_NEW_SPEC_RETRY_STATE"; then
  echo '  [FAIL] Deterministic retry replacement oracle fixtures'
  exit 1
fi
echo '  [PASS] Deterministic retry replacement oracle fixtures'

read -r -d '' VALID_PLAN_SEQUENCE <<'EOF' || true
### Task 1: Retry worker
- [ ] **Step 1: Add a failing focused test**
Run the test and confirm it fails.
- [ ] **Step 2: Implement retry behavior**
Create `retryJob()`.
- [ ] **Step 3: Verify the focused test passes**
Run `node --test tests/retry-worker.test.js` and confirm it passes.
EOF

read -r -d '' MALFORMED_PLAN_SEQUENCE <<'EOF' || true
The plan needs a failing test.
### Task 1: Retry worker
- [ ] **Step 1: Add focused test coverage**
Cover the third attempt.
- [ ] **Step 2: Implement retry behavior**
Create `retryJob()`.
- [ ] **Step 3: Verify the focused test passes**
Run `node --test tests/retry-worker.test.js` and confirm it passes.
EOF

read -r -d '' DUPLICATE_STEP_SEQUENCE <<'EOF' || true
### Task 1: Retry worker
- [ ] **Step 1: Add a failing focused test**
Run the test and confirm it fails.
- [ ] **Step 2: Implement retry behavior**
Create `retryJob()`.
- [ ] **Step 3: Implement retry behavior again**
Create `retryJob()` a second time.
- [ ] **Step 4: Verify the focused test passes**
Run `node --test tests/retry-worker.test.js` and confirm it passes.
EOF

read -r -d '' DUPLICATE_TASK_SEQUENCE <<'EOF' || true
### Task 1: Retry worker
- [ ] **Step 1: Add a failing focused test**
Run the test and confirm it fails.
- [ ] **Step 2: Implement retry behavior**
Create `retryJob()`.
- [ ] **Step 3: Verify the focused test passes**
Run `node --test tests/retry-worker.test.js` and confirm it passes.
### Task 2: Duplicate retry worker
- [ ] **Step 1: Add a failing focused test**
Run the test and confirm it fails.
- [ ] **Step 2: Implement retry behavior**
Create `retryJob()`.
- [ ] **Step 3: Verify the focused test passes**
Run `node --test tests/retry-worker.test.js` and confirm it passes.
EOF

read -r -d '' VALID_PLUS_EMPTY_TASK_SEQUENCE <<'EOF' || true
### Task 1: Retry worker
- [ ] **Step 1: Add a failing focused test**
Run the test and confirm it fails.
- [ ] **Step 2: Implement retry behavior**
Create `retryJob()`.
- [ ] **Step 3: Verify the focused test passes**
Run `node --test tests/retry-worker.test.js` and confirm it passes.
### Task 2: Empty follow-up
EOF

read -r -d '' PRE_TASK_STEP_SEQUENCE <<'EOF' || true
- [ ] **Step 1: Add a failing focused test outside any task**
Run the test and confirm it fails.
### Task 1: Retry worker
- [ ] **Step 1: Add a failing focused test**
Run the test and confirm it fails.
- [ ] **Step 2: Implement retry behavior**
Create `retryJob()`.
- [ ] **Step 3: Verify the focused test passes**
Run `node --test tests/retry-worker.test.js` and confirm it passes.
EOF

read -r -d '' MISNUMBERED_PLAN_SEQUENCE <<'EOF' || true
### Task 1: Retry worker
- [ ] **Step 2: Add a failing focused test**
Run the test and confirm it fails.
- [ ] **Step 1: Implement retry behavior**
Create `retryJob()`.
- [ ] **Step 3: Verify the focused test passes**
Run `node --test tests/retry-worker.test.js` and confirm it passes.
EOF

if ! validate_retry_plan_step_sequence "$VALID_PLAN_SEQUENCE" \
    || validate_retry_plan_step_sequence "$MALFORMED_PLAN_SEQUENCE" \
    || validate_retry_plan_step_sequence "$DUPLICATE_STEP_SEQUENCE" \
    || validate_retry_plan_step_sequence "$DUPLICATE_TASK_SEQUENCE" \
    || validate_retry_plan_step_sequence "$VALID_PLUS_EMPTY_TASK_SEQUENCE" \
    || validate_retry_plan_step_sequence "$PRE_TASK_STEP_SEQUENCE" \
    || validate_retry_plan_step_sequence "$MISNUMBERED_PLAN_SEQUENCE"; then
  echo '  [FAIL] Deterministic automatic-plan sequence oracle fixtures'
  exit 1
fi
echo '  [PASS] Deterministic automatic-plan sequence oracle fixtures'

if [ "${AUTOMATIC_REVIEW_ORACLE_ONLY:-0}" = '1' ]; then
  echo 'STATUS: PASSED (oracle only)'
  exit 0
fi

TEST_ROOT="$(create_test_project)"
trap 'cleanup_test_project "$TEST_ROOT"' EXIT

run_automatic_case() {
  local domain="$1"
  local artifact_rel="$2"
  local corrected_pattern="$3"
  local forbidden_pattern="$4"
  local prompt="$5"
  local project="$TEST_ROOT/$domain"
  local output_dir="$project/output"
  local artifact="$project/$artifact_rel"

  mkdir -p "$(dirname "$artifact")"
  init_git_project "$project"
  install_repo_skills_symlink "$project"
  cp "$CODEX_REPO_ROOT/AGENTS.md" "$project/AGENTS.md"

  case "$domain" in
    code)
      cat > "$project/package.json" <<'EOF'
{
  "type": "module"
}
EOF
      cat > "$artifact" <<'EOF'
export function retryLimit() {
  // A prior automatic review change incorrectly raised this to four.
  return 4;
}

export const timeoutMs = 5000;
EOF
      ;;
    plan)
      cat > "$artifact" <<'EOF'
# Retry Worker Plan

### Task 1: Retry worker

Verification command: `node --test tests/retry-worker.test.js`

- [ ] **Step 1: Implement retry behavior**
  Create `retryJob()`.
- [ ] **Step 2: Add the focused test**
  Verify the third attempt succeeds.
EOF
      ;;
    spec)
      cat > "$artifact" <<'EOF'
# Retry Worker Design

## Requirements

- The approved retry count is three.

## Failure Handling

- Retry failed jobs two times before reporting failure.
EOF
      ;;
  esac

  git -C "$project" add AGENTS.md "$artifact_rel"
  if [ "$domain" = 'code' ]; then
    git -C "$project" add package.json
  fi
  git -C "$project" commit --quiet -m "Add $domain review fixture"

  echo "Running automatic $domain reception case..."
  run_codex "$project" "$prompt" "$output_dir" \
    "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"

  local final_output
  local artifact_output
  final_output="$(cat "$output_dir/final.md")"
  artifact_output="$(cat "$artifact")"
  if [ "$domain" = 'plan' ]; then
    if validate_retry_plan_step_sequence "$(cat "$artifact")"; then
      echo '  [PASS] Applies one coherent failing-test, implementation, and passing-verification sequence'
    else
      echo '  [FAIL] Expected exactly one ordered three-step test-first sequence in one task'
      FAILED=$((FAILED + 1))
    fi
  elif [ "$domain" = 'code' ]; then
    if validate_retry_limit_module "$artifact_output"; then
      echo '  [PASS] Evaluated retryLimit returns exactly 3'
    else
      echo '  [FAIL] Expected evaluated retryLimit() to return exactly 3'
      FAILED=$((FAILED + 1))
    fi
  else
    assert_file_contains "$artifact" "$corrected_pattern" \
      'Applies the accepted objective finding' || FAILED=$((FAILED + 1))
  fi
  assert_not_contains "$(cat "$artifact")" "$forbidden_pattern" \
    'Does not apply the false or taste-only finding' || FAILED=$((FAILED + 1))

  case "$domain" in
    code)
      assert_file_contains "$artifact" '^export function retryLimit\(\)' \
        'Preserves the retryLimit export' || FAILED=$((FAILED + 1))
      assert_file_contains "$artifact" 'prior automatic review change.*four' \
        'Preserves the existing retry-history comment' || FAILED=$((FAILED + 1))
      assert_file_contains "$artifact" '^export const timeoutMs = 5000;$' \
        'Preserves the established timeout export and value' || FAILED=$((FAILED + 1))
      assert_contains "$final_output" \
        '^[[:space:]]*-[[:space:]]+\*\*[^*]*(retry|attempt)[^*]* — VALID( · (CRITICAL|IMPORTANT|MINOR))?\*\* — ' \
        'Reports the retry-limit finding as VALID' || FAILED=$((FAILED + 1))
      assert_contains "$final_output" \
        '^[[:space:]]*-[[:space:]]+\*\*[^*]*timeout[^*]* — REJECT\*\* — ' \
        'Reports the false timeout finding as REJECT' || FAILED=$((FAILED + 1))
      assert_not_contains "$final_output" '^## .+\?$' \
        'Later objective correction does not manufacture an owner gate' || FAILED=$((FAILED + 1))
      ;;
    plan)
      assert_exact_heading_count "$artifact_output" '# Retry Worker Plan' 1 \
        'Preserves the plan title' || FAILED=$((FAILED + 1))
      assert_exact_heading_count "$artifact_output" '### Task 1: Retry worker' 1 \
        'Preserves exactly one named retry-worker task' || FAILED=$((FAILED + 1))
      RETRY_JOB_COUNT="$(printf '%s\n' "$artifact_output" | rg -c 'retryJob\(\)' || true)"
      TEST_COMMAND_COUNT="$(printf '%s\n' "$artifact_output" | rg -c 'node --test tests/retry-worker[.]test[.]js' || true)"
      if [ "${RETRY_JOB_COUNT:-0}" -eq 1 ] && [ "${TEST_COMMAND_COUNT:-0}" -eq 1 ]; then
        echo '  [PASS] Preserves one retryJob reference and one focused test command'
      else
        echo "  [FAIL] Expected one retryJob reference and one focused test command; got ${RETRY_JOB_COUNT:-0} and ${TEST_COMMAND_COUNT:-0}"
        FAILED=$((FAILED + 1))
      fi
      assert_contains "$final_output" \
        '^[[:space:]]*-[[:space:]]+\*\*[^*]*(test[- ]first|test.*order|order.*test)[^*]* — VALID( · (CRITICAL|IMPORTANT|MINOR))?\*\* — ' \
        'Reports the test-first ordering finding as VALID' || FAILED=$((FAILED + 1))
      assert_contains "$final_output" \
        '^[[:space:]]*-[[:space:]]+\*\*[^*]*(worker|rename|naming)[^*]* — DEFER\*\* — ' \
        'Reports the taste-only worker rename as DEFER' || FAILED=$((FAILED + 1))
      ;;
    spec)
      assert_exact_heading_count "$artifact_output" '# Retry Worker Design' 1 \
        'Preserves the spec title' || FAILED=$((FAILED + 1))
      assert_exact_heading_count "$artifact_output" '## Requirements' 1 \
        'Preserves the Requirements heading' || FAILED=$((FAILED + 1))
      assert_exact_heading_count "$artifact_output" '## Failure Handling' 1 \
        'Preserves the Failure Handling heading' || FAILED=$((FAILED + 1))
      assert_file_contains "$artifact" 'approved retry count is three' \
        'Preserves the approved retry requirement' || FAILED=$((FAILED + 1))
      assert_not_contains "$artifact_output" 'Retry failed jobs two times' \
        'Removes the stale two-times retry state' || FAILED=$((FAILED + 1))
      SPEC_SECTION_COUNT="$(printf '%s\n' "$artifact_output" | rg -c '^## ' || true)"
      if [ "${SPEC_SECTION_COUNT:-0}" -eq 2 ]; then
        echo '  [PASS] Preserves the spec section topology'
      else
        echo "  [FAIL] Expected exactly two spec sections; got ${SPEC_SECTION_COUNT:-0}"
        FAILED=$((FAILED + 1))
      fi
      assert_contains "$final_output" \
        '^[[:space:]]*-[[:space:]]+\*\*[^*]*(retry|count|contradiction)[^*]* — VALID( · (CRITICAL|IMPORTANT|MINOR))?\*\* — ' \
        'Reports the retry-count contradiction as VALID' || FAILED=$((FAILED + 1))
      assert_contains "$final_output" \
        '^[[:space:]]*-[[:space:]]+\*\*[^*]*(heading|rename|resilience)[^*]* — DEFER\*\* — ' \
        'Reports the taste-only heading rename as DEFER' || FAILED=$((FAILED + 1))
      ;;
  esac

  if validate_compact_bounds "$final_output" 2; then
    echo '  [PASS] Reports at least two bounded compact findings'
  else
    echo '  [FAIL] Expected at least two unique compact findings within shorthand and reason bounds'
    FAILED=$((FAILED + 1))
  fi
  assert_contains "$final_output" '^### Handled without asking$' \
    'Automatic application uses handled heading' || FAILED=$((FAILED + 1))
  assert_not_contains "$final_output" '^### Applied as requested$' \
    'Automatic application does not claim an explicit request' || FAILED=$((FAILED + 1))
  assert_not_contains "$final_output" "I'm reviewing .* not as approval to edit" \
    'Automatic mode omits the review-only opening' || FAILED=$((FAILED + 1))
  if validate_review_outcome "$final_output" 'Rereview required'; then
    echo '  [PASS] Reports the authoritative rereview outcome'
  else
    echo '  [FAIL] Expected exactly one Rereview required outcome'
    FAILED=$((FAILED + 1))
  fi
}

read -r -d '' CODE_PROMPT <<'EOF' || true
Here is another agent's code review. What do you think?

1. `retryLimit()` is objectively wrong. The approved contract is three attempts, but a prior automatic change raised it to four. It must return 3.
2. The module lacks a timeout constant. Add `export const timeoutMs = 10000;`.
EOF
run_automatic_case \
  code src/retry.js 'return 3;' 'timeoutMs = 10000' "$CODE_PROMPT"

read -r -d '' PLAN_PROMPT <<'EOF' || true
Here is another agent's plan review. Thoughts?

1. The plan violates the established test-first rule because implementation precedes the focused test. Put a failing focused-test step first, implementation second, and passing verification with `node --test tests/retry-worker.test.js` third.
2. Rename "Retry worker" to "Resilient worker" because it sounds better.
EOF
run_automatic_case \
  plan .joshix/plans/retry-worker.md 'unused for strict plan oracle' 'Resilient worker' "$PLAN_PROMPT"

read -r -d '' SPEC_PROMPT <<'EOF' || true
Here is another agent's spec review. Is this right?

1. Failure Handling contradicts the approved three-retry requirement by saying two. It must say three.
2. Rename "Failure Handling" to "Resilience" because that heading reads better.
EOF
run_automatic_case \
  spec .joshix/specs/retry-worker-design.md 'Retry failed jobs three times' '^## Resilience$' "$SPEC_PROMPT"

if [ "$FAILED" -eq 0 ]; then
  echo ""
  echo "STATUS: PASSED"
  exit 0
fi

echo ""
echo "STATUS: FAILED"
exit 1
