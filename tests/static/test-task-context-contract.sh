#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BOOTSTRAP="$ROOT/skills/using-joshix/SKILL.md"
TASK_CONTEXT="$ROOT/skills/task-context/SKILL.md"
VERIFICATION="$ROOT/skills/verification-before-completion/SKILL.md"
EXECUTING_PLANS="$ROOT/skills/executing-plans/SKILL.md"
SUBAGENT_DEVELOPMENT="$ROOT/skills/subagent-driven-development/SKILL.md"
STATIC_RUNNER="$ROOT/tests/static/run-tests.sh"
TESTING_DOC="$ROOT/docs/testing.md"
HANDOFF_TEST="$ROOT/tests/claude-code/test-task-context-handoff-integration.sh"

require_fixed() {
  local file="$1" text="$2" label="$3"
  local normalized
  normalized="$(tr '\n\r\t' '   ' < "$file" | tr -s ' ')"
  if [[ "$normalized" != *"$text"* ]]; then
    printf 'FAIL: %s\nMissing: %s\n' "$label" "$text"
    exit 1
  fi
}

reject_fixed() {
  local file="$1" text="$2" label="$3"
  local normalized
  normalized="$(tr '\n\r\t' '   ' < "$file" | tr -s ' ')"
  if [[ "$normalized" == *"$text"* ]]; then
    printf 'FAIL: %s\nUnexpected: %s\n' "$label" "$text"
    exit 1
  fi
}

require_fixed "$BOOTSTRAP" '`joshix:task-context`' 'bootstrap invokes task context'
require_fixed "$BOOTSTRAP" 'every top-level Codex or Claude conversation' 'bootstrap is always-on for supported top-level agents'
require_fixed "$TASK_CONTEXT" '<SUBAGENT-STOP>' 'subagents are exempt'
require_fixed "$BOOTSTRAP" 'If the prompt declares a persistent reviewer peer' 'bootstrap routes the persistent reviewer role'
require_fixed "$BOOTSTRAP" 'follow the read-only reviewer branch in `joshix:task-context`' 'bootstrap preserves reviewer read-only routing'
require_fixed "$TASK_CONTEXT" 'A declared persistent reviewer peer may use `recent`, `since-id`, `since-time`, `search`, `get`, and `check`' 'persistent reviewer commands are narrowly enumerated'
require_fixed "$TASK_CONTEXT" 'against only the exact task folder supplied by its coordinator' 'reviewer access is task scoped'
require_fixed "$TASK_CONTEXT" 'never calls `init`, `append`, or `export`' 'reviewer cannot mutate or bulk export task state'
require_fixed "$TASK_CONTEXT" 'Every other delegated worker stops without reading or writing shared task context.' 'ordinary delegated workers remain isolated'
require_fixed "$ROOT/skills/task-context/scripts/task-context.mjs" 'databaseFor(folder, { readOnly: true })' 'task-context read commands open SQLite read-only'
require_fixed "$TASK_CONTEXT" 'There is no task-size classifier.' 'one-turn work still gets context'
require_fixed "$TASK_CONTEXT" 'explicit absolute task-folder path' 'non-Git opt-in is explicit'
require_fixed "$TASK_CONTEXT" 'git rev-parse --show-toplevel' 'Git root is canonical'
require_fixed "$TASK_CONTEXT" 'host-provided absolute path to this `SKILL.md`' 'helper path comes from selected skill'
require_fixed "$TASK_CONTEXT" '<absolute-skill-directory>/scripts/task-context.mjs' 'supported invocation uses the executable helper path'
reject_fixed "$TASK_CONTEXT" 'node --disable-warning=ExperimentalWarning' 'task-context callers do not own Node warning flags'
require_fixed "$TASK_CONTEXT" 'init .joshix/tasks/<folder>' 'initialization uses the complete repository-relative path'
require_fixed "$TASK_CONTEXT" 'Do not batch `init` with later commands' 'initialization failure cannot be hidden by batching'
require_fixed "$TASK_CONTEXT" 'Use `--help` for the complete command syntax.' 'agents use the bounded interface instead of reading source'
reject_fixed "$TASK_CONTEXT" 'elevated filesystem permission' 'task context never enters a permission-escalation loop'
reject_fixed "$TASK_CONTEXT" 'Codex sandboxes may protect `.agents/`' 'task context does not treat the shared workspace as protected'
reject_fixed "$VERIFICATION" '.agents/' 'verification guidance uses the writable joshix artifact root'
reject_fixed "$EXECUTING_PLANS" '.agents/' 'inline execution guidance uses the writable joshix artifact root'
reject_fixed "$SUBAGENT_DEVELOPMENT" '.agents/' 'subagent execution guidance uses the writable joshix artifact root'
require_fixed "$TASK_CONTEXT" 'Node 22.13.0 or newer' 'minimum runtime is explicit'
require_fixed "$TASK_CONTEXT" 'Shared task created:' 'creation notice is exact'
require_fixed "$TASK_CONTEXT" 'Using shared task:' 'usage notice is exact'
require_fixed "$TASK_CONTEXT" 'exact standalone plain-text line' 'notices are not decorated'
require_fixed "$TASK_CONTEXT" 'Notice state is per top-level chat' 'every new chat owns its notice'
require_fixed "$TASK_CONTEXT" 'a notice shown by another agent or earlier chat does not satisfy this chat' 'cross-agent notices are not reused'
require_fixed "$TASK_CONTEXT" 'exact path → exact folder name → unique ticket match → established conversation → create' 'routing order is explicit'
require_fixed "$TASK_CONTEXT" 'Never scan message history to choose a task.' 'routing does not pollute context'
require_fixed "$TASK_CONTEXT" 'Ask when a ticket or name has multiple matches.' 'ambiguous routing asks instead of guessing'
require_fixed "$TASK_CONTEXT" 'append every outward-facing message before emitting it' 'visible responses are recording targets'
require_fixed "$TASK_CONTEXT" '`--idempotency-key`' 'retryable coordinator records use stable append keys'
require_fixed "$TASK_CONTEXT" 'elapsed .joshix/tasks/example --now 2026-09-02T11:40:00.000Z' 'elapsed query has one exact example'
require_fixed "$TASK_CONTEXT" 'append the current User message before querying' 'elapsed query follows the user-message append'
require_fixed "$TASK_CONTEXT" 'Do not query an idle conversation after a final response' 'elapsed query does not count idle time'
require_fixed "$TASK_CONTEXT" '{"type":"joshix.external-wait","state":"paused","key":"<stable-key>"}' 'external waits use exact metadata'
require_fixed "$TASK_CONTEXT" '- Active time: `40m; open; approximate`' 'snapshot keeps compact approximate active time'
require_fixed "$TASK_CONTEXT" 'no timer, poller, daemon, or routine timing event' 'task context adds no ongoing timing machinery'
reject_fixed "$TASK_CONTEXT" 'timer transitions' 'old transition bookkeeping is removed'
require_fixed "$ROOT/skills/task-context/scripts/task-context.mjs" 'messages_idempotency_key_idx' 'task history schema enforces keyed uniqueness'
require_fixed "$ROOT/tests/task-context/task-context.test.mjs" 'version 1 database to version 2 without data loss' 'task history migration is covered'
require_fixed "$TASK_CONTEXT" 'the host name `Codex` or `Claude`' 'agent history preserves its source'
require_fixed "$TASK_CONTEXT" 'Never use a generic `Assistant` speaker.' 'generic speaker labels are rejected'
require_fixed "$TASK_CONTEXT" 'retain that exact message in a short buffer' 'pre-initialization commentary is buffered'
require_fixed "$TASK_CONTEXT" 'it excludes tools and hidden reasoning' 'internal mechanics are not recorded'
require_fixed "$TASK_CONTEXT" 'Do not repeat notices on routine turns within the same chat.' 'established conversations stay quiet'
require_fixed "$TASK_CONTEXT" 'current.md' 'summary is first-line context'
require_fixed "$TASK_CONTEXT" 'under 500 words and never exceed 1,000 words' 'summary has a hard bound'
require_fixed "$TASK_CONTEXT" 'temporary file followed by an atomic rename' 'summary replacement is atomic'
require_fixed "$TASK_CONTEXT" 'files/' 'attachments use the shared folder'
require_fixed "$TASK_CONTEXT" 'safe basename; choose the lowest numeric suffix on collision' 'file collision behavior is explicit'
require_fixed "$TASK_CONTEXT" 'If bytes are unavailable, record and report that honestly.' 'inaccessible attachments are disclosed'
require_fixed "$TASK_CONTEXT" 'Do not clean up task folders' 'cleanup stays out of scope'
require_fixed "$TASK_CONTEXT" 'Do not query Linear' 'external status stays out of scope'
require_fixed "$TASK_CONTEXT" 'Do not depend on deploy state' 'deploy state stays out of scope'
require_fixed "$TASK_CONTEXT" 'Never derive the helper from cwd, a plugin environment variable, `CLAUDE_PLUGIN_ROOT`, `CODEX_HOME`, or an assumed cache layout.' 'host layout is explicitly rejected'
require_fixed "$TASK_CONTEXT" 'Never mutate the Git index or `.git/info/exclude`.' 'Git metadata mutation is explicitly rejected'
require_fixed "$ROOT/.gitignore" '.joshix/' 'root ignore protects joshix artifacts'
require_fixed "$ROOT/.gitignore" '.agents/context/' 'legacy root ignore protects unmigrated scratch context'
require_fixed "$ROOT/.gitignore" '.agents/tasks/' 'legacy root ignore protects unmigrated task context'
require_fixed "$ROOT/README.md" 'ignored per-task Codex/Claude handoff state' 'README describes task context'
require_fixed "$ROOT/AGENTS.md" 'ignored per-task shared context for top-level Codex/Claude conversations' 'Codex guidance describes task context'
require_fixed "$ROOT/CLAUDE.md" 'ignored per-task shared context for top-level Codex/Claude conversations' 'Claude guidance describes task context'
require_fixed "$STATIC_RUNNER" 'tests/task-context/task-context.test.mjs' 'static runner includes deterministic helper tests'
require_fixed "$STATIC_RUNNER" 'tests/reviewer-runner/reviewer-runner.test.mjs' 'static runner includes deterministic reviewer transport tests'
require_fixed "$TESTING_DOC" 'tests/task-context/task-context.test.mjs' 'testing docs describe deterministic helper tests'
require_fixed "$STATIC_RUNNER" 'node --disable-warning=ExperimentalWarning --test' 'the SQLite-importing test runner keeps its warning flag'
require_fixed "$TESTING_DOC" 'node --disable-warning=ExperimentalWarning --test' 'testing docs keep the test-runner warning flag'
require_fixed "$HANDOFF_TEST" 'source "$ROOT/tests/codex/test-helpers.sh" source "$SCRIPT_DIR/test-helpers.sh"' 'handoff test preserves suite-native helper definitions'
require_fixed "$HANDOFF_TEST" 'select(.type == "text")' 'Claude usage notice is read from the session transcript'

echo 'STATUS: PASSED'
