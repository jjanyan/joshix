#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$ROOT/skills/using-joshix/references/workflow-policy.md"
BRAINSTORMING="$ROOT/skills/brainstorming/SKILL.md"
WRITING="$ROOT/skills/writing-plans/SKILL.md"
EXECUTING="$ROOT/skills/executing-plans/SKILL.md"
SUBAGENT="$ROOT/skills/subagent-driven-development/SKILL.md"
PARALLEL="$ROOT/skills/dispatching-parallel-agents/SKILL.md"
REQUESTING="$ROOT/skills/requesting-code-review/SKILL.md"
VERIFYING="$ROOT/skills/verification-before-completion/SKILL.md"
FORMAT="$ROOT/skills/using-joshix/references/review-response-format.md"

normalized_file() { tr '\n\r\t' '   ' < "$1" | tr -s ' '; }
require_fixed() {
  local file="$1" text="$2" label="$3"
  [[ "$(normalized_file "$file")" == *"$text"* ]] \
    || { printf 'FAIL: %s\nMissing: %s\n' "$label" "$text"; exit 1; }
}
reject_fixed() {
  local file="$1" text="$2" label="$3"
  [[ "$(normalized_file "$file")" != *"$text"* ]] \
    || { printf 'FAIL: %s\nUnexpected: %s\n' "$label" "$text"; exit 1; }
}
require_order() {
  local file="$1" first="$2" second="$3" label="$4" content
  content="$(normalized_file "$file")"
  [[ "$content" == *"$first"*"$second"* ]] \
    || { printf 'FAIL: %s\nExpected order: %s -> %s\n' "$label" "$first" "$second"; exit 1; }
}

BOOTSTRAP="$ROOT/skills/using-joshix/SKILL.md"
require_fixed "$BOOTSTRAP" '## Work and review' 'one central ceremony selector'
require_fixed "$BOOTSTRAP" 'A plan file, file count, or task count alone does not require it.' 'artifact presence does not create advance review'
require_fixed "$BOOTSTRAP" 'Preserve tier-required gates.' 'explicit risk gates remain binding'
require_fixed "$BOOTSTRAP" 'Required review needs approval or an explicit owner override of that review' 'required gates need approval'
require_fixed "$BOOTSTRAP" 'Extending a preview does not start completion review.' 'preview retains its phase'
require_fixed "$POLICY" 'including for owner-supplied specs and plans' 'supplied artifacts use the same selector'
require_fixed "$POLICY" 'A semantic stop without approval leaves a required gate blocked' 'unapproved required gate remains blocked'
require_fixed "$POLICY" 'An equivalent tier review satisfies the same gate' 'equivalent final gates coalesce'
for file in "$BRAINSTORMING" "$WRITING" "$EXECUTING" "$SUBAGENT"; do
  require_fixed "$file" 'Work and review' 'workflow routes to the central selector'
  reject_fixed "$file" 'If neither exists and no opposite-provider review' 'unconditional supplied-artifact backstop removed'
done
require_fixed "$WRITING" 'If review is required, confirm its approval' 'required supplied-spec gate remains enforced'
require_fixed "$EXECUTING" 'obtain that review before retained implementation' 'required supplied-plan gate remains enforced'
require_fixed "$BRAINSTORMING" 'A required unapproved review blocks its dependent phase' 'selected spec review blocks its dependent phase'
require_fixed "$SUBAGENT" 'one core whole-change review' 'outer completed-change review remains'
require_fixed "$EXECUTING" 'one core whole-change review' 'inline completed-change review remains'
require_fixed "$VERIFYING" 'Completed-implementation boundary blocked:' 'unapproved final gate has a blocked terminal'

require_fixed "$EXECUTING" \
  'one core whole-change review of the completed implementation, plus any distinct tier-added whole-change gate' \
  'inline execution owns final core review'
require_fixed "$SUBAGENT" \
  'first execution entry, it owns the one core whole-change review' \
  'subagent execution preserves one outer review'
require_fixed "$SUBAGENT" \
  'It then invokes `joshix:verification-before-completion` for broad/full completion verification once after review sign-off or that named override.' \
  'direct subagent execution invokes the completion backstop owner'
require_fixed "$SUBAGENT" \
  'run only tier-selected gates inside each lane; the outer core final review remains required' \
  'tier selection is confined to additional lane review'
require_fixed "$PARALLEL" \
  'The caller owns core and tier-added whole-change review plus broad/full completion verification' \
  'parallel execution preserves the outer review'
require_fixed "$REQUESTING" \
  'run the core completed-implementation review once unless an explicit owner or repository instruction names that boundary' \
  'requesting-code-review treats final review as core'
require_fixed "$REQUESTING" \
  'it does not suppress or duplicate the core review.' \
  'requesting-code-review coalesces equivalent tier review'
require_fixed "$VERIFYING" \
  'confirm that the core completed-implementation review has been approved for the current material state or an explicit owner or repository instruction names the completed-implementation boundary' \
  'completion verification backstops final review'
require_fixed "$VERIFYING" \
  'If no core completed-implementation review is recorded for the current material state and no explicit owner or repository instruction names the completed-implementation boundary, invoke `joshix:requesting-code-review` as the backstop.' \
  'completion backstop runs only when review is missing'
require_fixed "$VERIFYING" \
  'Completed-implementation boundary blocked: opposite-provider approval is absent and no explicit owner or repository instruction names the completed-implementation boundary.' \
  'unapproved completed implementation has a blocked terminal'
require_fixed "$VERIFYING" \
  'A correction that materially changes implementation behavior or scope requires a fresh core review before any completion claim.' \
  'material post-review corrections return through code review'
require_fixed "$VERIFYING" \
  'When this task materially changed any repository surface' \
  'no-change completion claims skip the implementation-review backstop'
reject_fixed "$FORMAT" \
  'semantic stop on an unchanged artifact may use the same artifact-local hold' \
  'semantic stop cannot masquerade as reviewed-artifact readiness'
require_fixed "$SUBAGENT" \
  'When entered from `executing-plans`, that caller remains outer and retains the core final review' \
  'routed execution has one explicit final-review owner'
require_fixed "$EXECUTING" \
  'delegates task execution while this skill retains the core final review and Step 3' \
  'executing-plans keeps caller-side routed review ownership'
require_fixed "$SUBAGENT" \
  'When entered from `executing-plans`, return after serial integration and lane verification; the caller owns core review and full completion verification.' \
  'nested subagent execution returns before caller-owned completion gates'
require_fixed "$PARALLEL" \
  'return to the caller after serial integration' \
  'parallel dispatcher returns before caller-owned completion gates'
require_fixed "$SUBAGENT" \
  'Active policy uses the installed `joshix-review review` operation and its structured result' \
  'active-policy final review uses the thin bridge result'
reject_fixed "$SUBAGENT" \
  'or when active policy requires its core final review or a tier-added gate' \
  'active-policy core review cannot enter the legacy final-line loop'

for file in "$POLICY" "$BRAINSTORMING" "$WRITING" "$EXECUTING" \
  "$SUBAGENT" "$PARALLEL" "$REQUESTING" "$VERIFYING"; do
  if rg -n '[[:alnum:]]-$' "$file" >/dev/null; then
    printf 'FAIL: agent-facing compound is split across lines in %s\n' "$file"
    exit 1
  fi
done

echo 'STATUS: PASSED'
