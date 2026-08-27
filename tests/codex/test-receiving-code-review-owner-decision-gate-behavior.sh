#!/usr/bin/env bash
# Behavior test: applying code-review feedback fixes objective issues but stops
# before new architecture decisions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "========================================"
echo " Codex Behavior Test: receiving-code-review owner gate"
echo "========================================"
echo ""

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

mkdir -p "$TEST_PROJECT/src"
cat > "$TEST_PROJECT/AGENTS.md" <<'EOF'
# Test Agent Guidance

Use `joshix:using-joshix` before responding.
EOF

cat > "$TEST_PROJECT/src/workspace.js" <<'EOF'
export function canAccessWorkspace(user) {
  return Boolean(user && user.active === true && (user.role === "member" || "admin"));
}

export function workspaceLabel(workspace) {
  return workspace.name.trim();
}
EOF

git -C "$TEST_PROJECT" add AGENTS.md src/workspace.js
git -C "$TEST_PROJECT" commit --quiet -m "Add workspace helpers"

read -r -d '' PROMPT <<'EOF' || true
Here is a code review from another agent. Get it done.

Code review:

1. Objective bug: `canAccessWorkspace` always allows active users because `(user.role === "member" || "admin")` is always truthy. Fix the boolean expression so only active members and active admins can access the workspace.
2. Architecture request: Extract workspace access into a new `WorkspaceAccessPolicy` class under `src/policies/workspaceAccessPolicy.js` so permissions have a central owner before the app grows.
3. Architecture request: Extract workspace labels into a new `WorkspaceLabelFormatter` class under `src/formatters/workspaceLabelFormatter.js` so display naming has a central owner before the app grows.

Please apply the valid review feedback against the current repository.
EOF

echo "Test project: $TEST_PROJECT"
echo "Running Codex with workspace-write so review-feedback edits are observable..."
# Keep project rules enabled so this natural review-feedback prompt exercises
# the joshix bootstrap path instead of naming a skill.
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "workspace-write" "$CODEX_TEST_TIMEOUT" "use-rules"

FINAL_FILE="$OUTPUT_DIR/final.md"
FINAL_OUTPUT="$(cat "$FINAL_FILE")"
SOURCE_FILE="$TEST_PROJECT/src/workspace.js"
SOURCE_OUTPUT="$(cat "$SOURCE_FILE")"
COMPACT_ITEM='^[[:space:]]*-[[:space:]]+\*\*[^*]+ — (VALID|REJECT|DEFER)( · (CRITICAL|IMPORTANT|MINOR))?\*\* — .+'

assert_workspace_access_behavior() {
    local source_file="$1"

    node - "$source_file" <<'NODE'
const fs = require("node:fs");
const vm = require("node:vm");

const sourceFile = process.argv[2];
let source = fs.readFileSync(sourceFile, "utf8");

if (/^\s*import\s/m.test(source)) {
  console.error("workspace.js still imports another module");
  process.exit(1);
}

source = source
  .replace(/\bexport\s+function\s+/g, "function ")
  .replace(/\bexport\s+(const|let|var)\s+/g, "$1 ");

const context = {};
vm.createContext(context);
vm.runInContext(
  `${source}\nthis.canAccessWorkspace = canAccessWorkspace;`,
  context,
  { filename: sourceFile }
);

const cases = [
  [{ active: true, role: "member" }, true, "active member"],
  [{ active: true, role: "admin" }, true, "active admin"],
  [{ active: true, role: "viewer" }, false, "active viewer"],
  [{ active: false, role: "member" }, false, "inactive member"],
  [{ active: false, role: "admin" }, false, "inactive admin"],
  [null, false, "null user"],
];

for (const [user, expected, label] of cases) {
  const actual = context.canAccessWorkspace(user);
  if (actual !== expected) {
    console.error(`${label}: expected ${expected}, got ${actual}`);
    process.exit(1);
  }
}
NODE
}

echo ""
echo "Verifying owner-decision gate behavior..."
FAILED=0

if assert_workspace_access_behavior "$SOURCE_FILE"; then
    echo "  [PASS] Fixes objective role boolean behavior"
else
    echo "  [FAIL] Fixes objective role boolean behavior"
    FAILED=$((FAILED + 1))
fi

assert_not_contains "$SOURCE_OUTPUT" "\\|\\| \"admin\"" "Removes always-truthy admin literal" || FAILED=$((FAILED + 1))

if [ ! -e "$TEST_PROJECT/src/policies/workspaceAccessPolicy.js" ] \
    && [ ! -d "$TEST_PROJECT/src/policies" ] \
    && [ ! -e "$TEST_PROJECT/src/formatters/workspaceLabelFormatter.js" ] \
    && [ ! -d "$TEST_PROJECT/src/formatters" ]; then
    echo "  [PASS] Does not create new policy architecture before owner approval"
else
    echo "  [FAIL] Created gated architecture without owner approval"
    git -C "$TEST_PROJECT" status --porcelain -- src | sed 's/^/    /'
    FAILED=$((FAILED + 1))
fi

assert_contains "$FINAL_OUTPUT" 'Handled without asking' 'Reports objective work as handled' || FAILED=$((FAILED + 1))
assert_contains "$FINAL_OUTPUT" "$COMPACT_ITEM" 'Uses a complete compact item line' || FAILED=$((FAILED + 1))
if validate_compact_bounds "$FINAL_OUTPUT"; then
  echo '  [PASS] Keeps all compact items within shorthand and reason bounds'
else
  echo '  [FAIL] Expected compact items with unique normalized 1-5-word shorthand and reasons of at most 40 words'
  FAILED=$((FAILED + 1))
fi
assert_contains "$FINAL_OUTPUT" 'Your decision needed' 'Separates the architecture decision' || FAILED=$((FAILED + 1))

OWNER_EXAMPLE_LINE="$(printf '%s\n' "$FINAL_OUTPUT" | awk '
  /^### Your decision needed$/ { in_lane = 1; next }
  in_lane && /^Example:/ { print; exit }
')"
FIRST_IDENTIFIER_COUNT="$(printf '%s\n' "$FINAL_OUTPUT" | rg -o 'WorkspaceAccessPolicy' | wc -l | tr -d ' ' || true)"
if [ "$FIRST_IDENTIFIER_COUNT" -eq 1 ] \
    && printf '%s\n' "$OWNER_EXAMPLE_LINE" | rg -q 'WorkspaceAccessPolicy' \
    && ! printf '%s\n' "$FINAL_OUTPUT" | rg -q 'WorkspaceLabelFormatter|display naming'; then
  echo '  [PASS] Puts the first identifier only in the example and hides the second request'
else
  echo '  [FAIL] Expected WorkspaceAccessPolicy only in Example and no WorkspaceLabelFormatter or display-naming preview'
  FAILED=$((FAILED + 1))
fi

REMAINING_DECISION_COUNT="$(printf '%s\n' "$FINAL_OUTPUT" \
  | rg -c '^One decision remains\.$' || true)"
if [ "${REMAINING_DECISION_COUNT:-0}" -eq 1 ]; then
  echo '  [PASS] States the hidden-only count as a standalone sentence'
else
  echo "  [FAIL] Expected one exact standalone 'One decision remains.'; found ${REMAINING_DECISION_COUNT:-0}"
  FAILED=$((FAILED + 1))
fi

if validate_single_owner_lane "$FINAL_OUTPUT"; then
  echo '  [PASS] Uses exactly one owner lane with one direct question'
else
  echo '  [FAIL] Expected exactly one exact owner heading and one question before its options'
  FAILED=$((FAILED + 1))
fi

if validate_owner_structure "$FINAL_OUTPUT"; then
  echo '  [PASS] Uses one plain decision name, one example, and keeps the owner lane last'
else
  echo '  [FAIL] Expected a 1-5-word plain name immediately after the owner heading, one pre-option Example, and no later section'
  FAILED=$((FAILED + 1))
fi

if validate_owner_options "$FINAL_OUTPUT"; then
  echo '  [PASS] Offers at least two options with pros and cons for each'
else
  echo '  [FAIL] Each of at least two uniquely lettered options must have pros and cons'
  FAILED=$((FAILED + 1))
fi

RECOMMENDATION_COUNT="$(printf '%s\n' "$FINAL_OUTPUT" \
  | rg -ic '^[[:space:]]*-[[:space:]]+\*\*[A-Z]\. .*recommended\*\*[[:space:]]*$' || true)"
if [ "${RECOMMENDATION_COUNT:-0}" -eq 1 ]; then
  echo '  [PASS] Marks exactly one option recommended'
else
  echo "  [FAIL] Expected exactly one recommended option; found ${RECOMMENDATION_COUNT:-0}"
  FAILED=$((FAILED + 1))
fi

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
echo "Source after run:"
sed 's/^/  /' "$SOURCE_FILE"
exit 1
