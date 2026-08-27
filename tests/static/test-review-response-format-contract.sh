#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FORMAT="$ROOT/skills/using-joshix/references/review-response-format.md"
source "$ROOT/tests/codex/test-helpers.sh"

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

require_fixed "$FORMAT" 'applies to agents responding to reviewer reports' 'scope is receiver-only'
require_fixed "$FORMAT" 'Reviewer reports stay detailed' 'reviewer reports keep their existing format'
require_fixed "$FORMAT" 'fresh and delegated plan, spec, and code reviewers' 'producer reviews remain detailed'
require_fixed "$FORMAT" 'No decision needed — no changes made' 'review-only heading is canonical'
require_fixed "$FORMAT" '### No decision needed — no changes made' 'review-only heading syntax is canonical'
require_fixed "$FORMAT" 'Handled without asking' 'authorized-application heading is canonical'
require_fixed "$FORMAT" '### Handled without asking' 'authorized-application heading syntax is canonical'
require_fixed "$FORMAT" 'one-to-five-word shorthand' 'compact items use short handles'
require_fixed "$FORMAT" '40 words' 'compact reasons have a word limit'
require_fixed "$FORMAT" 'concrete evidence and the proposed action or actual outcome' 'compact reasons contain evidence and outcomes'
require_fixed "$FORMAT" '`VALID`' 'valid classification is documented'
require_fixed "$FORMAT" '`REJECT`' 'reject classification is documented'
require_fixed "$FORMAT" '`DEFER`' 'defer classification is documented'
require_fixed "$FORMAT" '`REJECT` means the finding is wrong, stale, duplicated, or contradicted by evidence.' \
  'reject is reserved for disproven findings'
require_fixed "$FORMAT" '`DEFER` means the idea or harmless preference is reasonable, clearly non-blocking, and already outside approved scope.' \
  'defer owns reasonable non-blocking preferences'
require_fixed "$FORMAT" 'A harmless naming, heading, or style preference is `DEFER`, not `REJECT`' \
  'canonical format resolves preference classification explicitly'
require_fixed "$FORMAT" 'even when applying it would create needless churn' \
  'preference deferral is not confused with implementation cost'
forbid_fixed "$FORMAT" '`REJECT` means the finding is wrong, stale, duplicated, taste-only' \
  'taste-only wording does not conflict with preference deferral'
require_fixed "$FORMAT" 'only on `VALID`' 'urgency is limited to valid findings'
require_fixed "$FORMAT" 'exactly one owner decision per response' 'owner decisions are serialized'
require_fixed "$FORMAT" 'Use ordinary wording, one concrete example' 'owner decisions use plain concrete language'
require_fixed "$FORMAT" 'at least two genuine options' 'owner decisions present genuine alternatives'
require_fixed "$FORMAT" 'lettered `A` through `Z`' 'owner options are lettered'
require_fixed "$FORMAT" 'Give each option concrete pros and cons' 'owner options explain their tradeoffs'
require_fixed "$FORMAT" 'exactly one recommended option' 'one owner option is recommended'
require_fixed "$FORMAT" 'first non-empty line after `### Your decision needed`' \
  'canonical reference owns owner-decision name placement'
require_fixed "$FORMAT" 'exactly one concrete `Example:` line before the options' \
  'canonical reference owns the example grammar'
require_fixed "$FORMAT" 'put that exact identifier in the `Example:` line only' \
  'canonical reference owns technical-identifier placement'
require_fixed "$FORMAT" 'standalone sentence `One decision remains.`' \
  'canonical reference owns the remaining-count grammar'
require_fixed "$FORMAT" 'End the response with this owner section' \
  'canonical reference owns owner-section placement'
require_fixed "$FORMAT" '```markdown ### No decision needed — no changes made' \
  'compact response example is fenced'
require_fixed "$FORMAT" '```markdown ### Your decision needed' \
  'owner-decision example is fenced'
require_fixed "$FORMAT" 'Expand' 'compact findings can be expanded'
require_fixed "$FORMAT" 'Never use `REJECT` or `DEFER` to silently choose product behavior, scope, or architecture' 'classifications cannot hide owner decisions'
require_fixed "$FORMAT" 'do not repeat the detailed report by default' 'detailed evidence stays available without repetition'
require_fixed "$FORMAT" 'readiness line' 'readiness guidance is documented'
require_fixed "$FORMAT" 'Include a readiness line only when it adds information' 'readiness is included only when informative'
require_fixed "$FORMAT" 'Automated test failures are evidence' 'test failures require classification'
require_fixed "$FORMAT" 'reviewed change, a stale expectation, the environment, or pre-existing behavior' 'test failure sources are investigated completely'
forbid_fixed "$FORMAT" 'skills/code-review' 'shared contract does not couple to code review producer paths'
forbid_fixed "$FORMAT" 'skills/reviewing-plans' 'shared contract does not couple to plan review producer paths'

USING="$ROOT/skills/using-joshix/SKILL.md"
RECEIVERS=(
  "$ROOT/skills/receiving-code-review/SKILL.md"
  "$ROOT/skills/receiving-plan-review/SKILL.md"
  "$ROOT/skills/receiving-spec-review/SKILL.md"
)
for skill in "${RECEIVERS[@]}"; do
  require_fixed "$skill" 'using-joshix/references/review-response-format.md' \
    "$(basename "$(dirname "$skill")") links canonical receiver format"
  require_fixed "$skill" 'Owner Decision Gate' \
    "$(basename "$(dirname "$skill")") defines the owner gate"
  require_fixed "$skill" 'canonical reference owns the exact presentation grammar' \
    "$(basename "$(dirname "$skill")") delegates exact grammar to the canonical reference"
  forbid_fixed "$skill" 'One decision remains.' \
    "$(basename "$(dirname "$skill")") does not duplicate the canonical remaining-count sentence"
  forbid_fixed "$skill" 'first non-empty line after `### Your decision needed`' \
    "$(basename "$(dirname "$skill")") does not duplicate canonical name placement"
done

require_fixed "$USING" 'code review feedback, review comments, a pasted agent review, or critique of code changes' \
  'bootstrap preserves the complete review trigger surface'
require_fixed "$USING" 'before any implementation skill, TDD step, file edit, or test-writing step' \
  'bootstrap preserves the complete pre-edit gate'
require_fixed "$USING" 'receiving-code-review` for code' \
  'bootstrap routes code reviews explicitly'
require_fixed "$USING" 'receiving-plan-review` for plans' \
  'bootstrap routes plan reviews explicitly'
require_fixed "$USING" 'receiving-spec-review` for specs' \
  'bootstrap routes spec reviews explicitly'
require_fixed "$USING" 'first emitted agent sentence' \
  'bootstrap preserves exact review-only openings before announcements'
require_fixed "$USING" 'shared-task notice follows' \
  'bootstrap preserves the task-context notice after the exact opening'
forbid_fixed "$USING" 'task-context announcement; the exact sentence itself is' \
  'bootstrap does not imply the exact opening replaces task-context notices'
require_fixed "$USING" "I'm reviewing the review as feedback to evaluate, not as approval to edit files." \
  'bootstrap carries the exact code-review opening'
require_fixed "$USING" "I'm reviewing the plan review as feedback to evaluate, not as approval to edit the plan." \
  'bootstrap carries the exact plan-review opening'
require_fixed "$USING" "I'm reviewing the spec review as feedback to evaluate, not as approval to edit the spec." \
  'bootstrap carries the exact spec-review opening'
require_fixed "${RECEIVERS[0]}" 'code review comments, pasted agent code reviews' \
  'code receiver metadata is code-specific'
forbid_fixed "${RECEIVERS[0]}" 'review comments, pasted agent reviews' \
  'code receiver metadata no longer claims generic agent reviews'
forbid_fixed "${RECEIVERS[0]}" "I'll review this feedback item by item before making any changes." \
  'code receiver permits only the exact review-only opening'

require_fixed "${RECEIVERS[0]}" 'Product/owner decisions' \
  'code reception identifies product decisions in its gate'
require_fixed "${RECEIVERS[0]}" 'Architecture decisions' \
  'code reception identifies architecture decisions in its gate'
require_fixed "${RECEIVERS[0]}" 'ask only the next owner question' \
  'code reception serializes owner questions'
require_fixed "${RECEIVERS[0]}" 'how many decisions remain' \
  'code reception reports the remaining owner-decision count'
require_fixed "${RECEIVERS[0]}" 'Do not preview or bundle later decisions' \
  'code reception hides later owner decisions until their turn'
require_fixed "${RECEIVERS[0]}" 'Each independently requested architecture change is a separate owner decision' \
  'code reception does not collapse independent architecture requests'
require_fixed "${RECEIVERS[1]}" 'New product behavior, scope, ownership, or architecture requested' \
  'plan reception connects new decisions to its gate'
require_fixed "${RECEIVERS[2]}" 'New product behavior, scope, acceptance criteria, ownership, or architecture requires Josh' \
  'spec reception connects new decisions to Josh approval'
forbid_fixed "${RECEIVERS[0]}" 'complete verified independent objective fixes before responding' \
  'code reception does not duplicate its mandatory objective-work-first rule'
forbid_fixed "${RECEIVERS[1]}" 'Do not split an existing step' \
  'plan reception does not encode a fixture-shaped heading ban'
forbid_fixed "${RECEIVERS[1]}" 'put the failing command inside the moved test step' \
  'plan reception does not encode a fixture-specific command placement'

HELPERS="$ROOT/tests/codex/test-helpers.sh"
RECEIVER_TESTS=(
  "$ROOT/tests/codex/test-receiving-code-review-review-review.sh"
  "$ROOT/tests/codex/test-receiving-plan-review-review-review.sh"
  "$ROOT/tests/codex/test-receiving-spec-review-review-review.sh"
  "$ROOT/tests/codex/test-receiving-code-review-owner-decision-gate-behavior.sh"
  "$ROOT/tests/codex/test-receiving-plan-review-owner-decision-gate-behavior.sh"
  "$ROOT/tests/codex/test-receiving-spec-review-owner-decision-gate-behavior.sh"
)
REVIEW_ONLY_RECEIVER_TESTS=(
  "$ROOT/tests/codex/test-receiving-code-review-review-review.sh"
  "$ROOT/tests/codex/test-receiving-plan-review-review-review.sh"
  "$ROOT/tests/codex/test-receiving-spec-review-review-review.sh"
)
VALIDATORS=(
  validate_compact_bounds
  validate_owner_options
  validate_single_owner_lane
  validate_owner_structure
)
for validator in "${VALIDATORS[@]}"; do
  require_fixed "$HELPERS" "$validator()" "$validator is owned by the shared Codex test helper"
done
for test_file in "${RECEIVER_TESTS[@]}"; do
  require_fixed "$test_file" 'source "$SCRIPT_DIR/test-helpers.sh"' \
    "$(basename "$test_file") sources shared validators"
  for validator in "${VALIDATORS[@]}"; do
    forbid_fixed "$test_file" "$validator()" \
      "$(basename "$test_file") does not duplicate $validator"
  done
done
require_fixed "$HELPERS" 'first_nonempty_trimmed_line()' \
  'shared helper owns normalized first-line extraction'
for test_file in "${REVIEW_ONLY_RECEIVER_TESTS[@]}"; do
  require_fixed "$test_file" 'FIRST_NONEMPTY_LINE="$(first_nonempty_trimmed_line < "$FINAL_FILE")"' \
    "$(basename "$test_file") checks the normalized first final line"
  require_fixed "$test_file" '| first_nonempty_trimmed_line)"' \
    "$(basename "$test_file") normalizes the first emitted sentence"
done

TRIMMED_FIRST_LINE="$(printf '\nMode sentence   \t\nLater line\n' | first_nonempty_trimmed_line)"
if [ "$TRIMMED_FIRST_LINE" != 'Mode sentence' ]; then
  printf 'FAIL: normalized first-line extraction\nActual: <%s>\n' "$TRIMMED_FIRST_LINE"
  exit 1
fi
forbid_fixed "$ROOT/tests/codex/test-receiving-plan-review-owner-decision-gate-behavior.sh" \
  'Reorders only the two original step headings' \
  'plan owner behavior test does not pin the fixture to exactly two headings'

require_fixed "$ROOT/AGENTS.md" 'joshix:receiving-spec-review' \
  'repository guidance routes received spec reviews'
require_fixed "$ROOT/CLAUDE.md" 'joshix:receiving-spec-review' \
  'Claude guidance routes received spec reviews'
require_fixed "$ROOT/AGENTS.md" 'first emitted agent sentence' \
  'repository guidance protects review-only openings before skill announcements'
require_fixed "$ROOT/CLAUDE.md" 'first emitted agent sentence' \
  'Claude guidance protects review-only openings before skill announcements'
require_fixed "$ROOT/AGENTS.md" 'first non-empty line of the final response' \
  'repository guidance repeats the exact opening in final output'
require_fixed "$ROOT/CLAUDE.md" 'first non-empty line of the final response' \
  'Claude guidance repeats the exact opening in final output'
require_fixed "$ROOT/AGENTS.md" 'replaces the generic skill announcement' \
  'repository guidance narrows what the exact opening replaces'
require_fixed "$ROOT/CLAUDE.md" 'replaces the generic skill announcement' \
  'Claude guidance narrows what the exact opening replaces'
require_fixed "$ROOT/AGENTS.md" 'shared-task notice still follows' \
  'repository guidance preserves the task-context notice'
require_fixed "$ROOT/CLAUDE.md" 'shared-task notice still follows' \
  'Claude guidance preserves the task-context notice'
forbid_fixed "$ROOT/AGENTS.md" 'satisfies every skill, workflow, repository-context, and task-context announcement requirement' \
  'repository guidance does not waive task-context announcements'
forbid_fixed "$ROOT/CLAUDE.md" 'satisfies every skill, workflow, repository-context, and task-context announcement requirement' \
  'Claude guidance does not waive task-context announcements'
require_fixed "$ROOT/AGENTS.md" "I'm reviewing the review as feedback to evaluate, not as approval to edit files." \
  'repository guidance carries the exact code-review opening'
require_fixed "$ROOT/AGENTS.md" "I'm reviewing the plan review as feedback to evaluate, not as approval to edit the plan." \
  'repository guidance carries the exact plan-review opening'
require_fixed "$ROOT/AGENTS.md" "I'm reviewing the spec review as feedback to evaluate, not as approval to edit the spec." \
  'repository guidance carries the exact spec-review opening'
require_fixed "$ROOT/CLAUDE.md" "I'm reviewing the review as feedback to evaluate, not as approval to edit files." \
  'Claude guidance carries the exact code-review opening'
require_fixed "$ROOT/CLAUDE.md" "I'm reviewing the plan review as feedback to evaluate, not as approval to edit the plan." \
  'Claude guidance carries the exact plan-review opening'
require_fixed "$ROOT/CLAUDE.md" "I'm reviewing the spec review as feedback to evaluate, not as approval to edit the spec." \
  'Claude guidance carries the exact spec-review opening'

echo 'STATUS: PASSED'
