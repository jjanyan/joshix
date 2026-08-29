#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT_DIR/tests/codex/run-skill-tests.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/joshix-codex-retry.XXXXXX")"
FAKE_BIN="$TMP_DIR/bin"
COUNT_FILE="$TMP_DIR/count"
FAILED=0

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/codex" <<'EOF'
#!/bin/bash
echo 'fake codex'
EOF

cat > "$FAKE_BIN/bash" <<'EOF'
#!/bin/bash
set -euo pipefail

count=0
if [ -f "$FAKE_COUNT_FILE" ]; then
  count="$(cat "$FAKE_COUNT_FILE")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$FAKE_COUNT_FILE"
printf 'synthetic attempt %s for %s\n' "$count" "$(basename "$1")"

case "$FAKE_MODE" in
  fail-then-pass)
    if [ "$count" -eq 1 ]; then
      exit 1
    fi
    exit 0
    ;;
  always-fail)
    exit 1
    ;;
  *)
    echo "unknown fake mode: $FAKE_MODE" >&2
    exit 2
    ;;
esac
EOF

chmod +x "$FAKE_BIN/codex" "$FAKE_BIN/bash"

run_case() {
  local description="$1"
  local mode="$2"
  local test_name="$3"
  local expected_status="$4"
  local expected_attempts="$5"
  local retry_expectation="$6"
  local expected_retries="$7"
  local output status attempts

  printf '0\n' > "$COUNT_FILE"
  set +e
  output="$(
    PATH="$FAKE_BIN:/usr/bin:/bin" \
      CODEX_BIN=codex \
      FAKE_MODE="$mode" \
      FAKE_COUNT_FILE="$COUNT_FILE" \
      /bin/bash "$RUNNER" --test "$test_name" 2>&1
  )"
  status=$?
  set -e
  attempts="$(cat "$COUNT_FILE")"

  if [ "$status" -eq "$expected_status" ] \
      && [ "$attempts" -eq "$expected_attempts" ]; then
    echo "[PASS] $description uses $attempts attempt(s) and exits $status"
  else
    echo "[FAIL] $description used $attempts attempt(s) and exited $status"
    echo "  expected: attempts=$expected_attempts status=$expected_status"
    printf '%s\n' "$output" | sed 's/^/  /'
    FAILED=$((FAILED + 1))
  fi

  if [ "$retry_expectation" = 'present' ]; then
    if grep -Fq '[RETRY] Model-backed test failed; retrying once.' <<< "$output"; then
      echo "[PASS] $description reports the bounded retry"
    else
      echo "[FAIL] $description did not report the bounded retry"
      FAILED=$((FAILED + 1))
    fi
  elif grep -Fq '[RETRY]' <<< "$output"; then
    echo "[FAIL] $description retried a deterministic test"
    FAILED=$((FAILED + 1))
  else
    echo "[PASS] $description does not report a retry"
  fi

  if grep -Fq "Retried: $expected_retries" <<< "$output"; then
    echo "[PASS] $description reports $expected_retries retried test(s)"
  else
    echo "[FAIL] $description does not report $expected_retries retried test(s)"
    FAILED=$((FAILED + 1))
  fi
}

run_case \
  'transient model-backed failure' \
  'fail-then-pass' \
  'test-skill-discovery-smoke.sh' \
  0 2 present 1

run_case \
  'persistent model-backed failure' \
  'always-fail' \
  'test-skill-discovery-smoke.sh' \
  1 2 present 1

run_case \
  'deterministic failure' \
  'always-fail' \
  'test-receiving-code-review-owner-decision-gate.sh' \
  1 1 absent 0

if [ "$FAILED" -ne 0 ]; then
  echo 'STATUS: FAILED'
  exit 1
fi

echo 'STATUS: PASSED'
