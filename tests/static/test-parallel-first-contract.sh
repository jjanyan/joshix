#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DISPATCH="$ROOT_DIR/skills/dispatching-parallel-agents/SKILL.md"
SDD="$ROOT_DIR/skills/subagent-driven-development/SKILL.md"
WRITING="$ROOT_DIR/skills/writing-plans/SKILL.md"
PLAN_REVIEWER="$ROOT_DIR/skills/writing-plans/plan-document-reviewer-prompt.md"
EXECUTING="$ROOT_DIR/skills/executing-plans/SKILL.md"
IMPLEMENTER="$ROOT_DIR/skills/subagent-driven-development/implementer-prompt.md"
SPEC_REVIEWER="$ROOT_DIR/skills/subagent-driven-development/spec-reviewer-prompt.md"
QUALITY_REVIEWER="$ROOT_DIR/skills/subagent-driven-development/code-quality-reviewer-prompt.md"
CODEX_MAP="$ROOT_DIR/skills/using-joshix/references/codex-tools.md"
COPILOT_MAP="$ROOT_DIR/skills/using-joshix/references/copilot-tools.md"
GEMINI_MAP="$ROOT_DIR/skills/using-joshix/references/gemini-tools.md"
OPENCODE_PLUGIN="$ROOT_DIR/.opencode/plugins/joshix.js"
CLAUDE_SDD_INTEGRATION="$ROOT_DIR/tests/claude-code/test-subagent-driven-development-integration.sh"

failures=0

if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL: static contract requires rg (ripgrep)"
  exit 1
fi

require_fixed() {
  local file="$1"
  local text="$2"
  local label="$3"
  if rg -Fq -- "$text" "$file"; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s\n' "$label"
    failures=$((failures + 1))
  fi
}

require_multiline_fixed() {
  local file="$1"
  local text="$2"
  local label="$3"
  if rg -U -Fq -- "$text" "$file"; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s\n' "$label"
    failures=$((failures + 1))
  fi
}

forbid_fixed() {
  local file="$1"
  local text="$2"
  local label="$3"
  local status
  if rg -Fq -- "$text" "$file"; then
    printf 'FAIL: %s\n' "$label"
    failures=$((failures + 1))
  else
    status=$?
    if [ "$status" -eq 1 ]; then
      printf 'PASS: %s\n' "$label"
    else
      printf 'FAIL: %s (rg exited %d)\n' "$label" "$status"
      failures=$((failures + 1))
    fi
  fi
}

require_absent_regex() {
  local pattern="$1"
  shift
  local label="$1"
  shift
  local status
  if rg -n "$pattern" "$@" >/dev/null; then
    printf 'FAIL: %s\n' "$label"
    failures=$((failures + 1))
  else
    status=$?
    if [ "$status" -eq 1 ]; then
      printf 'PASS: %s\n' "$label"
    else
      printf 'FAIL: %s (rg exited %d)\n' "$label" "$status"
      failures=$((failures + 1))
    fi
  fi
}

require_fixed "$DISPATCH" "Parallel-first after execution authorization" "dispatcher owns the automatic default"
require_fixed "$DISPATCH" "disjoint write ownership" "parallel safety requires disjoint writes"
require_fixed "$DISPATCH" "unsafe mutable resources" "parallel safety excludes unsafe shared state"
require_fixed "$DISPATCH" "Stay serial when the problem is not yet decomposed into independent domains" "exploration is serial only until independent domains are identified"
forbid_fixed "$DISPATCH" "Stay serial when work is exploratory" "blanket exploratory-work serialization is removed"
require_fixed "$DISPATCH" "at most two concurrent workers" "unknown capacity has a two-worker bootstrap"
require_fixed "$DISPATCH" "Completion-aware" "dispatcher defines completion-aware scheduling"
require_fixed "$DISPATCH" "Join-all" "dispatcher defines join-all waves"
require_multiline_fixed "$DISPATCH" \
  $'3. **Serial:** Run the same authorized work and quality gates one at a time when\n   concurrent workers are unavailable.' \
  "dispatcher defines serial fallback"
require_fixed "$DISPATCH" "current/default model and reasoning effort" "delegated work inherits model and effort"
require_fixed "$DISPATCH" "actual changed files and touched resources" "returned scope is checked"
require_fixed "$DISPATCH" "first safe serialization point" "deferred verification has an owner"
require_fixed "$DISPATCH" "The lane stays pre-review until it passes" "verification failure loops before review"
require_fixed "$DISPATCH" "parallel lanes" "start report identifies parallel lanes"
require_fixed "$DISPATCH" "serial phases and reasons" "start report identifies serial phases"
require_fixed "$DISPATCH" "expected critical path" "start report identifies the expected critical path"
require_fixed "$DISPATCH" "expected peak concurrency" "start report identifies expected concurrency"
require_fixed "$DISPATCH" "what actually overlapped" "completion report identifies observed overlap"
require_fixed "$DISPATCH" "actual critical path when identifiable" "completion report identifies the actual critical path"
require_fixed "$DISPATCH" "serial waits, retries, or re-serialization" "completion report identifies waits and retries"
require_fixed "$DISPATCH" "meaningful topology variance" "completion report identifies topology variance"
require_fixed "$DISPATCH" "three meaningful work items" "Mermaid threshold is explicit"
require_fixed "$DISPATCH" "Always emit the Mermaid fence at that threshold" "Mermaid source is emitted without capability detection"
require_fixed "$DISPATCH" "omit numbers" "unsupported timing is omitted"
require_fixed "$DISPATCH" 'An older plan without `Depends on:`' "legacy plans are classified conservatively"

require_fixed "$WRITING" "**Depends on:** None" "plan template requires dependency metadata"
require_fixed "$WRITING" "Task order is presentational" "task order has no dependency meaning"
require_fixed "$PLAN_REVIEWER" "Depends on" "plan review checks dependency metadata"
require_fixed "$EXECUTING" "description: Use when the user explicitly asks to execute, implement, apply, start, carry out, or get done a written implementation plan" "executing-plans discovery remains trigger-only"
forbid_fixed "$EXECUTING" "in a separate session with review checkpoints" "executing-plans discovery removes stale session wording"
require_fixed "$EXECUTING" "joshix:subagent-driven-development" "inline executor preserves independent-plan routing"

require_fixed "$SDD" "joshix:dispatching-parallel-agents" "subagent execution invokes the canonical policy"
require_fixed "$SDD" "For each lane: implementation and self-review" "lane gate starts with implementation and self-review"
require_fixed "$SDD" "verification → spec-compliance review" "verification precedes spec review"
require_fixed "$SDD" "spec-compliance review → code-quality review" "spec review precedes quality review"
require_fixed "$SDD" "Quality review Task N:" "review dispatch descriptions are stable"
require_fixed "$SDD" "Whole-change review: <plan or feature>" "whole-change review dispatch description is stable"
require_fixed "$SDD" "QUALITY OUTCOME: <APPROVED or CHANGES REQUIRED>" "whole-change review outcome is machine-observable"
require_fixed "$SDD" "Do not advance the same lane or its dependents" "within-lane review gate is preserved"
require_fixed "$SDD" "Unrelated lanes may continue" "unrelated lanes may progress"
forbid_fixed "$SDD" "Dispatch multiple implementation subagents in parallel (conflicts)" "old global parallel prohibition is removed"
forbid_fixed "$SDD" "Move to next task while either review has open issues" "old unscoped review prohibition is removed"
require_multiline_fixed "$CLAUDE_SDD_INTEGRATION" \
  $'else\n    echo "  [INFO] No task tracking tool observed; this harness may expose task tools only on demand"\nfi' \
  "missing Claude task tracking is diagnostic"

require_fixed "$IMPLEMENTER" "## Exclusive Scope" "implementer receives exclusive scope"
require_fixed "$IMPLEMENTER" "Deferred verification" "implementer reports deferred verification"
require_fixed "$SPEC_REVIEWER" "## Lane Scope" "spec reviewer receives lane scope"
require_fixed "$SPEC_REVIEWER" "aggregate in-flight working-tree diff" "spec reviewer avoids aggregate in-flight diffs"
require_fixed "$QUALITY_REVIEWER" "LANE_SCOPED_CHANGE_CONTEXT" "quality reviewer receives lane-only change context"

require_fixed "$CODEX_MAP" 'Dispatch/capacity: start independent workers with multiple `spawn_agent`' "Codex mapping describes dispatch and capacity"
require_fixed "$CODEX_MAP" 'Observation: `wait_agent` supports completion-aware coordination.' "Codex mapping describes observation"
require_fixed "$CODEX_MAP" '| Continue the same worker | `followup_task` |' "Codex mapping names same-worker continuation"
require_fixed "$CODEX_MAP" 'Continuation: use `followup_task` for an existing idle worker' "Codex mapping describes continuation"
require_fixed "$CODEX_MAP" 'Questions: workers return `NEEDS_CONTEXT`; the lead resolves user questions.' "Codex mapping describes question ownership"
require_fixed "$CODEX_MAP" 'Reasoning: delegated workers inherit the current/default model and reasoning' "Codex mapping describes reasoning inheritance"

require_fixed "$COPILOT_MAP" 'Dispatch/capacity: start independent workers with multiple `task` calls.' "Copilot mapping describes dispatch and capacity"
require_fixed "$COPILOT_MAP" 'Observation: use `read_agent` and `list_agents` to observe individual' "Copilot mapping describes observation"
require_fixed "$COPILOT_MAP" 'Continuation: when the host cannot continue the same worker, dispatch a fully' "Copilot mapping describes continuation"
require_fixed "$COPILOT_MAP" 'Questions: workers return `NEEDS_CONTEXT`; the lead owns any user question.' "Copilot mapping describes question ownership"
require_fixed "$COPILOT_MAP" 'Reasoning: use the current Copilot model and default reasoning behavior when' "Copilot mapping describes reasoning defaults"

require_fixed "$GEMINI_MAP" 'Dispatch/capacity: request independent `@generalist` or named-agent tasks' "Gemini mapping describes dispatch and capacity"
require_fixed "$GEMINI_MAP" 'Observation: treat a multi-agent prompt conservatively as a join-all wave' "Gemini mapping describes observation"
require_fixed "$GEMINI_MAP" 'Continuation: when same-worker continuation is unavailable, dispatch a fully' "Gemini mapping describes continuation"
require_fixed "$GEMINI_MAP" 'Questions: workers return `NEEDS_CONTEXT`; the lead owns user questions' "Gemini mapping describes question ownership"
require_fixed "$GEMINI_MAP" 'Reasoning: inherit model and reasoning controls when exposed; otherwise use' "Gemini mapping describes reasoning defaults"

require_fixed "$OPENCODE_PLUGIN" "Multiple independent subagents → parallel @mentions when supported; otherwise serial execution" "OpenCode mapping exposes parallel capability bootstrap"

require_absent_regex \
  'using-git-worktrees|finishing-a-development-branch' \
  "obsolete workflow skill identifiers stay absent" \
  "$ROOT_DIR/skills" "$ROOT_DIR/README.md" "$ROOT_DIR/.opencode"

for non_owner in "$WRITING" "$EXECUTING" "$SDD"; do
  require_absent_regex \
    'Completion-aware|Join-all|serial-equivalent time|expected peak concurrency' \
    "canonical dispatcher policy is not duplicated in $non_owner" \
    "$non_owner"
done

if [ "$failures" -ne 0 ]; then
  printf 'STATUS: FAILED (%d assertions)\n' "$failures"
  exit 1
fi

echo "STATUS: PASSED"
