#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$ROOT/skills/using-joshix/references/workflow-policy.md"
BOOTSTRAP="$ROOT/skills/using-joshix/SKILL.md"

normalized_file() { tr '\n\r\t' '   ' < "$1" | tr -s ' '; }
require_fixed() {
  local file="$1" text="$2" label="$3"
  [ -f "$file" ] || { printf 'FAIL: %s (missing %s)\n' "$label" "$file"; exit 1; }
  [[ "$(normalized_file "$file")" == *"$text"* ]] \
    || { printf 'FAIL: %s\nMissing: %s\n' "$label" "$text"; exit 1; }
}
reject_fixed() {
  local file="$1" text="$2" label="$3"
  [ -f "$file" ] || return 0
  [[ "$(normalized_file "$file")" != *"$text"* ]] \
    || { printf 'FAIL: %s\nUnexpected: %s\n' "$label" "$text"; exit 1; }
}

require_fixed "$POLICY" 'joshix-workflow-policy:' 'exact activation marker'
require_fixed "$POLICY" 'trivial' 'fixed trivial complexity'
require_fixed "$POLICY" 'routine' 'fixed routine complexity'
require_fixed "$POLICY" 'complex' 'fixed complex complexity'
require_fixed "$POLICY" 'Criticality and complexity are independent' 'axes stay independent'
require_fixed "$POLICY" 'Complexity determines which planning artifacts exist; it does not determine whether an existing artifact is reviewed.' 'complexity selects artifacts while review follows them'
reject_fixed "$POLICY" 'reviewed slices' 'complexity does not mandate slice review'
require_fixed "$POLICY" 'highest-criticality changed surface' 'mixed-surface review rigor'
require_fixed "$POLICY" 'surface-specific' 'surface tests and finding comparisons'
require_fixed "$POLICY" 'Leave it unchanged unless the owner authorizes that additional scope.' 'lower findings stay outside authorized scope'
require_fixed "$POLICY" 'bubble up immediately' 'higher findings stop work'
require_fixed "$POLICY" 'focused checks' 'interim verification budget'
require_fixed "$POLICY" 'full completion gates once' 'single final full gate'
require_fixed "$POLICY" 'requested outcome and authorized scope' 'scope guard'
require_fixed "$POLICY" 'Policy absent' 'legacy branch is explicit'
reject_fixed "$POLICY" 'joshix-cross-provider-review:' 'workflow policy cannot authorize providers'
reject_fixed "$POLICY" 'active-work effort estimate' 'policy has no AI duration estimate'
reject_fixed "$POLICY" 'Active-time alarm' 'policy has no elapsed-time governance'
reject_fixed "$POLICY" 'task-context `elapsed` query' 'policy does not query elapsed time'
reject_fixed "$POLICY" 'external-wait' 'policy has no wait timing protocol'
reject_fixed "$POLICY" 'twice the declared estimate' 'policy has no cost alarm'
reject_fixed "$POLICY" 'active-start' 'old active timer transition is removed'
reject_fixed "$POLICY" 'active-stop' 'old active timer stop transition is removed'
reject_fixed "$POLICY" 'blocked-owner' 'old owner timer transition is removed'
reject_fixed "$POLICY" 'blocked-external' 'old external timer transition is removed'
reject_fixed "$POLICY" 're-review changed work, then rerun only the failed required gate' 'workflow policy no longer has unconditional post-signoff rereview'
require_fixed "$POLICY" 'autonomous-review.md' 'workflow policy delegates completion recovery to the central contract'
require_fixed "$POLICY" 'The reviewer supplies evidence and a recommendation.' 'policy keeps reviewer output evidence-only'
require_fixed "$POLICY" 'The coordinator verifies the evidence' 'policy leaves governance classification to the coordinator'
require_fixed "$POLICY" 'artifact materially changes or new evidence appears' 'policy requires semantic progress before rereview'
for removed in 'correction round' 'recovery repair' 'pass ceiling'; do
  reject_fixed "$POLICY" "$removed" "policy has no review-engine concept: $removed"
done
require_fixed "$ROOT/skills/brainstorming/SKILL.md" 'Routine design-note terminal' 'routine brainstorming has a terminal branch'
require_fixed "$ROOT/skills/writing-plans/SKILL.md" 'Routine short-plan terminal' 'routine planning has a terminal branch'
reject_fixed "$BOOTSTRAP" 'highest = ' 'bootstrap does not hardcode tiers'
reject_fixed "$BOOTSTRAP" 'AGENTS.md, CLAUDE.md' 'bootstrap does not hardcode host filenames'
reject_fixed "$BOOTSTRAP" '## The Rule' 'bootstrap removes duplicated skill rule'
require_fixed "$BOOTSTRAP" "If an invoked skill turns out to be wrong for the situation, you don't need to use it." 'bootstrap keeps the skill escape hatch'
require_fixed "$BOOTSTRAP" 'Rigid skills are exact; flexible skills adapt their principles to context.' 'bootstrap preserves skill-type guidance'
reject_fixed "$BOOTSTRAP" 'The skill itself tells you which.' 'bootstrap has no orphaned skill-type sentence'

router_words="$({
  sed -n '/<SUBAGENT-STOP>/,/<\/SUBAGENT-STOP>/p' "$BOOTSTRAP"
  sed -n '/<WORKFLOW-POLICY>/,/<\/WORKFLOW-POLICY>/p' "$BOOTSTRAP"
} | wc -w | tr -d '[:space:]')"
[ "$router_words" -le 80 ] \
  || { printf 'FAIL: bootstrap routers exceed 80 words (%s)\n' "$router_words"; exit 1; }

echo 'STATUS: PASSED'
