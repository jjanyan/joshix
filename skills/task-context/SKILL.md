---
name: task-context
description: Use when starting or continuing a top-level Codex or Claude conversation in a repository, including one-turn questions
---

<SUBAGENT-STOP>
If you were dispatched as a subagent or worker for a bounded task, stop. Do not
create, connect to, read, append to, summarize, or mention shared task context.
The top-level coordinator owns it.
</SUBAGENT-STOP>

# Shared Task Context

Use this for every top-level Codex or Claude conversation in a Git-backed
repository. There is no task-size classifier. If Git cannot resolve a root,
skip automatic initialization with a concise explanation unless the user
supplied an explicit absolute task-folder path.

## Helper

The helper requires Node 22.13.0 or newer. Use the host-provided absolute path to this `SKILL.md` as authoritative. Resolve `scripts/task-context.mjs` from its parent directory and invoke it as:

`node --disable-warning=ExperimentalWarning <absolute-skill-directory>/scripts/task-context.mjs`

Run initialization by itself and confirm that it succeeds before appending:

`node --disable-warning=ExperimentalWarning <absolute-skill-directory>/scripts/task-context.mjs init .agents/tasks/<folder>`

Always pass the repository-relative `.agents/tasks/<folder>` path, not a bare
folder name. Do not batch `init` with later commands, because a failed first
command must not be hidden by a successful command at the end of the batch.
Use `--help` for the complete command syntax. Do not inspect the helper source
merely to discover its interface.

Never derive the helper from cwd, a plugin environment variable,
`CLAUDE_PLUGIN_ROOT`, `CODEX_HOME`, or an assumed cache layout. The helper
itself resolves relative task paths with `git rev-parse --show-toplevel`.

Codex sandboxes may protect `.agents/` even when the rest of the repository is
writable. If an in-scope task-context operation fails with a sandbox denial,
retry only that narrow helper or file operation with elevated filesystem
permission. Do not broaden the command or request unrelated access. Claude
uses its normal repository write mechanism.

## Establish the task

Use: exact path → exact folder name → unique ticket match → established conversation → create.

- Resolve names under `<git-root>/.agents/tasks/` and match tickets against
  folder names only. Never scan message history to choose a task.
- Ask when a ticket or name has multiple matches. Never switch an established
  task silently.
- Use `YYYY-MM-DD-TICKET` for a recognized ticket or
  `YYYY-MM-DD-descriptive-slug` otherwise. The agent chooses collision suffixes;
  `init` receives the final exact path.

On creation, append and show exactly once:

`Shared task created: .agents/tasks/<folder>/`

When a user-supplied path, name, or ticket attaches a new chat, append and show
exactly once:

`Using shared task: .agents/tasks/<folder>/`

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
- If append fails, keep helping when safe but warn that shared history was not
  updated.
- Rewrite `current.md` as a present-state snapshot under 500 words and never
  exceed 1,000 words. Preserve `Objective`, `Current state`, `Decisions`,
  `Open questions or blockers`, `Next actions`, and `Relevant files`; set
  `history_through` to the latest response ID.
- Replace `current.md` using a temporary file followed by an atomic rename.
- On handoff, use `recent`, `since-id`, `since-time`, `search`, and `get`
  selectively. Never load or export full history by default.

## Failures and boundaries

- Stop before conversation writes if privacy verification fails or task paths
  are tracked. Never mutate the Git index or `.git/info/exclude`.
- If `current.md` is missing, rebuild it from explicit queries. If
  `history_through` exceeds the maximum message ID, report it and run `check`
  before rewriting. Preserve an integrity-failed database unchanged.
- Do not clean up task folders. Do not query Linear. Do not depend on deploy
  state.
