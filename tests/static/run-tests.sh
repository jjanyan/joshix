#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
tests=(
  "test-claude-runner-timeout-contract.sh"
  "test-parallel-oracles.sh"
  "test-parallel-first-contract.sh"
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

printf 'Passed: %d\n' "$passed"
printf 'Failed: %d\n' "$failed"

if [ "$failed" -ne 0 ]; then
  echo "STATUS: FAILED"
  exit 1
fi

echo "STATUS: PASSED"
