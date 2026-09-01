#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

TEST_PROJECT="$(create_test_project)"
POLICY_OUTPUT="$TEST_PROJECT/policy-output"
LEGACY_OUTPUT="$TEST_PROJECT/legacy-output"
trap 'cleanup_test_project "$TEST_PROJECT"' EXIT

init_git_project "$TEST_PROJECT"
install_repo_skills_symlink "$TEST_PROJECT"
mkdir -p "$TEST_PROJECT/docs"

cat > "$TEST_PROJECT/AGENTS.md" <<'EOF'
# Test guidance

joshix-workflow-policy: docs/workflow-policy.md
EOF
cat > "$TEST_PROJECT/docs/workflow-policy.md" <<'EOF'
# Synthetic workflow policy

Tiers, most critical first: guarded, ordinary, presentation.

- guarded: exhaustive invariant tests and review at every existing gate.
- ordinary: one strong behavior test and one whole-change review.
- presentation: no new automated tests unless recurring; one review.

Map authorization/storage effects to guarded, ordinary application behavior to
ordinary, and styling-only effects to presentation. Findings use the tier of
the endangered outcome independently of the hosting surface. Required final
check: `git diff --check`. All repository safety rules remain unconditional.
EOF

read -r -d '' POLICY_PROMPT <<'EOF' || true
Use the active joshix workflow policy. This is a read-only classification; do
not edit files. Return one JSON object and no prose for these cases:
- highTrivial: one-line authorization evaluator change, trivial complexity.
- routineDesign: a routine task whose only uncertainty is behavior choice, so
  the selected artifact is a design note.
- routinePlan: a routine task whose behavior is settled but file sequencing is
  uncertain, so the selected artifact is an implementation plan.
- lowComplex: sweeping styling overhaul, complex complexity.
- mixed: guarded authorization plus presentation styling.
- displayRead: presentation-only change reads a guarded module's existing value
  for display without changing what the guarded module computes.
- lowerFinding: presentation consequence on a guarded changed surface.
- higherFinding: guarded data-loss consequence on a presentation surface.
- unchangedLowerFinding: presentation consequence on an unchanged surface in
  an ordinary-tier task.
- unchangedHigherFinding: guarded consequence on an unchanged surface in a
  presentation-tier task.
- scopeExpansion: requested CSS fix grows a new subsystem.
- costAtTwoTimesEstimate: active work reaches exactly twice estimate.

Use keys planningArtifacts, planningStages, verification, taskReviewTier,
surfaceTestsStayDistinct, lowerFinding, higherFinding, scopeExpansion, and
costAtTwoTimesEstimate as applicable. For mixed.surfaceTestsStayDistinct,
return an object with exact keys guarded and presentation whose values state
each surface's test depth.
EOF
run_codex "$TEST_PROJECT" "$POLICY_PROMPT" "$POLICY_OUTPUT" "read-only" "$CODEX_TEST_TIMEOUT" "use-rules"
POLICY_FINAL="$(cat "$POLICY_OUTPUT/final.md")"
POLICY_JSON="$POLICY_OUTPUT/policy.json"
printf '%s\n' "$POLICY_FINAL" | awk '
  /^\{/ { capture = 1 }
  capture { print }
  capture && /^\}$/ { exit }
' > "$POLICY_JSON"

rm "$TEST_PROJECT/AGENTS.md"
cat > "$TEST_PROJECT/AGENTS.md" <<'EOF'
# Test guidance

Use joshix normally. No workflow policy is declared.
EOF
read -r -d '' LEGACY_PROMPT <<'EOF' || true
Use joshix to describe the required workflow for a multi-step feature. Do not
edit files. State whether brainstorming, a spec, and an implementation plan are
still required when no repository workflow policy is declared.
EOF
run_codex "$TEST_PROJECT" "$LEGACY_PROMPT" "$LEGACY_OUTPUT" "read-only" "$CODEX_TEST_TIMEOUT" "use-rules"
LEGACY_FINAL="$(cat "$LEGACY_OUTPUT/final.md")"

FAILED=0
if jq -e '
  ((.highTrivial.planningArtifacts // .planningArtifacts.highTrivial) | length == 0) and
  ((.routineDesign.planningArtifacts // .planningArtifacts.routineDesign) | length == 1) and
  ((.routineDesign.planningArtifacts // .planningArtifacts.routineDesign) | tostring | test("design note"; "i")) and
  ((.routinePlan.planningArtifacts // .planningArtifacts.routinePlan) | length == 1) and
  ((.routinePlan.planningArtifacts // .planningArtifacts.routinePlan) | tostring | test("plan"; "i")) and
  ((.lowComplex.planningArtifacts // .planningArtifacts.lowComplex) | tostring | test("brainstorm")) and
  ((.lowComplex.planningArtifacts // .planningArtifacts.lowComplex) | tostring | test("spec")) and
  ((.lowComplex.planningArtifacts // .planningArtifacts.lowComplex) | tostring | test("plan")) and
  ((.lowComplex.verification // .verification.lowComplex) | tostring | test("no new automated tests|light|presentation"; "i")) and
  ((.highTrivial.verification // .verification.highTrivial) | tostring | test("exhaustive")) and
  ((.mixed.taskReviewTier // .taskReviewTier.mixed) == "guarded") and
  ((.displayRead.taskReviewTier // .taskReviewTier.displayRead) == "presentation") and
  (((.mixed.surfaceTestsStayDistinct // .surfaceTestsStayDistinct) | type) == "object" and
    ((.mixed.surfaceTestsStayDistinct // .surfaceTestsStayDistinct).guarded | tostring | test("exhaustive"; "i")) and
    ((.mixed.surfaceTestsStayDistinct // .surfaceTestsStayDistinct).presentation | tostring | test("no new automated tests|recurring"; "i"))) and
  (.lowerFinding | tostring | test("deferred")) and
  (.higherFinding | tostring | test("bubble up|bubble-up")) and
  (.unchangedLowerFinding | tostring | test("deferred|out-of-scope"; "i")) and
  (.unchangedHigherFinding | tostring | test("bubble up|bubble-up"; "i")) and
  (.scopeExpansion | tostring | test("bubble up|bubble-up")) and
  (.costAtTwoTimesEstimate | tostring | test("decision memo|bubble up|bubble-up"))
' "$POLICY_JSON" >/dev/null; then
  echo 'PASS: policy JSON preserves independent axes and bubble-up rules'
else
  echo 'FAIL: policy JSON preserves independent axes and bubble-up rules'
  FAILED=$((FAILED + 1))
fi
assert_contains "$LEGACY_FINAL" 'brainstorm' 'no-policy branch keeps brainstorming' || FAILED=$((FAILED + 1))
assert_contains "$LEGACY_FINAL" 'spec' 'no-policy branch keeps spec' || FAILED=$((FAILED + 1))
assert_contains "$LEGACY_FINAL" 'plan' 'no-policy branch keeps plan' || FAILED=$((FAILED + 1))

if [ "$FAILED" -ne 0 ]; then
  printf '%s\n' "$POLICY_FINAL" "$LEGACY_FINAL"
  echo 'STATUS: FAILED'
  exit 1
fi
echo 'STATUS: PASSED'
