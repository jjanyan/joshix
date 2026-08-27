#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CODE_REVIEW="$ROOT/skills/code-review/SKILL.md"
PLAN_REVIEW="$ROOT/skills/reviewing-plans/SKILL.md"
REQUESTING="$ROOT/skills/requesting-code-review/SKILL.md"
CODE_TEMPLATE="$ROOT/skills/requesting-code-review/code-reviewer.md"
PLAN_TEMPLATE="$ROOT/skills/writing-plans/plan-document-reviewer-prompt.md"
SPEC_TEMPLATE="$ROOT/skills/brainstorming/spec-document-reviewer-prompt.md"
QUALITY_TEMPLATE="$ROOT/skills/subagent-driven-development/code-quality-reviewer-prompt.md"

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

require_fixed "$CODE_REVIEW" '# Code Review' 'fresh code review stays detailed'
require_fixed "$CODE_REVIEW" '## Critical' 'fresh code severity stays detailed'
forbid_fixed "$CODE_REVIEW" 'Repeat the exact sentence as the first non-empty line of the final response.' \
  'fresh code review does not gain a one-sided final-output rule'
require_fixed "$PLAN_REVIEW" '# Plan Review' 'fresh plan review stays detailed'
require_fixed "$PLAN_REVIEW" '**Status:** Approved | Issues Found' 'fresh plan readiness stays detailed'
forbid_fixed "$PLAN_REVIEW" 'Repeat the exact sentence as the first non-empty line of the final response.' \
  'fresh plan review does not gain a one-sided final-output rule'
require_fixed "$CODE_TEMPLATE" '### Findings' 'delegated code reviewer stays detailed'
require_fixed "$PLAN_TEMPLATE" '## Plan Review' 'plan document reviewer stays detailed'
require_fixed "$PLAN_TEMPLATE" '**Status:** Approved | Issues Found' 'plan reviewer status stays detailed'
require_fixed "$SPEC_TEMPLATE" '## Spec Review' 'spec document reviewer stays detailed'
require_fixed "$SPEC_TEMPLATE" '**Status:** Approved | Issues Found' 'spec reviewer status stays detailed'
require_fixed "$QUALITY_TEMPLATE" 'Findings (Critical/Important/Minor)' 'quality reviewer stays detailed'

PRODUCERS=(
  "$CODE_REVIEW"
  "$PLAN_REVIEW"
  "$REQUESTING"
  "$CODE_TEMPLATE"
  "$PLAN_TEMPLATE"
  "$SPEC_TEMPLATE"
  "$QUALITY_TEMPLATE"
)
for producer in "${PRODUCERS[@]}"; do
  forbid_fixed "$producer" 'using-joshix/references/review-response-format.md' \
    "$(basename "$(dirname "$producer")") is not wired to receiver formatting"
done

echo 'STATUS: PASSED'
