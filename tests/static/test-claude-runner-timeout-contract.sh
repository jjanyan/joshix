#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT_DIR/tests/claude-code/run-skill-tests.sh"
COUPLED_TEST="$ROOT_DIR/tests/claude-code/test-executing-plans-coupled-integration.sh"
PARALLEL_TEST="$ROOT_DIR/tests/claude-code/test-subagent-driven-development-integration.sh"
SKILL_TRIGGER_RUNNER="$ROOT_DIR/tests/skill-triggering/run-test.sh"
SKILL_TRIGGER_PROMPT="$ROOT_DIR/tests/skill-triggering/prompts/dispatching-parallel-agents.txt"
CODEX_HELPERS="$ROOT_DIR/tests/codex/test-helpers.sh"
TEST_NAME="test-subagent-driven-development.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/joshix-runner-timeout.XXXXXX")"
FAKE_BIN="$TMP_DIR/bin"
FAILURE_BIN="$TMP_DIR/failure-bin"
ARGUMENT_BIN="$TMP_DIR/argument-bin"
MAX_TURNS_BIN="$TMP_DIR/max-turns-bin"
TIMEOUT_LOG="$TMP_DIR/timeout.log"
FAILED=0

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$FAKE_BIN" "$FAILURE_BIN" "$ARGUMENT_BIN" "$MAX_TURNS_BIN"

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
echo "fake claude"
EOF

cat > "$FAKE_BIN/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >> "$TIMEOUT_LOG"
exit 0
EOF

chmod +x "$FAKE_BIN/claude" "$FAKE_BIN/timeout"

cat > "$FAILURE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
echo "synthetic Claude failure" >&2
exit 7
EOF

cat > "$FAILURE_BIN/timeout" <<'EOF'
#!/usr/bin/env bash
shift
"$@"
EOF

chmod +x "$FAILURE_BIN/claude" "$FAILURE_BIN/timeout"

cat > "$ARGUMENT_BIN/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
verbose=false
stream_json=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --verbose)
            verbose=true
            ;;
        --output-format)
            shift
            if [ "${1:-}" = "stream-json" ]; then
                stream_json=true
            fi
            ;;
    esac
    shift
done

if [ "$stream_json" = true ] && [ "$verbose" != true ]; then
    echo "stream-json requires --verbose" >&2
    exit 9
fi

printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"joshix:dispatching-parallel-agents"}}]}}'
EOF

cat > "$ARGUMENT_BIN/timeout" <<'EOF'
#!/usr/bin/env bash
shift
"$@"
EOF

chmod +x "$ARGUMENT_BIN/claude" "$ARGUMENT_BIN/timeout"

cat > "$MAX_TURNS_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"joshix:dispatching-parallel-agents"}}]}}'
printf '%s\n' '{"type":"result","subtype":"error_max_turns","is_error":true}'
exit 1
EOF

cat > "$MAX_TURNS_BIN/timeout" <<'EOF'
#!/usr/bin/env bash
shift
"$@"
EOF

chmod +x "$MAX_TURNS_BIN/claude" "$MAX_TURNS_BIN/timeout"

check_timeout() {
    local expected="$1"
    local description="$2"
    shift 2

    : > "$TIMEOUT_LOG"
    if ! PATH="$FAKE_BIN:$PATH" \
        CLAUDE_BIN=claude \
        TIMEOUT_LOG="$TIMEOUT_LOG" \
        bash "$RUNNER" --test "$TEST_NAME" "$@" >/dev/null; then
        echo "[FAIL] $description: runner invocation failed"
        FAILED=$((FAILED + 1))
        return
    fi

    local observed
    observed="$(tail -n 1 "$TIMEOUT_LOG")"
    if [ "$observed" = "$expected" ]; then
        echo "[PASS] $description uses ${expected}s"
    else
        echo "[FAIL] $description uses ${observed}s, expected ${expected}s"
        FAILED=$((FAILED + 1))
    fi
}

check_timeout 300 "focused default"
check_timeout 1800 "integration default" --integration
check_timeout 47 "explicit integration override" --integration --timeout 47

help_output="$(PATH="$FAKE_BIN:$PATH" CLAUDE_BIN=claude bash "$RUNNER" --help)"
if grep -Fq \
    "Set timeout per test (default: 300; 1800 with --integration)" \
    <<< "$help_output"; then
    echo "[PASS] help documents both timeout defaults"
else
    echo "[FAIL] help does not document both timeout defaults"
    FAILED=$((FAILED + 1))
fi

if grep -Fq 'echo "  [PASS] No extra commits created"' "$COUPLED_TEST"; then
    echo "[PASS] coupled integration reports unchanged commit count"
else
    echo "[FAIL] coupled integration omits unchanged commit-count output"
    FAILED=$((FAILED + 1))
fi

HEADROOM_COMMENT="# 1680s leaves 120s of headroom under the runner's 1800s integration timeout."
for test_file in "$COUPLED_TEST" "$PARALLEL_TEST"; do
    if grep -Fq "$HEADROOM_COMMENT" "$test_file"; then
        echo "[PASS] $(basename "$test_file") documents timeout headroom"
    else
        echo "[FAIL] $(basename "$test_file") omits timeout headroom"
        FAILED=$((FAILED + 1))
    fi
done

if grep -Fq 'elif command -v gtimeout >/dev/null 2>&1; then' \
    "$SKILL_TRIGGER_RUNNER" &&
   grep -Fq 'run_with_timeout 300 "$CLAUDE_BIN" -p "$PROMPT"' \
    "$SKILL_TRIGGER_RUNNER"; then
    echo "[PASS] skill-triggering runner has a portable timeout fallback"
else
    echo "[FAIL] skill-triggering runner requires GNU timeout"
    FAILED=$((FAILED + 1))
fi

set +e
skill_trigger_output="$(
    PATH="$FAILURE_BIN:/usr/bin:/bin" \
    CLAUDE_BIN=claude \
    bash "$SKILL_TRIGGER_RUNNER" \
      dispatching-parallel-agents "$SKILL_TRIGGER_PROMPT" 3 2>&1
)"
skill_trigger_status=$?
set -e

if [ "$skill_trigger_status" -eq 7 ] &&
   grep -Fq 'Claude invocation failed with exit code 7' \
    <<< "$skill_trigger_output"; then
    echo "[PASS] skill-triggering runner preserves Claude failures"
else
    echo "[FAIL] skill-triggering runner masked Claude failure as status $skill_trigger_status"
    FAILED=$((FAILED + 1))
fi

set +e
skill_trigger_success_output="$(
    PATH="$ARGUMENT_BIN:/usr/bin:/bin" \
    CLAUDE_BIN=claude \
    bash "$SKILL_TRIGGER_RUNNER" \
      dispatching-parallel-agents "$SKILL_TRIGGER_PROMPT" 3 2>&1
)"
skill_trigger_success_status=$?
set -e

if [ "$skill_trigger_success_status" -eq 0 ] &&
   grep -Fq "PASS: Skill 'dispatching-parallel-agents' was triggered" \
    <<< "$skill_trigger_success_output"; then
    echo "[PASS] skill-triggering runner supplies valid stream-json arguments"
else
    echo "[FAIL] skill-triggering runner's stream-json arguments were rejected"
    FAILED=$((FAILED + 1))
fi

set +e
max_turns_output="$(
    PATH="$MAX_TURNS_BIN:/usr/bin:/bin" \
    CLAUDE_BIN=claude \
    bash "$SKILL_TRIGGER_RUNNER" \
      dispatching-parallel-agents "$SKILL_TRIGGER_PROMPT" 3 2>&1
)"
max_turns_status=$?
set -e

if [ "$max_turns_status" -eq 0 ] &&
   grep -Fq "PASS: Skill 'dispatching-parallel-agents' was triggered" \
    <<< "$max_turns_output"; then
    echo "[PASS] observed activation survives a later max-turns exit"
else
    echo "[FAIL] max-turns exit discarded observed activation evidence"
    FAILED=$((FAILED + 1))
fi

set +e
codex_failure_output="$(
    (
        source "$CODEX_HELPERS"
        run_with_timeout() { return 7; }
        run_codex "$TMP_DIR" "prompt" "$TMP_DIR/codex-output"
    ) 2>&1
)"
codex_failure_status=$?
set -e

if [ "$codex_failure_status" -eq 7 ] &&
   grep -Fq 'Codex execution failed with exit code 7' \
    <<< "$codex_failure_output"; then
    echo "[PASS] Codex helper preserves execution failures"
else
    echo "[FAIL] Codex helper reported status $codex_failure_status instead of 7"
    FAILED=$((FAILED + 1))
fi

if [ "$FAILED" -ne 0 ]; then
    echo "STATUS: FAILED"
    exit 1
fi

echo "STATUS: PASSED"
