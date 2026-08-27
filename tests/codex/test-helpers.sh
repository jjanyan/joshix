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
    local rules_mode="${6:-ignore-rules}"
    local writable_dir="${7:-}"

    mkdir -p "$output_dir"

    local final_file="$output_dir/final.md"
    local json_file="$output_dir/events.jsonl"
    local stderr_file="$output_dir/stderr.txt"
    local cmd=(
        "$CODEX_BIN" exec
        --ephemeral
        --ignore-user-config
        --sandbox "$sandbox"
        --cd "$project_dir"
        --json
        --output-last-message "$final_file"
    )

    if [ -n "$writable_dir" ]; then
        cmd+=(--add-dir "$writable_dir")
    fi

    case "$rules_mode" in
        ignore-rules)
            cmd+=(--ignore-rules)
            ;;
        use-rules)
            ;;
        *)
            echo "Unknown run_codex rules mode: $rules_mode" >&2
            return 1
            ;;
    esac

    if [ -n "${CODEX_TEST_MODEL:-}" ]; then
        cmd+=(--model "$CODEX_TEST_MODEL")
    fi

    cmd+=(-)

    local exit_code
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
    else
        exit_code=$?
    fi

    echo "Codex execution failed with exit code $exit_code" >&2
    echo "stderr: $stderr_file" >&2
    echo "events: $json_file" >&2
    echo "final: $final_file" >&2
    if [ -s "$stderr_file" ]; then
        sed 's/^/  stderr: /' "$stderr_file" >&2
    fi
    return "$exit_code"
}

first_nonempty_trimmed_line() {
    awk 'NF { sub(/[[:space:]]+$/, ""); print; exit }'
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

validate_compact_bounds() {
    local output="$1"
    local minimum_items="${2:-1}"

    printf '%s\n' "$output" | awk -v minimum_items="$minimum_items" '
      /^[[:space:]]*-[[:space:]]+\*\*[^*]+ — (VALID|REJECT|DEFER)( · (CRITICAL|IMPORTANT|MINOR))?\*\* — .+/ {
        shorthand = $0
        sub(/^[[:space:]]*-[[:space:]]+\*\*/, "", shorthand)
        sub(/ — (VALID|REJECT|DEFER)( · (CRITICAL|IMPORTANT|MINOR))?\*\* — .+$/, "", shorthand)
        shorthand_words = split(shorthand, shorthand_parts, /[[:space:]]+/)
        normalized_shorthand = tolower(shorthand)
        gsub(/[[:space:]]+/, " ", normalized_shorthand)
        sub(/^ /, "", normalized_shorthand)
        sub(/ $/, "", normalized_shorthand)
        if (handles[normalized_shorthand]) duplicate = 1
        handles[normalized_shorthand] = 1

        reason = $0
        sub(/^.*\*\* — /, "", reason)
        reason_words = split(reason, reason_parts, /[[:space:]]+/)

        if (shorthand_words < 1 || shorthand_words > 5 || reason_words > 40) invalid = 1
        count++
      }
      END { if (count < minimum_items || invalid || duplicate) exit 1 }
    '
}

validate_owner_options() {
    printf '%s\n' "$1" | awk '
      function finish_previous() {
        if (seen && (!pros || !cons)) exit 1
      }
      /^### Your decision needed$/ {
        headings++
        if (headings == 1) in_lane = 1
        next
      }
      !in_lane { next }
      /^[[:space:]]*-[[:space:]]+\*\*[A-Z]\. .+\*\*[[:space:]]*$/ {
        finish_previous()
        option = $0
        sub(/^[[:space:]]*-[[:space:]]+\*\*/, "", option)
        letter = substr(option, 1, 1)
        if (letters[letter]) duplicate = 1
        letters[letter] = 1
        seen++
        pros = 0
        cons = 0
        next
      }
      seen && /^[[:space:]]*-[[:space:]]+Pros:/ { pros = 1; next }
      seen && /^[[:space:]]*-[[:space:]]+Cons:/ { cons = 1; next }
      END {
        if (headings != 1 || seen < 2 || !pros || !cons || duplicate) exit 1
      }
    '
}

validate_single_owner_lane() {
    printf '%s\n' "$1" | awk '
      /^### Your decision needed$/ {
        headings++
        if (headings == 1) in_lane = 1
        next
      }
      in_lane && /^[[:space:]]*-[[:space:]]+\*\*[A-Z]\. / { options_started = 1 }
      in_lane {
        question_line = $0
        question_marks = gsub(/\?/, "", question_line)
        questions += question_marks
        if (!options_started) questions_before_options += question_marks
      }
      END {
        if (headings != 1 || questions != 1 || questions_before_options != 1) exit 1
      }
    '
}

validate_owner_structure() {
    printf '%s\n' "$1" | awk '
      function plain_name(line, name, words) {
        if (line !~ /^\*\*[^*]+\*\*$/) return 0
        name = line
        sub(/^\*\*/, "", name)
        sub(/\*\*$/, "", name)
        if (name !~ /^[[:alnum:]][[:alnum:] &\/-]*$/) return 0
        if (name ~ /[[:lower:]][[:upper:]]/) return 0
        words = split(name, name_parts, /[[:space:]]+/)
        return words >= 1 && words <= 5
      }
      /^### Your decision needed$/ {
        headings++
        if (headings == 1) in_lane = 1
        next
      }
      in_lane && /^#+[[:space:]]/ { later_section = 1 }
      in_lane && NF && !first_nonempty {
        first_nonempty = 1
        if (plain_name($0)) names++
        else invalid_name = 1
        next
      }
      in_lane && /^\*\*[^*]+\*\*$/ {
        names++
        if (!plain_name($0)) invalid_name = 1
        next
      }
      in_lane && /^[[:space:]]*-[[:space:]]+\*\*[A-Z]\. / { options_started = 1 }
      in_lane && /^Example:/ {
        examples++
        if ($0 !~ /^Example:[[:space:]]+[^[:space:]]/ || options_started) invalid_example = 1
      }
      END {
        if (headings != 1 || names != 1 || invalid_name || examples != 1 || invalid_example || later_section) exit 1
      }
    '
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
export -f validate_compact_bounds
export -f validate_owner_options
export -f validate_single_owner_lane
export -f validate_owner_structure
