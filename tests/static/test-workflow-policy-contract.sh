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
reject_fixed "$POLICY" 'reviewed spec' 'complexity does not mandate spec review'
reject_fixed "$POLICY" 'reviewed slices' 'complexity does not mandate slice review'
require_fixed "$POLICY" 'highest-criticality changed surface' 'mixed-surface review rigor'
require_fixed "$POLICY" 'surface-specific' 'surface tests and finding comparisons'
require_fixed "$POLICY" 'deferred observation' 'lower findings are recorded'
require_fixed "$POLICY" 'bubble up immediately' 'higher findings stop work'
require_fixed "$POLICY" 'focused checks' 'interim verification budget'
require_fixed "$POLICY" 'full completion gates once' 'single final full gate'
require_fixed "$POLICY" 'requested outcome and authorized scope' 'scope guard'
require_fixed "$POLICY" 'twice the declared estimate' 'cost alarm'
require_fixed "$POLICY" 'Policy absent' 'legacy branch is explicit'
reject_fixed "$POLICY" 'joshix-cross-provider-review:' 'workflow policy cannot authorize providers'
require_fixed "$POLICY" 'task-context `elapsed` query' 'cost alarm uses one read-only elapsed query'
require_fixed "$POLICY" 'before a new work unit, review dispatch, or recovery' 'elapsed is checked only at meaningful boundaries'
require_fixed "$POLICY" 'Owner gaps represented by exact external-wait metadata are excluded' 'owner wait is excluded without timer events'
require_fixed "$POLICY" 'no timer, poller, daemon, or routine timing event' 'active time adds no ongoing bookkeeping loop'
reject_fixed "$POLICY" 'active-start' 'old active timer transition is removed'
reject_fixed "$POLICY" 'active-stop' 'old active timer stop transition is removed'
reject_fixed "$POLICY" 'blocked-owner' 'old owner timer transition is removed'
reject_fixed "$POLICY" 'blocked-external' 'old external timer transition is removed'
reject_fixed "$POLICY" 're-review changed work, then rerun only the failed required gate' 'workflow policy no longer has unconditional post-signoff rereview'
require_fixed "$POLICY" 'autonomous-review.md' 'workflow policy delegates completion recovery to the central contract'
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
