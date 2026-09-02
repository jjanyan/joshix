#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONTRACT="$ROOT/skills/using-joshix/references/review-reception-contract.md"
FORMAT="$ROOT/skills/using-joshix/references/review-response-format.md"
USING="$ROOT/skills/using-joshix/SKILL.md"
README="$ROOT/README.md"
GUIDANCE=("$ROOT/AGENTS.md" "$ROOT/CLAUDE.md")
RECEIVERS=(
  "$ROOT/skills/receiving-code-review/SKILL.md"
  "$ROOT/skills/receiving-plan-review/SKILL.md"
  "$ROOT/skills/receiving-spec-review/SKILL.md"
)

normalized_file() {
  tr '\n\r\t' '   ' < "$1" | tr -s ' '
}

require_fixed() {
  local file="$1" text="$2" label="$3"
  local normalized
  normalized="$(normalized_file "$file")"
  if [[ "$normalized" != *"$text"* ]]; then
    printf 'FAIL: %s\nMissing: %s\n' "$label" "$text"
    exit 1
  fi
}

forbid_fixed() {
  local file="$1" text="$2" label="$3"
  local normalized
  normalized="$(normalized_file "$file")"
  if [[ "$normalized" == *"$text"* ]]; then
    printf 'FAIL: %s\nUnexpected: %s\n' "$label" "$text"
    exit 1
  fi
}

require_fixed "$CONTRACT" 'The roles, not fresh `apply`, `fix`, or `proceed` wording, determine default edit authority.' \
  'receiver role owns default authority'
require_fixed "$CONTRACT" 'concrete code or diff' \
  'receiver contract requires a concrete code artifact'
require_fixed "$CONTRACT" 'named plan' \
  'receiver contract requires a named plan artifact'
require_fixed "$CONTRACT" 'named spec' \
  'receiver contract requires a named spec artifact'
require_fixed "$CONTRACT" '## Decision table' \
  'receiver behavior is consolidated in one decision table'
require_fixed "$CONTRACT" '| Situation | Required action | Result |' \
  'decision table owns action and result routing'
require_fixed "$CONTRACT" 'Agent 2 is a read-only review producer.' \
  'Agent 2 remains read-only'
require_fixed "$CONTRACT" 'Agent 1 is the meta-review receiver and artifact owner.' \
  'Agent 1 owns review reception and the artifact'
require_fixed "$CONTRACT" 'Agent 1 independently verifies every finding before classifying or editing.' \
  'Agent 1 verifies before editing'
require_fixed "$CONTRACT" 'Automatic authority covers only objective findings raised by Agent 2 and accepted by Agent 1.' \
  'automatic authority is reviewer-scoped'
require_fixed "$CONTRACT" 'New product, scope, ownership, acceptance-criteria, or architecture choices remain owner-gated.' \
  'new product and architecture choices remain owner-gated'
require_fixed "$CONTRACT" 'Apply every independent accepted objective finding raised by Agent 2.' \
  'required order applies accepted reviewer findings'
require_fixed "$CONTRACT" 'A semantic explicit no-edit instruction or a substantive question about whether work should occur does pause edits.' \
  'semantic no-edit override exists'
require_fixed "$CONTRACT" 'a substantive question about whether work should occur does pause edits.' \
  'honest work-decision questions pause edits'
require_fixed "$CONTRACT" 'A question that merely solicits meta-review does not pause automatic mode.' \
  'meta-review questions do not pause edits'
require_fixed "$CONTRACT" 'After Josh answers an owner question, apply the answer and newly unblocked work without another permission request.' \
  'owner answers continue automatically'
require_fixed "$CONTRACT" 'When prior shared reasoning or the review supplies exact replacement text, preserve it verbatim rather than restyling or elaborating it.' \
  'owner-answer continuation preserves exact agreed text'
require_fixed "$CONTRACT" '## Failure recovery' \
  'failure handling is a bounded recovery protocol'
require_fixed "$CONTRACT" 'pauses further writes to the affected artifact while Agent 1 diagnoses the failure read-only' \
  'unexpected failures pause writes for diagnosis'
require_fixed "$CONTRACT" "Preserve the artifact's exact current state and never automatically roll back a partial change." \
  'unexpected failures preserve exact partial state'
require_fixed "$CONTRACT" 'A verification failure is evidence, not by itself a reason to end the turn.' \
  'verification failure alone does not end the turn'
require_fixed "$CONTRACT" 'Do not rerun a passing focused verification solely to confirm it.' \
  'passing focused verification is not repeated performatively'
require_fixed "$CONTRACT" 'For policy-active completion-gate recovery, follow `autonomous-review.md`' \
  'completion recovery delegates to the central autonomous contract'
require_fixed "$CONTRACT" 'Never require an owner message solely to reset a conversational turn boundary.' \
  'conversational turn boundaries are not recovery gates'
require_fixed "$CONTRACT" 'The eventual reception report names every successfully recovered failure and the focused command or evidence that established recovery.' \
  'successful recovery requires focused evidence'
forbid_fixed "$CONTRACT" 'stops further edits to that artifact for the turn' \
  'old same-turn edit freeze is removed'
forbid_fixed "$CONTRACT" 'does not attempt same-turn repair' \
  'old automatic-repair prohibition is removed'
forbid_fixed "$CONTRACT" 'Make one bounded recovery pass for that failure' \
  'artifact reception does not duplicate completion recovery policy'
forbid_fixed "$CONTRACT" 'Across one review application, Agent 1 may make at most two recovery passes' \
  'artifact reception does not own the recovery ceiling'
require_fixed "$CONTRACT" 'A newly discovered concern from Agent 1 remains unchanged until Agent 2 agrees in a later review.' \
  'Agent 1 concerns wait for Agent 2'
require_fixed "$CONTRACT" 'Rejected, deferred, unclear, and unverified findings remain unchanged with evidence-backed reasoning in the shared conversation.' \
  'disagreement handoff stays conversational'
require_fixed "$CONTRACT" 'If a later Agent 2 pass identifies a previously applied automatic change as wrong, that report is an ordinary new finding.' \
  'later corrections reenter the ordinary review loop'
require_fixed "$CONTRACT" 'the prior application does not create a new owner gate.' \
  'later objective corrections do not become owner decisions'
require_fixed "$CONTRACT" 'Do not classify these failure-state entries as `VALID` or claim they were updated, handled, completed, or fixed' \
  'failure reporting cannot overstate partial work'
require_fixed "$CONTRACT" 'Automatic reception never authorizes unrelated refactoring, new product scope, new architecture, staging, commits, other Git operations, or deployment.' \
  'automatic authority excludes Git'

require_fixed "$FORMAT" 'Use the exact `### Review outcome` lane whenever an outcome is emitted; never substitute an inline `Outcome:` label.' \
  'response contract owns exact outcome presentation'
require_fixed "$FORMAT" '`Approved` requires a current Agent 2 approval plus Agent 1 concurrence with no unresolved dispute.' \
  'response contract owns approval convergence'
require_fixed "$FORMAT" 'Do not reclassify the owner' \
  'response contract owns owner-answer reporting'

forbid_fixed "$USING" '`Approved` requires a current Agent 2 approval' \
  'bootstrap does not duplicate convergence details'
forbid_fixed "$USING" 'On an owner-answer continuation' \
  'bootstrap does not duplicate owner-answer reporting'
forbid_fixed "$USING" 'After an unexpected post-application edit or verification failure' \
  'bootstrap does not duplicate failure-reporting details'

for skill in "${RECEIVERS[@]}"; do
  require_fixed "$skill" 'review-reception-contract.md' \
    "$(basename "$(dirname "$skill")") links receiver behavior"
  require_fixed "$skill" 'review-response-format.md' \
    "$(basename "$(dirname "$skill")") links response presentation"
done
require_fixed "$USING" 'merely asks for meta-review' \
  'bootstrap honest-question rule has the meta-review carve-out'
require_fixed "$USING" 'product discussion' \
  'bootstrap excludes product discussion from artifact reception'
require_fixed "$USING" 'proposed architecture' \
  'bootstrap excludes proposed architecture from artifact reception'
require_fixed "$USING" 'normal conversational response' \
  'bootstrap routes discussion feedback to ordinary prose'
require_fixed "$USING" 'phrase `review` alone does not select artifact reception' \
  'bootstrap does not route on the word review alone'
for file in "${GUIDANCE[@]}"; do
  require_fixed "$file" 'concrete code or diff' \
    "$(basename "$file") requires a concrete code artifact"
  require_fixed "$file" 'named plan' \
    "$(basename "$file") requires a named plan artifact"
  require_fixed "$file" 'named spec' \
    "$(basename "$file") requires a named spec artifact"
  require_fixed "$file" 'product discussion' \
    "$(basename "$file") excludes product discussion from artifact reception"
  require_fixed "$file" 'proposed architecture' \
    "$(basename "$file") excludes proposed architecture from artifact reception"
  require_fixed "$file" 'normal conversational response' \
    "$(basename "$file") routes discussion feedback to ordinary prose"
  require_fixed "$file" 'phrase `review` alone does not select artifact reception' \
    "$(basename "$file") does not route on the word review alone"
  require_fixed "$file" 'automatic meta-review' \
    "$(basename "$file") enables action by default"
  require_fixed "$file" 'explicit no-edit' \
    "$(basename "$file") preserves the read-only override"
  require_fixed "$file" 'supplied or referenced spec' \
    "$(basename "$file") routes spec review requests"
  require_fixed "$file" 'remain automatic and must never trigger the no-edit opening' \
    "$(basename "$file") distinguishes meta-review questions before tool loading"
  forbid_fixed "$file" 'without edit authorization' \
    "$(basename "$file") does not use the old unconditional opening trigger"
done

for file in "$USING" "${GUIDANCE[@]}"; do
  forbid_fixed "$file" 'Every occurrence of `review` enters artifact reception' \
    "$(basename "$file") does not route every use of review"
  forbid_fixed "$file" 'Every shared-chat response enters artifact reception' \
    "$(basename "$file") does not route every shared-chat response"
  forbid_fixed "$file" 'Every task-history critique enters artifact reception' \
    "$(basename "$file") does not route every task-history critique"
done
require_fixed "$USING" 'remain automatic and must never trigger the no-edit opening' \
  'bootstrap distinguishes meta-review questions before tool loading'

for file in "$README" "${GUIDANCE[@]}"; do
  require_fixed "$file" 'joshix:reviewing-plans' \
    "$(basename "$file") lists the plan review producer"
  require_fixed "$file" 'joshix:reviewing-specs' \
    "$(basename "$file") lists the spec review producer"
done
require_fixed "$README" 'artifact-owning agent' \
  'README names the receiver role'
require_fixed "$README" 'automatically applies agreed objective findings' \
  'README documents automatic objective application'
require_fixed "$README" 'explicit no-edit instruction' \
  'README documents the read-only override'
require_fixed "$README" 'architecture choices remain owner-gated' \
  'README documents the owner gate'
for skill in "${RECEIVERS[@]}"; do
  forbid_fixed "$skill" 'Default to review-review mode' \
    "$(basename "$(dirname "$skill")") removes the old default opt-in rule"
  forbid_fixed "$skill" 'review-review mode' \
    "$(basename "$(dirname "$skill")") removes all old opt-in mode wording"
done

DECISION_TABLE_COUNT="$(rg -c '^## Decision table$' "$CONTRACT" || true)"
[ "${DECISION_TABLE_COUNT:-0}" -eq 1 ]

CODE_AUTOMATIC_COUNT="$(rg -ci 'automatic meta-review' "${RECEIVERS[0]}" || true)"
PLAN_AUTOMATIC_COUNT="$(rg -ci 'automatic meta-review' "${RECEIVERS[1]}" || true)"
SPEC_AUTOMATIC_COUNT="$(rg -ci 'automatic meta-review' "${RECEIVERS[2]}" || true)"
USING_AUTOMATIC_COUNT="$(rg -ci 'automatic meta-review' "$USING" || true)"
[ "${CODE_AUTOMATIC_COUNT:-0}" -eq 1 ]
[ "${PLAN_AUTOMATIC_COUNT:-0}" -eq 1 ]
[ "${SPEC_AUTOMATIC_COUNT:-0}" -eq 1 ]
[ "${USING_AUTOMATIC_COUNT:-0}" -eq 1 ]

for file in "${GUIDANCE[@]}"; do
  require_fixed "$file" 'review-reception-contract.md' \
    "$(basename "$file") routes to the canonical decision table"
  require_fixed "$file" 'review-response-format.md' \
    "$(basename "$file") routes to the canonical response grammar"
done

for file in "$USING" "${GUIDANCE[@]}" "${RECEIVERS[@]}"; do
  forbid_fixed "$file" "Agent 1's newly discovered concern remains unchanged until Agent 2 agrees" \
    "$(basename "$file") does not duplicate the convergence decision"
  forbid_fixed "$file" '### Handled without asking' \
    "$(basename "$file") does not duplicate response headings"
  forbid_fixed "$file" '### Applied as requested' \
    "$(basename "$file") does not duplicate response headings"
done

echo 'STATUS: PASSED'
