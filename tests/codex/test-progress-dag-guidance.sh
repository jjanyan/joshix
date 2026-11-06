#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

fail() {
  echo "FAIL: $*"
  exit 1
}

count_matches() {
  local content="$1" pattern="$2" count
  count="$(printf '%s\n' "$content" | rg -c "$pattern" || true)"
  printf '%s\n' "${count:-0}"
}

TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT
init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

read -r -d '' PROMPT <<'EOF' || true
Use the joshix:executing-plans skill and its canonical progress-DAG reference.
This client has no native interactive visualization or artifact surface.
Show how the top-level coordinator emits this three-node dependency chain:

1. At start, T1 is in flight; T2 and T3 are todo.
2. After one state change, T1 is complete; T2 is in flight; T3 is todo.

Use stable node IDs and base labels Task 1, Task 2, and Task 3, with a readable
status suffix in each label (for example, "Task 1 · active"). Preserve the
dependencies T1 -> T2 -> T3. Then classify whether an ordinary question, a
one-node implementation plan, or a dispatched worker gets a DAG.

Return exactly this shape with no other prose:
START
<one Mermaid fence>
UPDATED
<one Mermaid fence>
DECISIONS: QUESTION=<DAG or NO DAG>; ONE-NODE=<DAG or NO DAG>; WORKER=<DAG or NO DAG>

EOF

run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" "read-only"
FINAL_OUTPUT="$(cat "$OUTPUT_DIR/final.md")"
START_GRAPH="$(printf '%s\n' "$FINAL_OUTPUT" \
  | awk '/^START$/{capture=1;next}/^UPDATED$/{capture=0}capture')"
UPDATED_GRAPH="$(printf '%s\n' "$FINAL_OUTPUT" \
  | awk '/^UPDATED$/{capture=1;next}/^DECISIONS:/{capture=0}capture')"

[ "$(count_matches "$FINAL_OUTPUT" '^```mermaid$')" -eq 2 ] \
  || fail 'expected two opening Mermaid fences'
[ "$(count_matches "$FINAL_OUTPUT" '^```$')" -eq 2 ] \
  || fail 'expected two closing Mermaid fences'
for node in T1 T2 T3; do
  label="Task ${node#T}"
  [ "$(count_matches "$FINAL_OUTPUT" "${node}\\[\\\"${label} · (todo|active|done)\\\"\\]")" -eq 2 ] \
    || fail "$node base label must be stable and its status readable"
done
[ "$(count_matches "$FINAL_OUTPUT" 'T1(\["Task 1 · (active|done)"\])?[[:space:]]*-->[[:space:]]*T2')" -eq 2 ] \
  || fail 'T1 to T2 dependency must be stable'
[ "$(count_matches "$FINAL_OUTPUT" 'T2(\["Task 2 · (todo|active)"\])?[[:space:]]*-->[[:space:]]*T3')" -eq 2 ] \
  || fail 'T2 to T3 dependency must be stable'
[ "$(count_matches "$FINAL_OUTPUT" 'classDef done fill:#173b2c,stroke:#34d399,color:#dcfce7,stroke-width:2px')" -eq 2 ] \
  || fail 'done class must be present in both graphs'
[ "$(count_matches "$FINAL_OUTPUT" 'classDef active fill:#183b5f,stroke:#60a5fa,color:#dbeafe,stroke-width:3px')" -eq 2 ] \
  || fail 'active class must be present in both graphs'
[ "$(count_matches "$FINAL_OUTPUT" 'classDef todo fill:#343434,stroke:#9ca3af,color:#f3f4f6,stroke-width:1px')" -eq 2 ] \
  || fail 'neutral todo class must be present in both graphs'
printf '%s\n' "$START_GRAPH" | rg -q 'class T1 active' \
  || fail 'T1 must start active'
if printf '%s\n' "$START_GRAPH" | rg -q 'class T1 done|class T2 active'; then
  fail 'start graph contains updated state'
fi
printf '%s\n' "$UPDATED_GRAPH" | rg -q 'class T1 done' \
  || fail 'T1 must finish in the update'
printf '%s\n' "$UPDATED_GRAPH" | rg -q 'class T2 active' \
  || fail 'T2 must become active in the update'
for node in T2 T3; do
  printf '%s\n' "$START_GRAPH" | rg -q "class [T0-9,]*${node}[T0-9,]* todo" \
    || fail "start-state $node must use neutral todo styling"
done
printf '%s\n' "$UPDATED_GRAPH" | rg -q 'class T3 todo' \
  || fail 'updated-state T3 must use neutral todo styling'
printf '%s\n' "$FINAL_OUTPUT" \
  | rg -q '^DECISIONS: QUESTION=NO DAG; ONE-NODE=DAG; WORKER=NO DAG$' \
  || fail 'non-trigger decisions are wrong'

echo 'STATUS: PASSED'
