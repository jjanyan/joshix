#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

oracle_only() {
  local contract="$ROOT/skills/using-joshix/references/autonomous-review.md"
  local policy="$ROOT/skills/using-joshix/references/workflow-policy.md"
  local verification="$ROOT/skills/verification-before-completion/SKILL.md"
  local normalized_contract normalized_verification
  normalized_contract="$(tr '\n\r\t' '   ' < "$contract" | tr -s ' ')"
  normalized_verification="$(tr '\n\r\t' '   ' < "$verification" | tr -s ' ')"
  for expected in \
    '| Event | Producer pass | Recovery repair | Review required |' \
    'Mechanical stale expectation meeting all four conditions' \
    'Zero-diagnostic infrastructure retry' \
    'Production/invariant/behavior recovery' \
    'no production code changes' \
    'no assertion is weakened' \
    'no invariant or user-visible behavior changes' \
    'coverage is not reduced' \
    'two recovery repairs total' \
    'gate budget never resets after sign-off'; do
    [[ "$normalized_contract" == *"$expected"* ]]
  done
  rg -Fq -- 'autonomous-review.md' "$policy"
  [[ "$normalized_verification" == *'policy-active completion-gate exception'* ]]

  local fixture
  fixture='[
    {"case":"stale exact string, equally strict","action":"focused repair","producerPasses":0,"recoveryRepairs":1,"bubble":false},
    {"case":"exact equality weakened to contains","action":"stop","producerPasses":0,"recoveryRepairs":0,"bubble":true},
    {"case":"production branch, one pass left","action":"recover and final review","producerPasses":1,"recoveryRepairs":1,"bubble":false},
    {"case":"production branch, no pass left","action":"stop before edit","producerPasses":0,"recoveryRepairs":0,"bubble":true},
    {"case":"provisioning 0.0s, no diagnostics, health green","action":"retry failed subgate","producerPasses":0,"recoveryRepairs":0,"bubble":false},
    {"case":"same provisioning failure twice","action":"decision memo","producerPasses":0,"recoveryRepairs":0,"bubble":true},
    {"case":"full gate after each review round","action":"reject","producerPasses":0,"recoveryRepairs":0,"bubble":true}
  ]'
  jq -e '
    length == 7 and
    .[0].action == "focused repair" and .[0].producerPasses == 0 and .[0].recoveryRepairs == 1 and
    .[1].action == "stop" and .[1].bubble == true and
    .[2].action == "recover and final review" and .[2].producerPasses == 1 and .[2].recoveryRepairs == 1 and
    .[3].action == "stop before edit" and .[3].bubble == true and
    .[4].action == "retry failed subgate" and .[4].producerPasses == 0 and
    .[5].action == "decision memo" and .[5].bubble == true and
    .[6].action == "reject" and .[6].bubble == true
  ' <<<"$fixture" >/dev/null
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
mkdir -p "$TEST_PROJECT/docs"
cat > "$TEST_PROJECT/AGENTS.md" <<'EOF'
joshix-workflow-policy: docs/workflow-policy.md
EOF
cat > "$TEST_PROJECT/docs/workflow-policy.md" <<'EOF'
# Test policy

Tiers, highest to lowest: guarded, ordinary, presentation.
All code behavior is ordinary. Ordinary requires focused behavior tests, one
whole-change review, and `git diff --check` as the final completion gate.
Repository safety and authorization rules are unconditional.
EOF

read -r -d '' PROMPT <<'EOF' || true
Use the active joshix autonomous-review and completion-verification contracts.
This is a read-only protocol test. Return exactly one JSON object and no prose:

- staleExpectation: after review sign-off the required gate fails only because
  an exact expected string is stale; updating it changes no production code,
  weakens no assertion, changes no invariant or user-visible behavior, and
  reduces no coverage. State action, ownerQuestion as a boolean,
  producerPassesConsumed,
  recoveryRepairsConsumed, and nextCheck.
- infrastructure: before workload start browser provisioning exits at 0.0s
  with no product/test diagnostic; the repo is unchanged and a focused health
  check is green. State action, ownerQuestion as a boolean, retries, and
  nextCheck.
- exhaustedProduction: both producer passes are consumed and the final gate
  exposes a production branch defect. State action, editedBeforeMemo, memoCount,
  and memoFields.
EOF
run_codex "$TEST_PROJECT" "$PROMPT" "$OUTPUT_DIR" read-only "$CODEX_TEST_TIMEOUT" use-rules
FINAL="$(cat "$OUTPUT_DIR/final.md")"
RESULT="$OUTPUT_DIR/result.json"
printf '%s\n' "$FINAL" | awk '/^\{/ {capture=1} capture {print} capture && /^\}$/ {exit}' > "$RESULT"

if ! jq -e '
  (.staleExpectation.action | ascii_downcase | test("update|repair")) and
  .staleExpectation.ownerQuestion == false and
  .staleExpectation.producerPassesConsumed == 0 and
  .staleExpectation.recoveryRepairsConsumed == 1 and
  (.staleExpectation.nextCheck | ascii_downcase | test("failed.*subgate|focused")) and
  (.infrastructure.action | ascii_downcase | test("retry")) and
  .infrastructure.ownerQuestion == false and .infrastructure.retries == 1 and
  (.infrastructure.nextCheck | ascii_downcase | test("failed.*subgate")) and
  (.exhaustedProduction.action | ascii_downcase | test("bubble|stop")) and
  .exhaustedProduction.editedBeforeMemo == false and .exhaustedProduction.memoCount == 1 and
  ((.exhaustedProduction.memoFields | tostring) | test("question"; "i") and test("options"; "i") and test("recommend"; "i") and test("context"; "i") and test("history"; "i"))
' "$RESULT" >/dev/null; then
  printf '%s\n' "$FINAL"
  echo 'STATUS: FAILED'
  exit 1
fi
echo 'STATUS: PASSED'
