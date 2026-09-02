---
name: task-context
description: Use when starting or continuing a top-level Codex or Claude conversation in a repository, including one-turn questions
---

<SUBAGENT-STOP>
A declared persistent reviewer peer may use `recent`, `since-id`, `since-time`,
`search`, `get`, and `check` against only the exact task folder supplied by its
coordinator. It never calls `init`, `append`, or `export`, never rewrites
`current.md`, and emits no attachment notice. Every other delegated worker
stops without reading or writing shared task context.
</SUBAGENT-STOP>

# Shared Task Context

Use this for every top-level Codex or Claude conversation in a Git-backed
repository. There is no task-size classifier. If Git cannot resolve a root,
skip automatic initialization with a concise explanation unless the user
supplied an explicit absolute task-folder path.

## Helper

The helper requires Node 22.13.0 or newer. Use the host-provided absolute path to this `SKILL.md` as authoritative. Resolve `scripts/task-context.mjs` from its parent directory and invoke it as:

`<absolute-skill-directory>/scripts/task-context.mjs`

Run initialization by itself and confirm that it succeeds before appending:

`<absolute-skill-directory>/scripts/task-context.mjs init .joshix/tasks/<folder>`

Always pass the repository-relative `.joshix/tasks/<folder>` path, not a bare
folder name. Do not batch `init` with later commands, because a failed first
command must not be hidden by a successful command at the end of the batch.
Use `--help` for the complete command syntax. Do not inspect the helper source
merely to discover its interface.

Never derive the helper from cwd, a plugin environment variable,
`CLAUDE_PLUGIN_ROOT`, `CODEX_HOME`, or an assumed cache layout. The helper
itself resolves relative task paths with `git rev-parse --show-toplevel`.

## Establish the task

Use: exact path → exact folder name → unique ticket match → established conversation → create.

- Resolve names under `<git-root>/.joshix/tasks/` and match tickets against
  folder names only. Never scan message history to choose a task.
- Ask when a ticket or name has multiple matches. Never switch an established
  task silently.
- Use `YYYY-MM-DD-TICKET` for a recognized ticket or
  `YYYY-MM-DD-descriptive-slug` otherwise. The agent chooses collision suffixes;
  `init` receives the final exact path.

On creation, append and show exactly once:

`Shared task created: .joshix/tasks/<folder>/`

When a user-supplied path, name, or ticket attaches a new chat, append and show
exactly once:

`Using shared task: .joshix/tasks/<folder>/`

Emit the applicable notice as the exact standalone plain-text line shown above,
without bullets, bold, code formatting, or other decoration. Notice state is
per top-level chat: a notice shown by another agent or earlier chat does not
satisfy this chat's requirement. Do not repeat notices on routine turns within
the same chat.

## First turn

1. Resolve the task before substantive work. If the host requires commentary
   before a tool call, retain that exact message in a short buffer.
2. Run `init`; then append the user message from a content file as `User`.
3. Append buffered commentary in order, then the applicable notice.
4. Copy accessible attachments into `files/` with a safe basename; choose the
   lowest numeric suffix on collision. If bytes are unavailable, record and
   report that honestly.
5. Read `current.md` first. Query history only for detail it lacks.

## Every turn

- Append each user message from a content file.
- Use exactly `User` for user messages and the host name `Codex` or `Claude`
  for agent messages. Never use a generic `Assistant` speaker.
- Prepare each visible response in a content file, append every outward-facing
  message before emitting it, then emit that same intended content. This
  includes commentary, progress DAGs, and final responses; it excludes tools
  and hidden reasoning.
- For coordinator-owned records that may be retried, pass a stable
  `--idempotency-key`. Reusing a key is valid only for the identical speaker
  and content; a collision is an error, never permission to append a variant.
- If append fails, keep helping when safe but warn that shared history was not
  updated.
- Rewrite `current.md` as a present-state snapshot under 500 words and never
  exceed 1,000 words. Preserve `Objective`, `Current state`, `Decisions`,
  `Open questions or blockers`, `Next actions`, and `Relevant files`; set
  `history_through` to the latest response ID.
- Replace `current.md` using a temporary file followed by an atomic rename.
- On handoff, use `recent`, `since-id`, `since-time`, `search`, and `get`
  selectively. Never load or export full history by default.

### Active workflow policy

When loaded repository guidance declares `joshix-workflow-policy:`, read
`../using-joshix/references/workflow-policy.md`. After initialization and before
planning or the first repository edit, append the task declaration required by
that contract. Policy absence leaves this skill's existing behavior unchanged.

Keep only this compact active state in `current.md`:

```markdown
## Workflow declaration
- Surfaces: `<name> — <tier> — <effect>`
- Complexity: `<trivial|routine|complex>`
- Effort: `<duration>`
- Outcome/scope: `<one sentence>`
- Active time: `40m; open; approximate`
- Review: `<gate>; round <n>; <path>; <provider> session <uuid>; history <id>`
- Deferred: `<count; history IDs>`
```

Full declarations, overrides, external-wait records, reviews, findings, and
deferred observations remain append-only history. The coordinator alone writes
this history and atomically replaces the snapshot. A declared persistent
reviewer peer may read the exact supplied task through the commands allowed by
the stop block; every delegated worker reports results to the coordinator.

Before a policy checkpoint, append the current User message before querying so
the preceding owner gap is excluded and the current coordinator interval is
open. Then run:

`<absolute-skill-directory>/scripts/task-context.mjs elapsed .joshix/tasks/example --now 2026-09-02T11:40:00.000Z`

Production calls omit `--now`. Do not query an idle conversation after a final
response because no coordinator work unit exists then. Record the returned
duration, state, and `approximate` marker only during an ordinary snapshot
rewrite; never emit a progress update solely for time bookkeeping.

The only machine-readable exception is an external wait, appended idempotently
with speaker `TaskMeta` and one exact JSON object:

```json
{"type":"joshix.external-wait","state":"paused","key":"<stable-key>"}
{"type":"joshix.external-wait","state":"resumed","key":"<stable-key>"}
```

Append these only around a genuine owner or external-system wait. Do not start
a policy checkpoint while the latest pause is still open. Missing metadata
deliberately overcounts active time. This protocol adds no timer, poller,
daemon, or routine timing event.

## Failures and boundaries

- Stop before conversation writes if privacy verification fails or task paths
  are tracked. Never mutate the Git index or `.git/info/exclude`.
- If `current.md` is missing, rebuild it from explicit queries. If
  `history_through` exceeds the maximum message ID, report it and run `check`
  before rewriting. Preserve an integrity-failed database unchanged.
- Do not clean up task folders. Do not query Linear. Do not depend on deploy
  state.
