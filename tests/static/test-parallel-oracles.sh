#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

run_oracle() {
  local description="$1"
  shift

  echo "Running oracle: $description"
  "$@"
}

run_oracle \
  "transcript analyzer fixtures" \
  python3 "$ROOT_DIR/tests/claude-code/assert-parallel-transcript.py" --self-test
run_oracle \
  "coupled execution decision" \
  bash "$ROOT_DIR/tests/claude-code/test-executing-plans-coupled-integration.sh" --oracle-only
run_oracle \
  "independent overlap decision" \
  bash "$ROOT_DIR/tests/claude-code/test-subagent-driven-development-integration.sh" --oracle-only
run_oracle \
  "dispatcher guidance" \
  env DISPATCHER_GUIDANCE_ORACLE_ONLY=1 \
    bash "$ROOT_DIR/tests/codex/test-dispatching-parallel-agents-guidance.sh"
run_oracle \
  "dependent Task 3 start decision" \
  bash "$ROOT_DIR/tests/claude-code/test-subagent-driven-development.sh" --oracle-only

echo "STATUS: PASSED"
