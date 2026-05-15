#!/usr/bin/env bash
# Helper functions for Codex skill behavior tests.

CODEX_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_REPO_ROOT="$(cd "$CODEX_TEST_DIR/../.." && pwd)"
CODEX_BIN="${CODEX_BIN:-codex}"
CODEX_TEST_TIMEOUT="${CODEX_TEST_TIMEOUT:-300}"

create_test_project() {
    local base="${TMPDIR:-/tmp}"
    mktemp -d "$base/joshix-codex-test.XXXXXX"
}

cleanup_test_project() {
    local test_dir="$1"
    if [ "${KEEP_CODEX_TEST_PROJECT:-}" = "1" ]; then
        echo "Keeping test project: $test_dir"
        return 0
    fi

    if [ -n "$test_dir" ] && [ -d "$test_dir" ]; then
        rm -rf "$test_dir"
    fi
}

init_git_project() {
    local project_dir="$1"

    git -C "$project_dir" init --quiet
    git -C "$project_dir" config user.email "codex-test@example.com"
    git -C "$project_dir" config user.name "Codex Test"
}

install_repo_skills_symlink() {
    local project_dir="$1"

    mkdir -p "$project_dir/.agents"
    ln -s "$CODEX_REPO_ROOT/skills" "$project_dir/.agents/skills"
}

run_with_timeout() {
    local seconds="$1"
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$seconds" "$@"
    else
        "$@"
    fi
}

run_codex() {
    local project_dir="$1"
    local prompt="$2"
    local output_dir="$3"
    local sandbox="${4:-read-only}"
    local timeout_seconds="${5:-$CODEX_TEST_TIMEOUT}"

    mkdir -p "$output_dir"

    local final_file="$output_dir/final.md"
    local json_file="$output_dir/events.jsonl"
    local stderr_file="$output_dir/stderr.txt"
    local cmd=(
        "$CODEX_BIN" exec
        --ephemeral
        --ignore-user-config
        --ignore-rules
        --sandbox "$sandbox"
        --cd "$project_dir"
        --json
        --output-last-message "$final_file"
    )

    if [ -n "${CODEX_TEST_MODEL:-}" ]; then
        cmd+=(--model "$CODEX_TEST_MODEL")
    fi

    cmd+=(-)

    if printf '%s' "$prompt" | run_with_timeout "$timeout_seconds" "${cmd[@]}" >"$json_file" 2>"$stderr_file"; then
        if [ -f "$final_file" ]; then
            return 0
        fi

        echo "Codex exited successfully but did not write final output" >&2
        echo "stderr: $stderr_file" >&2
        echo "events: $json_file" >&2
        echo "final: $final_file" >&2
        if [ -s "$stderr_file" ]; then
            sed 's/^/  stderr: /' "$stderr_file" >&2
        fi
        return 1
    fi

    local exit_code=$?
    echo "Codex execution failed with exit code $exit_code" >&2
    echo "stderr: $stderr_file" >&2
    echo "events: $json_file" >&2
    echo "final: $final_file" >&2
    if [ -s "$stderr_file" ]; then
        sed 's/^/  stderr: /' "$stderr_file" >&2
    fi
    return "$exit_code"
}

assert_contains() {
    local output="$1"
    local pattern="$2"
    local test_name="${3:-contains assertion}"

    if printf '%s\n' "$output" | grep -Eiq "$pattern"; then
        echo "  [PASS] $test_name"
        return 0
    fi

    echo "  [FAIL] $test_name"
    echo "  Expected to match: $pattern"
    echo "  In output:"
    printf '%s\n' "$output" | sed 's/^/    /'
    return 1
}

assert_not_contains() {
    local output="$1"
    local pattern="$2"
    local test_name="${3:-not contains assertion}"

    if printf '%s\n' "$output" | grep -Eiq "$pattern"; then
        echo "  [FAIL] $test_name"
        echo "  Did not expect to match: $pattern"
        echo "  In output:"
        printf '%s\n' "$output" | sed 's/^/    /'
        return 1
    fi

    echo "  [PASS] $test_name"
    return 0
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local test_name="${3:-file contains assertion}"

    if [ ! -f "$file" ]; then
        echo "  [FAIL] $test_name"
        echo "  Missing file: $file"
        return 1
    fi

    assert_contains "$(cat "$file")" "$pattern" "$test_name"
}

assert_git_path_clean() {
    local project_dir="$1"
    local pathspec="$2"
    local test_name="${3:-git path clean}"

    local status
    status="$(git -C "$project_dir" status --porcelain -- "$pathspec")"
    if [ -z "$status" ]; then
        echo "  [PASS] $test_name"
        return 0
    fi

    echo "  [FAIL] $test_name"
    echo "  Unexpected git status for $pathspec:"
    printf '%s\n' "$status" | sed 's/^/    /'
    return 1
}

export CODEX_TEST_DIR
export CODEX_REPO_ROOT
export CODEX_BIN
export CODEX_TEST_TIMEOUT
export -f create_test_project
export -f cleanup_test_project
export -f init_git_project
export -f install_repo_skills_symlink
export -f run_with_timeout
export -f run_codex
export -f assert_contains
export -f assert_not_contains
export -f assert_file_contains
export -f assert_git_path_clean
