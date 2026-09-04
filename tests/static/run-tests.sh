#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
tests=(
  "test-parallel-oracles.sh"
  "test-parallel-first-contract.sh"
  "test-task-context-contract.sh"
  "test-progress-dag-contract.sh"
  "test-review-reception-contract.sh"
  "test-review-response-format-contract.sh"
  "test-review-producer-format-contract.sh"
  "test-workflow-policy-contract.sh"
  "test-autonomous-review-contract.sh"
  "test-readiness-hold-contract.sh"
)

passed=0
failed=0

for test_name in "${tests[@]}"; do
  test_path="$SCRIPT_DIR/$test_name"
  echo "Running: $test_name"
  if bash "$test_path"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
done

echo "Running: task-context.test.mjs"
if node --disable-warning=ExperimentalWarning --test \
  "$ROOT/tests/task-context/task-context.test.mjs"; then
  passed=$((passed + 1))
else
  failed=$((failed + 1))
fi

echo "Running: reviewer-host.test.mjs"
if node --disable-warning=ExperimentalWarning --test \
  "$ROOT/tests/reviewer-host/reviewer-host.test.mjs"; then
  passed=$((passed + 1))
else
  failed=$((failed + 1))
fi

echo "Running: discussion-review-routing oracle"
if bash "$ROOT/tests/codex/test-discussion-review-routing-behavior.sh" --oracle-only; then
  passed=$((passed + 1))
else
  failed=$((failed + 1))
fi

echo "Running: completion-gate-recovery oracle"
if bash "$ROOT/tests/codex/test-completion-gate-recovery-behavior.sh" --oracle-only; then
  passed=$((passed + 1))
else
  failed=$((failed + 1))
fi

echo "Running: Codex-to-Claude review-loop oracle"
if bash "$ROOT/tests/codex/test-autonomous-review-loop-behavior.sh" --oracle-only; then
  passed=$((passed + 1))
else
  failed=$((failed + 1))
fi

echo "Running: Claude-to-Codex review-loop oracle"
if bash "$ROOT/tests/claude-code/test-autonomous-review-loop-behavior.sh" --oracle-only; then
  passed=$((passed + 1))
else
  failed=$((failed + 1))
fi

printf 'Passed: %d\n' "$passed"
printf 'Failed: %d\n' "$failed"

if [ "$failed" -ne 0 ]; then
  echo "STATUS: FAILED"
  exit 1
fi

echo "STATUS: PASSED"
