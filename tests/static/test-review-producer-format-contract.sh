#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
README="$ROOT/README.md"
CODE_REVIEW="$ROOT/skills/code-review/SKILL.md"
PLAN_REVIEW="$ROOT/skills/reviewing-plans/SKILL.md"
SPEC_REVIEW="$ROOT/skills/reviewing-specs/SKILL.md"
SPEC_RECEIVER="$ROOT/skills/receiving-spec-review/SKILL.md"
REQUESTING="$ROOT/skills/requesting-code-review/SKILL.md"
CODE_TEMPLATE="$ROOT/skills/code-review/code-reviewer.md"
PLAN_TEMPLATE="$ROOT/skills/reviewing-plans/plan-document-reviewer-prompt.md"
SPEC_TEMPLATE="$ROOT/skills/reviewing-specs/spec-document-reviewer-prompt.md"
QUALITY_TEMPLATE="$ROOT/skills/subagent-driven-development/code-quality-reviewer-prompt.md"
PRODUCER_CONTRACT="$ROOT/skills/using-joshix/references/review-producer-contract.md"
AUTONOMOUS_CONTRACT="$ROOT/skills/using-joshix/references/autonomous-review.md"
RESULT_SCHEMA="$ROOT/skills/requesting-code-review/review-result.schema.json"
RECORD_SCHEMA="$ROOT/skills/requesting-code-review/review-record.schema.json"
FAILURE_SCHEMA="$ROOT/skills/requesting-code-review/review-failure-record.schema.json"
DELEGATED_BOUNDARY='You are a delegated producer. Use only the artifacts and reasoning supplied in this dispatch; do not seek outside conversation state.'
DELEGATED_ISOLATION='Never initialize, read, write, or mention coordinator conversation state.'
PROVISIONAL_VERDICT='Every producer status, approval, or readiness verdict is provisional.'
OWNER_OUTCOME='The artifact owner emits the authoritative outcome after independent concurrence.'
EXPECTED_SPEC_OPENING="I'm using joshix:reviewing-specs to review this spec by default, not to edit it."

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

require_fixed "$README" 'joshix:reviewing-plans' \
  'README lists the plan review producer'
require_fixed "$README" 'joshix:reviewing-specs' \
  'README lists the spec review producer'
require_fixed "$README" 'Plan, spec, and code review producers remain read-only' \
  'README names the producer role boundary'

require_value_contains() {
  local value="$1" text="$2" label="$3"
  if [[ "$value" != *"$text"* ]]; then
    printf 'FAIL: %s\nMissing: %s\nActual: %s\n' "$label" "$text" "$value"
    exit 1
  fi
}

forbid_value_contains() {
  local value="$1" text="$2" label="$3"
  if [[ "$value" == *"$text"* ]]; then
    printf 'FAIL: %s\nUnexpected: %s\nActual: %s\n' "$label" "$text" "$value"
    exit 1
  fi
}

require_prompt_preamble() {
  local file="$1" label="$2"
  local actual expected
  actual="$(awk '
    /^  prompt: \|$/ {
      getline
      print
      getline
      print
      getline
      print
      getline
      print
      exit
    }
  ' "$file")"
  expected="    ${DELEGATED_BOUNDARY}"$'\n'"    ${DELEGATED_ISOLATION}"$'\n'"    ${PROVISIONAL_VERDICT}"$'\n'"    ${OWNER_OUTCOME}"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s\nExpected first three prompt lines:\n%s\nActual first three prompt lines:\n%s\n' \
      "$label" "$expected" "$actual"
    exit 1
  fi
}

prompt_payload() {
  awk '
    /^  prompt: \|$/ {
      in_prompt = 1
      next
    }
    in_prompt && /^```$/ {
      exit
    }
    in_prompt {
      print
    }
  ' "$1"
}

require_prompt_fixed() {
  local file="$1" text="$2" label="$3"
  local normalized
  normalized="$(prompt_payload "$file" | tr '\n\r\t' '   ' | tr -s ' ')"
  if [[ "$normalized" != *"$text"* ]]; then
    printf 'FAIL: %s\nMissing from prompt payload: %s\n' "$label" "$text"
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
require_fixed "$CODE_REVIEW" 'using-joshix/references/review-producer-contract.md' \
  'code review links the producer contract'
require_fixed "$PLAN_REVIEW" 'using-joshix/references/review-producer-contract.md' \
  'plan review links the producer contract'
require_fixed "$SPEC_REVIEW" 'review-producer-contract.md' \
  'spec producer links producer contract'
require_fixed "$SPEC_REVIEW" "$EXPECTED_SPEC_OPENING" \
  'spec producer has symmetric opening'
require_fixed "$SPEC_REVIEW" '**Status:** Approved | Issues Found' \
  'spec status is detailed'

PRODUCER_DESC="$(sed -n 's/^description: //p' "$SPEC_REVIEW" | head -1)"
RECEIVER_DESC="$(sed -n 's/^description: //p' "$SPEC_RECEIVER" | head -1)"

require_value_contains "$PRODUCER_DESC" 'asks to review' \
  'spec producer description routes direct review requests'
require_value_contains "$PRODUCER_DESC" 'supplies or references a spec' \
  'spec producer description routes supplied specs'
forbid_value_contains "$PRODUCER_DESC" 'pasted spec reviewer comments' \
  'spec producer description excludes received feedback'
require_value_contains "$RECEIVER_DESC" 'spec review feedback' \
  'spec receiver description routes review feedback'
require_value_contains "$RECEIVER_DESC" 'pasted spec reviewer comments' \
  'spec receiver description routes pasted reviewer comments'
forbid_value_contains "$RECEIVER_DESC" 'supplies or references a spec' \
  'spec receiver description excludes direct producer requests'
require_fixed "$PRODUCER_CONTRACT" 'top-level producer reads the artifact and prior reasoning from shared task context' \
  'top-level producers receive shared reasoning'
require_fixed "$PRODUCER_CONTRACT" 'delegated producer receives every required artifact, requirement, and prior reasoning item in its dispatch prompt' \
  'delegated producers rely on dispatch context'
require_fixed "$PRODUCER_CONTRACT" 'never reads, writes, or mentions top-level shared task context' \
  'delegated producers stay outside shared context'
require_fixed "$PRODUCER_CONTRACT" \
  'A bridge reviewer peer is a fresh process that reads the exact shared task folder supplied by the coordinator' \
  'fresh peer reads shared history'
require_fixed "$PRODUCER_CONTRACT" \
  'never initializes, appends, or replaces shared task state' \
  'persistent peer stays read-only'
require_fixed "$AUTONOMOUS_CONTRACT" \
  'The provider process may read repository files and the exact task but may not edit repository or task state.' \
  'automatic loop preserves the reviewer read-only boundary'
require_fixed "$PRODUCER_CONTRACT" 'Keep artifact-specific evidence, severity, recommendations, and existing status, approval, or readiness fields.' \
  'producer contract preserves artifact-specific verdict fields'
require_fixed "$PRODUCER_CONTRACT" 'Every producer status, approval, or readiness verdict is provisional.' \
  'every producer verdict is provisional'
require_fixed "$PRODUCER_CONTRACT" 'The artifact owner emits the authoritative outcome after independent concurrence.' \
  'artifact owner emits the authoritative outcome'
forbid_fixed "$PRODUCER_CONTRACT" 'status `Approved | Issues Found`' \
  'producer contract does not impose the plan/spec status grammar'
require_prompt_preamble "$CODE_TEMPLATE" \
  'code review payload starts with dispatch boundary and provisional owner semantics'
require_prompt_preamble "$PLAN_TEMPLATE" \
  'plan review payload starts with dispatch boundary and provisional owner semantics'
require_prompt_preamble "$SPEC_TEMPLATE" \
  'spec review payload starts with dispatch boundary and provisional owner semantics'
require_prompt_preamble "$QUALITY_TEMPLATE" \
  'quality review payload starts with dispatch boundary and provisional owner semantics'
require_fixed "$CODE_TEMPLATE" '### Findings' 'delegated code reviewer stays detailed'
require_fixed "$CODE_TEMPLATE" '**Ready to proceed?** [Yes | No | With fixes]' \
  'code reviewer keeps its readiness verdict'
require_fixed "$PLAN_TEMPLATE" '## Plan Review' 'plan document reviewer stays detailed'
require_fixed "$PLAN_TEMPLATE" '**Status:** Approved | Issues Found' 'plan reviewer status stays detailed'
require_fixed "$SPEC_TEMPLATE" '## Spec Review' 'spec document reviewer stays detailed'
require_fixed "$SPEC_TEMPLATE" '**Status:** Approved | Issues Found' 'spec reviewer status stays detailed'
require_fixed "$QUALITY_TEMPLATE" 'Findings (Critical/Important/Minor)' 'quality reviewer stays detailed'
require_fixed "$QUALITY_TEMPLATE" '**Ready to proceed?** [Yes | No | With fixes]' \
  'quality reviewer keeps the code readiness verdict'
forbid_fixed "$QUALITY_TEMPLATE" 'Use template at skills/code-review/code-reviewer.md' \
  'quality reviewer composes its delegated payload'
require_prompt_fixed "$QUALITY_TEMPLATE" \
  'Does the implementation match the plan / requirements, with all planned functionality present?' \
  'quality payload checks plan alignment'
require_prompt_fixed "$QUALITY_TEMPLATE" \
  'Are error handling, type safety where applicable, and edge cases handled correctly?' \
  'quality payload checks correctness details'
require_prompt_fixed "$QUALITY_TEMPLATE" \
  'Are security, data-loss or corruption, and operational risks addressed?' \
  'quality payload checks security, data, and operations'
require_prompt_fixed "$QUALITY_TEMPLATE" \
  'Are schema migration strategy, backward compatibility, and documentation complete where applicable?' \
  'quality payload checks production readiness'
require_prompt_fixed "$QUALITY_TEMPLATE" \
  'Categorize issues by actual severity. Not everything is Critical.' \
  'quality payload calibrates severity'
require_prompt_fixed "$QUALITY_TEMPLATE" \
  'Ground findings in code you actually inspected. Do not invent issues or rely on assumptions.' \
  'quality payload requires evidence'
require_prompt_fixed "$QUALITY_TEMPLATE" \
  'For each issue, include a file:line reference, what is wrong, why it matters, and how to fix it when the fix is not obvious.' \
  'quality payload requires actionable findings'
require_prompt_fixed "$QUALITY_TEMPLATE" \
  'Do not include a positive-assessment section.' \
  'quality payload forbids positive-assessment sections'

require_fixed "$REQUESTING" 'Dispatch every native reviewer in an isolated context with every required artifact, requirement, and prior reasoning item embedded in the dispatch prompt.' \
  'native review requests embed complete context in isolated dispatches'
require_fixed "$REQUESTING" 'policy absence never selects a native same-provider reviewer.' \
  'policy-absent Codex and Claude coordinators use the bridge'
require_fixed "$REQUESTING" 'PRIOR_REASONING: Task 1 review established the current indexing and repair assumptions' \
  'review request example embeds prior reasoning'
forbid_fixed "$REQUESTING" 'Inherit or fork session context' \
  'review requests do not permit full-history inheritance'

DELEGATED_TEMPLATES=(
  "$CODE_TEMPLATE"
  "$PLAN_TEMPLATE"
  "$SPEC_TEMPLATE"
  "$ROOT/skills/subagent-driven-development/spec-reviewer-prompt.md"
  "$QUALITY_TEMPLATE"
)
for template in "${DELEGATED_TEMPLATES[@]}"; do
  require_fixed "$template" 'PRIOR_REASONING' \
    "$(basename "$template") embeds prior reasoning in its dispatch payload"
  forbid_fixed "$template" 'shared task context' \
    "$(basename "$template") does not mention shared task context"
  forbid_fixed "$template" '.joshix/tasks' \
    "$(basename "$template") does not mention .joshix/tasks"
  forbid_fixed "$template" 'task-context' \
    "$(basename "$template") does not mention task-context"
done

PRODUCERS=(
  "$CODE_REVIEW"
  "$PLAN_REVIEW"
  "$SPEC_REVIEW"
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

require_fixed "$RESULT_SCHEMA" '"required": ["status", "findings"]' \
  'structured reviewer result has the exact root protocol fields'
for field in title severity evidence recommendation; do
  require_fixed "$RESULT_SCHEMA" "\"$field\"" \
    "structured findings keep $field"
done
for removed in criticality surface decisionLevel; do
  forbid_fixed "$RESULT_SCHEMA" "$removed" \
    "structured findings do not delegate $removed governance"
done
for producer in \
  "$CODE_TEMPLATE" "$PLAN_TEMPLATE" "$SPEC_TEMPLATE" "$QUALITY_TEMPLATE"
do
  require_fixed "$producer" \
    'Do not classify workflow criticality, declared surfaces, decision ownership, pass count, or transport state' \
    "$(basename "$producer") leaves governance classification to the coordinator"
done
test ! -e "$RECORD_SCHEMA" || { echo 'FAIL: review record envelope still exists'; exit 1; }
test ! -e "$FAILURE_SCHEMA" || { echo 'FAIL: failure record envelope still exists'; exit 1; }

echo 'STATUS: PASSED'
