#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DAG="$ROOT/skills/using-joshix/references/progress-dag.md"
SKILLS=(
  "$ROOT/skills/brainstorming/SKILL.md"
  "$ROOT/skills/writing-plans/SKILL.md"
  "$ROOT/skills/executing-plans/SKILL.md"
  "$ROOT/skills/subagent-driven-development/SKILL.md"
  "$ROOT/skills/dispatching-parallel-agents/SKILL.md"
  "$ROOT/skills/reviewing-plans/SKILL.md"
)

require_fixed() {
  local file="$1" text="$2" label="$3"
  local normalized
  normalized="$(tr '\n\r\t' '   ' < "$file" | tr -s ' ')"
  if [[ "$normalized" != *"$text"* ]]; then
    printf 'FAIL: %s\nMissing: %s\n' "$label" "$text"
    exit 1
  fi
}

forbid_fixed() {
  local file="$1" text="$2" label="$3"
  local normalized
  normalized="$(tr '\n\r\t' '   ' < "$file" | tr -s ' ')"
  if [[ "$normalized" == *"$text"* ]]; then
    printf 'FAIL: %s\nUnexpected: %s\n' "$label" "$text"
    exit 1
  fi
}

require_fixed "$DAG" 'before implementation or worker dispatch begins' 'DAG precedes execution'
require_fixed "$DAG" 'A simple task may have one node' 'one-node plans are supported'
require_fixed "$DAG" 'Ordinary questions do not require a plan or a DAG' 'discussion stays discussion'
require_fixed "$DAG" 'stable ID, objective' 'nodes carry stable identity and intent'
require_fixed "$DAG" 'completion criteria, owner/role' 'nodes carry completion and ownership'
require_fixed "$DAG" 'verification and review gates as explicit dependencies' 'gates constrain execution'
require_fixed "$DAG" 'Record which nodes may overlap' 'parallelism is planned'
require_fixed "$DAG" 'constraints, not automatically semantic dependency edges' 'resource conflicts remain constraints'
require_fixed "$DAG" 'When advance plan review is selected or required' 'review remains proportional'
require_fixed "$DAG" 'delta from the approved revision' 'adjustments identify their baseline'
require_fixed "$DAG" 'completed evidence and work already underway' 'adjustments account for active and completed work'
require_fixed "$DAG" 'before executing the affected changes' 'approval precedes affected execution'
require_fixed "$DAG" 'checkout writers must pause during bridge review' 'review isolation remains effective'
require_fixed "$DAG" 'Ordinary scheduling within approved constraints needs no reapproval' 'routine scheduling avoids review churn'
require_fixed "$DAG" 'reviewer approval cannot grant it' 'owner gates remain separate'
require_fixed "$DAG" 'When tracked node state changes' 'state transitions cause updates'
require_fixed "$DAG" 'At completion' 'completion receives a snapshot'
require_fixed "$DAG" 'top-level coordinator' 'coordinator owns emission'
require_fixed "$DAG" 'Dispatched workers never emit, update, or persist it' 'workers are exempt'
require_fixed "$DAG" 'same plan revision, dependencies, node statuses' 'renderers share authoritative state'
require_fixed "$DAG" 'Label displays as snapshots' 'snapshots do not imply live updates'
require_fixed "$DAG" 'Load the advertised native skill before choosing Mermaid' 'exposed capability must be inspected'
require_fixed "$DAG" 'no dedicated tool named visualize' 'file-based native output remains discoverable'
require_fixed "$DAG" 'Unknown means still indeterminate after inspection' 'unchecked capability cannot justify fallback'
require_fixed "$DAG" 'State the concrete fallback reason' 'fallback is explained'
require_fixed "$DAG" 'static-diagram preference' 'generic Mermaid preference does not bypass interaction'
require_fixed "$DAG" 'serial or one-node' 'simple plans retain interactive inspection'
forbid_fixed "$DAG" 'absent, unknown, or rendering fails, use Mermaid' 'uninspected unknown shortcut removed'
require_fixed "$DAG" 'overrides visualization-skill defaults' 'DAG exception overrides generic presentation defaults'
require_fixed "$DAG" 'native snapshots in commentary when the client supports it' 'repeated native progress is supported'
require_fixed "$DAG" 'must not change task status, alter dependencies, dispatch workers or trigger execution' 'interaction is read-only'
require_fixed "$DAG" 'adjacent node details' 'fallback preserves inspection information'
require_fixed "$DAG" '`Owner / scope` and `Done when`' 'compact details retain ownership and completion criteria'
require_fixed "$DAG" 'do not repeat them as a default detail row' 'dependencies stay in the graph'
require_fixed "$DAG" 'highlights incoming edges and direct predecessor nodes' 'selection exposes prerequisite relationships'
require_fixed "$DAG" 'prerequisites in accessible graph/node descriptions' 'prerequisites remain accessible'
require_fixed "$DAG" '`active`: `Progress`' 'active details show observed progress'
require_fixed "$DAG" '`blocked`: `Blocked by`' 'blocked details explain the obstacle'
require_fixed "$DAG" '`done`: `Result`' 'completed details show the outcome'
require_fixed "$DAG" 'Never invent evidence or links' 'completion evidence is concrete'
require_fixed "$DAG" 'Do not add a routine `Parallel work` row' 'routine concurrency prose stays out of cards'
require_fixed "$DAG" 'classDef done fill:#173b2c,stroke:#34d399,color:#dcfce7,stroke-width:2px' 'Mermaid done styling is preserved'
require_fixed "$DAG" 'classDef active fill:#183b5f,stroke:#60a5fa,color:#dbeafe,stroke-width:3px' 'Mermaid active styling is preserved'
require_fixed "$DAG" 'classDef todo fill:#343434,stroke:#9ca3af,color:#f3f4f6,stroke-width:1px' 'todo uses neutral styling'
require_fixed "$DAG" 'classDef blocked fill:#4a3216,stroke:#fbbf24,color:#fef3c7,stroke-width:2px' 'blocked uses amber styling'
require_fixed "$DAG" 'it must not replace or obscure status colors' 'selection preserves semantic color'
require_fixed "$DAG" 'default the detail view to an active node' 'default focus follows active work'
require_fixed "$DAG" 'choose the first in stable plan order' 'multiple active nodes have a stable default'
require_fixed "$DAG" 'most recently completed node' 'completion provides fallback focus'
require_fixed "$DAG" 'never numeric ID or layout order' 'completion recency comes from evidence'
require_fixed "$DAG" 'scope saved selection to that snapshot' 'stale saved focus cannot mask progress'
require_fixed "$DAG" 'Failure to display Mermaid visually is not a workflow failure' 'display failure does not block work'
require_fixed "$DAG" 'not a second task-state store' 'display is not authoritative state'
require_fixed "$DAG" 'task-owned rendering file' 'native rendering files are permitted'
forbid_fixed "$DAG" 'at least three tracked nodes' 'old display threshold is removed'
forbid_fixed "$DAG" 'source fence is the user-facing artifact' 'mandatory source-only output is removed'
forbid_fixed "$DAG" 'render-mermaid.mjs' 'no dedicated image renderer is required'

for skill in "${SKILLS[@]}"; do
  require_fixed "$skill" 'using-joshix/references/progress-dag.md' \
    "$(basename "$(dirname "$skill")") links canonical DAG guidance"
done

if rg -n 'classDef (done|active|todo|blocked)|fill:#173b2c|fill:#183b5f|three meaningful work items|at least three tracked nodes|three-node trigger' "${SKILLS[@]}"; then
  echo 'FAIL: participating skills duplicate canonical threshold or styling rules'
  exit 1
fi

require_fixed "$ROOT/skills/using-joshix/SKILL.md" 'references/progress-dag.md' 'bootstrap discovers the DAG contract'
require_fixed "$ROOT/skills/using-joshix/references/autonomous-review.md" 'under `progress-dag.md`' 'bridge review consumes the plan contract'
require_fixed "$ROOT/skills/reviewing-plans/plan-document-reviewer-prompt.md" 'references/progress-dag.md' 'native reviewer consumes the same contract'
for file in "$ROOT/skills/using-joshix/SKILL.md" "$ROOT/skills/brainstorming/SKILL.md" "$ROOT/README.md"; do
  forbid_fixed "$file" 'plan only when useful' 'small implementation still gets an inline plan'
  forbid_fixed "$file" 'plan when useful' 'optional-plan wording does not conflict with mandatory DAGs'
  forbid_fixed "$file" 'when a plan helps' 'repair routing keeps the small-plan contract'
done

echo 'STATUS: PASSED'
