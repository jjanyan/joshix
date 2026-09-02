#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FORMAT="$ROOT/skills/using-joshix/references/review-response-format.md"
CONTRACT="$ROOT/skills/using-joshix/references/review-reception-contract.md"
WRITING_PLANS="$ROOT/skills/writing-plans/SKILL.md"
BRAINSTORMING="$ROOT/skills/brainstorming/SKILL.md"

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

require_fixed "$FORMAT" 'Ready to plan; waiting for your command.' 'spec readiness hold'
require_fixed "$FORMAT" 'Ready to execute; waiting for your command.' 'plan readiness hold'
require_fixed "$FORMAT" 'Approval is not authorization for the next phase.' 'phase boundary is explicit'
require_fixed "$FORMAT" 'A readiness hold is local to the reviewed artifact and its immediate next phase.' 'readiness hold is artifact-local'
require_fixed "$FORMAT" 'Never infer a readiness hold from another queued task, plan, or artifact.' 'queued work cannot leak readiness'
require_fixed "$FORMAT" 'Never append one after implementation or code-review completion.' 'completion cannot emit readiness hold'
require_fixed "$CONTRACT" 'never manufacture owner options or borrow readiness from queued work.' 'reception table keeps readiness artifact-local'
require_fixed "$CONTRACT" 'Other approval reports do not inherit a hold from queued work.' 'other approvals cannot inherit readiness'
require_fixed "$BRAINSTORMING" 'Ready to plan; waiting for your command.' 'brainstorming holds before planning'
require_fixed "$WRITING_PLANS" 'Ready to execute; waiting for your command.' 'planning holds before execution'
reject_fixed "$WRITING_PLANS" 'Proceed with the recommended approach, or use the other one?' 'no fabricated execution decision'

echo 'STATUS: PASSED'
