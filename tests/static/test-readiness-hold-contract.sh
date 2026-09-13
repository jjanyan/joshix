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

reject_fixed "$FORMAT" 'Ready to plan; waiting for your command.' 'no routine planning hold'
require_fixed "$FORMAT" 'Spec-to-plan continuation is automatic' 'planning continues automatically'
require_fixed "$FORMAT" 'Ready to execute; waiting for your command.' 'plan readiness hold'
require_fixed "$FORMAT" 'Approval is not implementation authorization.' 'phase boundary is explicit'
require_fixed "$FORMAT" 'A readiness hold is local to the reviewed artifact and its immediate next phase.' 'readiness hold is artifact-local'
require_fixed "$FORMAT" 'Never infer a readiness hold from another queued task, plan, or artifact.' 'queued work cannot leak readiness'
require_fixed "$FORMAT" 'Never append one after implementation or code-review completion.' 'completion cannot emit readiness hold'
require_fixed "$CONTRACT" 'never manufacture owner options or borrow readiness from queued work.' 'reception table keeps readiness artifact-local'
require_fixed "$CONTRACT" 'Other approval reports do not inherit a hold from queued work.' 'other approvals cannot inherit readiness'
require_fixed "$BRAINSTORMING" 'continue directly into writing-plans' 'brainstorming continues into planning'
require_fixed "$BRAINSTORMING" 'Explicit spec-only, review-only, or stop instructions remain effective' 'explicit stops remain effective'
require_fixed "$ROOT/skills/using-joshix/references/workflow-policy.md" 'Stop policy activation and ask one owner question using `owner-question-format.md`.' 'invalid policy routes to the shared question template'
require_fixed "$WRITING_PLANS" 'Ready to execute; waiting for your command.' 'planning holds before execution'
reject_fixed "$WRITING_PLANS" 'Proceed with the recommended approach, or use the other one?' 'no fabricated execution decision'

echo 'STATUS: PASSED'
