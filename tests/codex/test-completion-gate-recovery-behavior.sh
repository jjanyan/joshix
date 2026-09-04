#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

oracle_only() {
  local contract="$ROOT/skills/using-joshix/references/autonomous-review.md"
  local reception="$ROOT/skills/using-joshix/references/review-reception-contract.md"
  local normalized_contract normalized_reception
  normalized_contract="$(tr '\n\r\t' '   ' < "$contract" | tr -s ' ')"
  normalized_reception="$(tr '\n\r\t' '   ' < "$reception" | tr -s ' ')"
  for expected in \
    'artifact materially changes or new evidence appears' \
    'repeats a rebutted disagreement without new evidence' \
    'same concrete defect is materially unchanged' \
    'owner decision' \
    'no objective correction remains'; do
    [[ "$normalized_contract" == *"$expected"* ]]
  done
  [[ "$normalized_reception" == *'diagnosis establishes the artifact'* ]]
  [[ "$normalized_reception" == *'Apply the correction and run focused verification.'* ]]
  for removed in \
    'correction rounds' 'recovery repairs' 'pass ceiling' \
    'infrastructure retry' 'gate budget'; do
    [[ "$normalized_contract" != *"$removed"* ]]
  done
  echo 'STATUS: PASSED'
}

if [ "${1:-}" = '--oracle-only' ]; then
  oracle_only
  exit 0
fi

oracle_only >/dev/null
TEST_PROJECT="$(create_test_project)"
OUTPUT_DIR="$TEST_PROJECT/output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT
init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"

read -r -d '' PROMPT <<'EOF' || true
Use the active joshix autonomous-review, review-reception, and completion
verification contracts. This is read-only. Return exactly one JSON object and
no prose with these fields:

- objectiveFailure: action, ownerQuestion, nextCheck. The final verification
  exposes a concrete in-scope defect, existing requirements determine the fix,
  and no product or architecture choice is involved.
- architectureChoice: action, editedBeforeOwner, ownerQuestion. The proposed
  fix requires selecting a new subsystem boundary.
- unchangedDefect: action, rereview. An attempted authorized correction leaves
  the same concrete defect materially unchanged.
- repeatedRebuttal: action, rereview. The reviewer repeats a rebutted
  disagreement and supplies no new evidence.
- meaningfulChange: action, reviewerProcess. The artifact materially changed,
  focused verification passed, and new evidence exists.
EOF
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" read-only "$CODEX_TEST_TIMEOUT" use-rules
FINAL="$(cat "$OUTPUT_DIR/final.md")"
RESULT="$OUTPUT_DIR/result.json"
printf '%s\n' "$FINAL" | awk '/^\{/ {capture=1} capture {print} capture && /^\}$/ {exit}' > "$RESULT"

if ! jq -e '
  (.objectiveFailure.action | ascii_downcase | test("correct|fix")) and
  (.objectiveFailure.ownerQuestion == false or .objectiveFailure.ownerQuestion == null) and
  (.objectiveFailure.nextCheck | ascii_downcase | test("rerun|affected|focused|gate")) and
  (.architectureChoice.action | ascii_downcase | test("leave|owner|stop|ask")) and
  .architectureChoice.editedBeforeOwner == false and
  (.architectureChoice.ownerQuestion != false and .architectureChoice.ownerQuestion != null) and
  (.unchangedDefect.action | ascii_downcase | test("stop")) and .unchangedDefect.rereview == false and
  (.repeatedRebuttal.action | ascii_downcase | test("stop")) and .repeatedRebuttal.rereview == false and
  (.meaningfulChange.action | ascii_downcase | test("review")) and
  (.meaningfulChange.reviewerProcess | ascii_downcase | test("fresh|new"))
' "$RESULT" >/dev/null; then
  printf '%s\n' "$FINAL"
  echo 'STATUS: FAILED'
  exit 1
fi
echo 'STATUS: PASSED'
