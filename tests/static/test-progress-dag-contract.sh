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

require_fixed "$DAG" 'at least three tracked nodes' 'trigger is objective'
require_fixed "$DAG" 'When tracked node state changes' 'state changes cause updates'
require_fixed "$DAG" 'When a blocker changes dependencies or the viable path' 'topology changes cause updates'
require_fixed "$DAG" 'At completion' 'completion gets a final rendering'
require_fixed "$DAG" 'classDef done fill:#173b2c,stroke:#34d399,color:#dcfce7,stroke-width:2px' 'done uses the approved outlined green palette'
require_fixed "$DAG" 'classDef active fill:#183b5f,stroke:#60a5fa,color:#dbeafe,stroke-width:3px' 'in-flight uses the approved outlined blue palette'
require_fixed "$DAG" 'Do not assign a class to todo nodes' 'todo uses Mermaid defaults'
require_fixed "$DAG" 'Keep node IDs and labels stable between updates' 'updates remain visually stable'
require_fixed "$DAG" 'Show actual dependencies and available parallelism' 'topology is truthful'
require_fixed "$DAG" 'Condense large plans into meaningful phase nodes' 'large graphs stay legible'
require_fixed "$DAG" 'top-level coordinator' 'coordinator owns emission'
require_fixed "$DAG" 'Dispatched workers never emit, update, or persist it.' 'workers are exempt'
require_fixed "$DAG" 'Do not write the DAG as shared task state' 'DAG stays conversation-only'
require_fixed "$DAG" 'Ordinary questions and one- or two-node work do not get a DAG' 'small work does not trigger'
require_fixed "$DAG" 'Mermaid source fence is the user-facing artifact' 'source fence is the required artifact'
require_fixed "$DAG" 'A client may render it natively' 'native rendering is optional'
require_fixed "$DAG" 'agent does not create, inspect, attach, or persist a fallback image' 'agent does not create fallback images'
require_fixed "$DAG" 'Failure to display Mermaid visually is not a workflow failure' 'missing native rendering does not block work'
require_fixed "$DAG" 'condense it into meaningful phase nodes or change its layout direction' 'source graph stays legible'
forbid_fixed "$DAG" 'additive PNG' 'PNG requirement is removed'
forbid_fixed "$DAG" 'render-mermaid.mjs' 'renderer helper is removed from policy'
forbid_fixed "$DAG" 'mktemp -d' 'temporary image rendering is removed'
forbid_fixed "$DAG" 'PNG' 'PNG terminology is removed from policy'

for skill in "${SKILLS[@]}"; do
  require_fixed "$skill" 'using-joshix/references/progress-dag.md' \
    "$(basename "$(dirname "$skill")") links canonical DAG guidance"
done

if rg -n 'classDef (done|active)|fill:#173b2c|fill:#183b5f|three meaningful work items' "${SKILLS[@]}"; then
  echo 'FAIL: participating skills duplicate canonical threshold or styling rules'
  exit 1
fi

echo 'STATUS: PASSED'
