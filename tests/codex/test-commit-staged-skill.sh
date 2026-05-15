#!/usr/bin/env bash
# Behavior test: joshix commit-staged commits only an all-staged clean worktree.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: commit-staged"
echo "========================================"
echo ""

TEST_ROOT="${CODEX_TEST_TMPDIR:-/private/tmp}"
if [ ! -d "$TEST_ROOT" ]; then
    TEST_ROOT="${TMPDIR:-/tmp}"
fi

TEST_RUN_DIR="$(mktemp -d "$TEST_ROOT/joshix-codex-commit-staged.XXXXXX")"
trap 'cleanup_test_project "$TEST_RUN_DIR"' EXIT

read -r -d '' PROMPT <<'EOF' || true
Use the joshix:commit-staged skill to commit my staged changes.
EOF

FAILED=0

create_case_project() {
    local name="$1"
    local project_dir="$TEST_RUN_DIR/$name/project"

    mkdir -p "$project_dir/src"
    init_git_project "$project_dir"
    install_repo_skills_symlink "$project_dir"

    cat > "$project_dir/src/profile.js" <<'EOF'
export function profileName(user) {
  return user.name;
}
EOF

    cat > "$project_dir/src/settings.js" <<'EOF'
export const profileSettings = {
  normalizeNames: false,
};
EOF

    git -C "$project_dir" add .agents/skills src/profile.js src/settings.js
    git -C "$project_dir" commit --quiet -m "Add profile helper"

    printf '%s\n' "$project_dir"
}

run_commit_staged_case() {
    local name="$1"
    local project_dir="$2"
    local final_file="$3"
    local output_dir

    output_dir="$(dirname "$final_file")"
    mkdir -p "$output_dir"
    echo ""
    echo "Running case: $name"
    echo "Test project: $project_dir"
    # Committing mutates .git; workspace-write sandboxes block that in temp repos.
    run_codex "$project_dir" "$PROMPT" "$output_dir" "danger-full-access"
}

verify_commit_created() {
    local name="$1"
    local project_dir="$2"
    local final_file="$3"
    local status_before="$4"
    local commit_count_before="$5"

    local final_output status_after commit_count_after latest_subject latest_body
    final_output="$(cat "$final_file")"
    status_after="$(git -C "$project_dir" status --porcelain)"
    commit_count_after="$(git -C "$project_dir" rev-list --count HEAD)"
    latest_subject="$(git -C "$project_dir" log -1 --format=%s)"
    latest_body="$(git -C "$project_dir" log -1 --format=%B)"

    echo ""
    echo "Verifying case: $name"

    if [ "$status_before" = "M  src/profile.js" ]; then
        echo "  [PASS] $name setup had only staged profile change"
    else
        echo "  [FAIL] $name setup status was unexpected"
        printf '%s\n' "$status_before" | sed 's/^/    /'
        FAILED=$((FAILED + 1))
    fi

    if [ "$commit_count_after" -eq $((commit_count_before + 1)) ]; then
        echo "  [PASS] $name created exactly one commit"
    else
        echo "  [FAIL] $name unexpected commit count"
        echo "    Before: $commit_count_before"
        echo "    After:  $commit_count_after"
        FAILED=$((FAILED + 1))
    fi

    if [ -z "$status_after" ]; then
        echo "  [PASS] $name worktree clean after commit"
    else
        echo "  [FAIL] $name worktree not clean after commit"
        printf '%s\n' "$status_after" | sed 's/^/    /'
        FAILED=$((FAILED + 1))
    fi

    assert_contains "$latest_subject" "^(feat|fix|refactor|perf|test|docs|build|ci|chore)\\([^)]+\\): [a-z]" "$name commit subject is conventional" || FAILED=$((FAILED + 1))
    assert_contains "$latest_body" "Why:" "$name commit body includes Why" || FAILED=$((FAILED + 1))
    assert_contains "$latest_body" "What:" "$name commit body includes What" || FAILED=$((FAILED + 1))
    assert_contains "$latest_body" "Risk:" "$name commit body includes Risk" || FAILED=$((FAILED + 1))
    assert_contains "$latest_body" "trim|profile" "$name commit message describes staged profile change" || FAILED=$((FAILED + 1))
    assert_contains "$final_output" "committed|commit" "$name final response reports commit result" || FAILED=$((FAILED + 1))
}

verify_commit_refused() {
    local name="$1"
    local project_dir="$2"
    local final_file="$3"
    local expected_status="$4"
    local commit_count_before="$5"

    local final_output status_after commit_count_after
    final_output="$(cat "$final_file")"
    status_after="$(git -C "$project_dir" status --porcelain)"
    commit_count_after="$(git -C "$project_dir" rev-list --count HEAD)"

    echo ""
    echo "Verifying case: $name"

    if [ "$commit_count_after" -eq "$commit_count_before" ]; then
        echo "  [PASS] $name did not create a commit"
    else
        echo "  [FAIL] $name changed commit count"
        echo "    Before: $commit_count_before"
        echo "    After:  $commit_count_after"
        FAILED=$((FAILED + 1))
    fi

    if [ "$status_after" = "$expected_status" ]; then
        echo "  [PASS] $name preserved git state"
    else
        echo "  [FAIL] $name changed git state"
        echo "    Expected:"
        printf '%s\n' "$expected_status" | sed 's/^/      /'
        echo "    Actual:"
        printf '%s\n' "$status_after" | sed 's/^/      /'
        FAILED=$((FAILED + 1))
    fi

    assert_contains "$final_output" "not fully staged|unstaged|untracked|partial|partially staged|cannot|can't|won't|refus" "$name final response refuses to commit" || FAILED=$((FAILED + 1))
    assert_contains "$final_output" "joshix:commit-message" "$name final response recommends joshix:commit-message" || FAILED=$((FAILED + 1))
}

echo "Preparing clean staged commit case..."
CLEAN_PROJECT="$(create_case_project clean-staged)"
cat > "$CLEAN_PROJECT/src/profile.js" <<'EOF'
export function profileName(user) {
  return user.name.trim();
}
EOF
git -C "$CLEAN_PROJECT" add src/profile.js
CLEAN_STATUS_BEFORE="$(git -C "$CLEAN_PROJECT" status --porcelain)"
CLEAN_COMMIT_COUNT_BEFORE="$(git -C "$CLEAN_PROJECT" rev-list --count HEAD)"
CLEAN_FINAL_FILE="$TEST_RUN_DIR/clean-staged/output/final.md"
run_commit_staged_case clean-staged "$CLEAN_PROJECT" "$CLEAN_FINAL_FILE"
verify_commit_created "clean-staged" "$CLEAN_PROJECT" "$CLEAN_FINAL_FILE" "$CLEAN_STATUS_BEFORE" "$CLEAN_COMMIT_COUNT_BEFORE"

echo ""
echo "Preparing unstaged tracked refusal case..."
UNSTAGED_PROJECT="$(create_case_project unstaged-tracked)"
cat > "$UNSTAGED_PROJECT/src/profile.js" <<'EOF'
export function profileName(user) {
  return user.name.trim();
}
EOF
git -C "$UNSTAGED_PROJECT" add src/profile.js
cat > "$UNSTAGED_PROJECT/src/settings.js" <<'EOF'
export const profileSettings = {
  normalizeNames: true,
};
EOF
UNSTAGED_STATUS_BEFORE="$(git -C "$UNSTAGED_PROJECT" status --porcelain)"
UNSTAGED_COMMIT_COUNT_BEFORE="$(git -C "$UNSTAGED_PROJECT" rev-list --count HEAD)"
UNSTAGED_FINAL_FILE="$TEST_RUN_DIR/unstaged-tracked/output/final.md"
run_commit_staged_case unstaged-tracked "$UNSTAGED_PROJECT" "$UNSTAGED_FINAL_FILE"
verify_commit_refused "unstaged-tracked" "$UNSTAGED_PROJECT" "$UNSTAGED_FINAL_FILE" "$UNSTAGED_STATUS_BEFORE" "$UNSTAGED_COMMIT_COUNT_BEFORE"

echo ""
echo "Preparing untracked file refusal case..."
UNTRACKED_PROJECT="$(create_case_project untracked-file)"
cat > "$UNTRACKED_PROJECT/src/profile.js" <<'EOF'
export function profileName(user) {
  return user.name.trim();
}
EOF
git -C "$UNTRACKED_PROJECT" add src/profile.js
cat > "$UNTRACKED_PROJECT/src/debug.js" <<'EOF'
export const debugProfile = true;
EOF
UNTRACKED_STATUS_BEFORE="$(git -C "$UNTRACKED_PROJECT" status --porcelain)"
UNTRACKED_COMMIT_COUNT_BEFORE="$(git -C "$UNTRACKED_PROJECT" rev-list --count HEAD)"
UNTRACKED_FINAL_FILE="$TEST_RUN_DIR/untracked-file/output/final.md"
run_commit_staged_case untracked-file "$UNTRACKED_PROJECT" "$UNTRACKED_FINAL_FILE"
verify_commit_refused "untracked-file" "$UNTRACKED_PROJECT" "$UNTRACKED_FINAL_FILE" "$UNTRACKED_STATUS_BEFORE" "$UNTRACKED_COMMIT_COUNT_BEFORE"

echo ""
echo "Preparing partially staged refusal case..."
PARTIAL_PROJECT="$(create_case_project partially-staged)"
cat > "$PARTIAL_PROJECT/src/profile.js" <<'EOF'
export function profileName(user) {
  return user.name.trim();
}
EOF
git -C "$PARTIAL_PROJECT" add src/profile.js
cat > "$PARTIAL_PROJECT/src/profile.js" <<'EOF'
export function profileName(user) {
  return user.name.trim().toUpperCase();
}
EOF
PARTIAL_STATUS_BEFORE="$(git -C "$PARTIAL_PROJECT" status --porcelain)"
PARTIAL_COMMIT_COUNT_BEFORE="$(git -C "$PARTIAL_PROJECT" rev-list --count HEAD)"
PARTIAL_FINAL_FILE="$TEST_RUN_DIR/partially-staged/output/final.md"
run_commit_staged_case partially-staged "$PARTIAL_PROJECT" "$PARTIAL_FINAL_FILE"
verify_commit_refused "partially-staged" "$PARTIAL_PROJECT" "$PARTIAL_FINAL_FILE" "$PARTIAL_STATUS_BEFORE" "$PARTIAL_COMMIT_COUNT_BEFORE"

if [ "$FAILED" -eq 0 ]; then
    echo ""
    echo "STATUS: PASSED"
    exit 0
fi

echo ""
echo "STATUS: FAILED"
exit 1
