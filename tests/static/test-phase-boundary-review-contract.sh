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

require_fixed "$POLICY" \
  'review a written spec before planning, review a written implementation plan before execution, and review the completed implementation before a completion claim' \
  'policy defines the three core phase boundaries'
require_fixed "$POLICY" \
  'Complexity determines which planning artifacts exist; it does not determine whether an existing artifact is reviewed.' \
  'complexity selects artifacts rather than review suppression'
require_fixed "$POLICY" \
  'Criticality controls test depth and may add review gates; it does not remove a core phase-boundary review.' \
  'tiers add rigor without suppressing core reviews'
require_fixed "$POLICY" \
  'only by naming that boundary' \
  'explicit instructions can name a boundary override'
require_fixed "$POLICY" \
  'A core phase boundary is satisfied by provider approval.' \
  'provider approval satisfies every core boundary'
require_fixed "$POLICY" \
  'A semantic stop without approval leaves the boundary blocked until material change, new evidence, or an explicit owner instruction naming that boundary.' \
  'semantic stops remain finite without pretending to approve'
require_fixed "$POLICY" \
  'A tier-required review at the same artifact boundary is satisfied by the core review; only a separately named, distinct gate adds another review.' \
  'core review also satisfies an equivalent tier gate'

require_fixed "$BRAINSTORMING" \
  'review the written spec through `../using-joshix/references/autonomous-review.md`' \
  'brainstorming owns active-policy spec review'
require_fixed "$BRAINSTORMING" \
  'unless an explicit owner or repository instruction names the spec boundary' \
  'spec producer preserves the named boundary override'
require_order "$BRAINSTORMING" \
  '**Spec self-review**' '**Opposite-provider spec review**' \
  'spec review follows self-review'
require_order "$BRAINSTORMING" \
  '**Opposite-provider spec review**' '**Continue to planning automatically**' \
  'spec review precedes automatic planning'

require_fixed "$WRITING" \
  'owner-supplied named spec' \
  'planning has a supplied-spec entry backstop'
require_fixed "$WRITING" \
  'opposite-provider approval of the unchanged spec or an explicit owner or repository instruction naming the spec boundary' \
  'supplied-spec backstop checks boundary satisfaction'
require_fixed "$WRITING" \
  'If neither exists and no opposite-provider review of the unchanged spec is recorded, review that spec' \
  'supplied-spec backstop avoids duplicate review after a semantic stop'
require_fixed "$WRITING" \
  'Spec boundary blocked: opposite-provider approval is absent and no explicit owner or repository instruction names the spec boundary.' \
  'supplied-spec backstop has a blocked terminal'
require_fixed "$WRITING" \
  'review the written implementation plan through `../using-joshix/references/autonomous-review.md`' \
  'writing-plans owns active-policy plan review'
require_fixed "$WRITING" \
  'unless an explicit owner or repository instruction names the plan boundary' \
  'plan producer preserves the named boundary override'
require_order "$WRITING" \
  'Self-review for ambiguity, missing coverage, and scope growth' \
  'review the written implementation plan' \
  'routine plan review follows self-review'
require_order "$WRITING" \
  'review the written implementation plan' \
  '`Ready to execute; waiting for your command.`' \
  'plan review precedes execution hold'

require_fixed "$EXECUTING" \
  'Before the first implementation edit from an owner-supplied named plan' \
  'execution has a supplied-plan entry backstop'
require_fixed "$EXECUTING" \
  'opposite-provider approval of the unchanged plan or an explicit owner or repository instruction naming the plan boundary' \
  'inline supplied-plan backstop checks boundary satisfaction'
require_fixed "$EXECUTING" \
  'If neither exists and no opposite-provider review of the unchanged plan is recorded, review the plan' \
  'inline supplied-plan backstop avoids duplicate review after a semantic stop'
require_fixed "$EXECUTING" \
  'Plan boundary blocked: opposite-provider approval is absent and no explicit owner or repository instruction names the plan boundary.' \
  'inline supplied-plan backstop has a blocked terminal'
require_fixed "$EXECUTING" \
  'one core whole-change review of the completed implementation, plus any distinct tier-added whole-change gate' \
  'inline execution owns final core review'
require_fixed "$EXECUTING" \
  'unless an explicit owner or repository instruction names the completed-implementation boundary' \
  'inline execution preserves the named final boundary override'
require_fixed "$SUBAGENT" \
  'first execution entry, it owns the one core whole-change review' \
  'subagent execution preserves one outer review'
require_fixed "$SUBAGENT" \
  'It then invokes `joshix:verification-before-completion` for broad/full completion verification once after review sign-off or that named override.' \
  'direct subagent execution invokes the completion backstop owner'
require_fixed "$SUBAGENT" \
  'Before dispatch or the first implementation edit from an owner-supplied named plan' \
  'subagent execution has a supplied-plan entry backstop'
require_fixed "$SUBAGENT" \
  'opposite-provider approval of the unchanged plan or an explicit owner or repository instruction naming the plan boundary' \
  'subagent supplied-plan backstop checks boundary satisfaction'
require_fixed "$SUBAGENT" \
  'If neither exists and no opposite-provider review of the unchanged plan is recorded, review the plan' \
  'subagent supplied-plan backstop avoids duplicate review after a semantic stop'
require_fixed "$SUBAGENT" \
  'Plan boundary blocked: opposite-provider approval is absent and no explicit owner or repository instruction names the plan boundary.' \
  'subagent supplied-plan backstop has a blocked terminal'
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
require_fixed "$BRAINSTORMING" \
  'Spec boundary blocked: opposite-provider approval is absent and no explicit owner or repository instruction names the spec boundary.' \
  'unapproved spec has a blocked terminal'
require_fixed "$BRAINSTORMING" \
  '**Continue to planning automatically**' \
  'brainstorming checklist continues only after reviews'
require_fixed "$BRAINSTORMING" \
  '"Spec boundary satisfied?" -> "Stop at blocked spec boundary" [label="no"]' \
  'brainstorming graph has a blocked spec branch'
require_fixed "$VERIFYING" \
  'A correction that materially changes implementation behavior or scope requires a fresh core review before any completion claim.' \
  'material post-review corrections return through code review'
require_fixed "$WRITING" \
  '### Policy-absent plan review heuristic' \
  'plan-review skip heuristic is explicitly policy-absent'
require_fixed "$WRITING" \
  'Under an active policy, do not use this heuristic or its skip disclosure.' \
  'active policy cannot inherit the policy-absent skip'
require_fixed "$WRITING" \
  'Core plan review approved and accounted for.' \
  'active policy defines its execution-handoff disclosure'
require_fixed "$WRITING" \
  'Plan boundary blocked: opposite-provider approval is absent and no explicit owner or repository instruction names the plan boundary.' \
  'active policy defines its blocked plan disclosure'
require_order "$WRITING" \
  'Continue only with provider approval or that named override' \
  '`Ready to execute; waiting for your command.`' \
  'routine plan approval condition precedes readiness'
require_fixed "$VERIFYING" \
  'When this task materially changed any repository surface' \
  'no-change completion claims skip the implementation-review backstop'
reject_fixed "$VERIFYING" \
  'materially changed repository code' \
  'non-code material changes remain inside the review backstop'
require_order "$FORMAT" \
  'end exactly:' \
  '`Ready to execute; waiting for your command.`' \
  'readiness literal immediately follows the hold introduction'
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
reject_fixed "$PARALLEL" \
  'run broad/full completion checks once' \
  'parallel dispatcher does not run caller-owned completion gates'
require_fixed "$SUBAGENT" \
  'Active policy uses the installed `joshix-review review` operation and its structured result' \
  'active-policy final review uses the thin bridge result'
require_fixed "$SUBAGENT" \
  'Policy absent — final reviewer template' \
  'quality outcome template is scoped to policy absence'
require_fixed "$SUBAGENT" \
  'Active policy — final reviewer transport' \
  'active transport has its own section'
require_fixed "$SUBAGENT" \
  'Implementer return and deferred checks' \
  'mode-neutral controller rules have a neutral section'
require_order "$SUBAGENT" \
  '### Implementer return and deferred checks' \
  '### Policy absent — final reviewer template' \
  'mode-neutral return rules precede policy-specific templates'
require_order "$SUBAGENT" \
  '### Policy absent — final reviewer template' \
  '### Active policy — final reviewer transport' \
  'policy-specific final-review sections are siblings'
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

reject_fixed "$WRITING" \
  'request independent plan review only when the task-level tier selects that existing gate' \
  'tier cannot suppress plan review'
reject_fixed "$WRITING" \
  'records opposite-provider review of the unchanged spec' \
  'recorded review alone cannot discharge supplied-spec boundary'
reject_fixed "$EXECUTING" \
  'each task-level tier-selected whole-change gate' \
  'tier cannot suppress inline final review'
reject_fixed "$EXECUTING" \
  'records opposite-provider review of the unchanged plan' \
  'recorded review alone cannot discharge inline supplied-plan boundary'
reject_fixed "$SUBAGENT" \
  'records opposite-provider review of the unchanged plan' \
  'recorded review alone cannot discharge subagent supplied-plan boundary'
reject_fixed "$REQUESTING" \
  'Use only the review gates required by the task-level tier' \
  'tier cannot suppress requesting-code-review core gate'
reject_fixed "$PARALLEL" \
  'perform only the tier-selected whole-change review' \
  'tier cannot suppress parallel final review'
reject_fixed "$SUBAGENT" \
  'perform a final whole-change review only when the policy-absent workflow or active tier requires it' \
  'tier cannot suppress subagent final review'

echo 'STATUS: PASSED'
