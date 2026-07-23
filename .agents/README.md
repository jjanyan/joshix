# Agent Workspace

This directory is for agent coordination metadata and working artifacts.

## Local Context

Temporary task context belongs in `.agents/context/`. That directory is ignored
by git.

Rules:

- Before creating a context file, scan existing files in `.agents/context/`.
- Use `.agents/context/<descriptive-name>.md`.
- Start each file with an ISO timestamp.
- Treat context files as scratchpads, not authoritative documentation.
- Delete context files older than 7 days during explicit cleanup, not as
  incidental churn in unrelated changes.

## Shared Task Context

Per-task Codex/Claude handoff state belongs in `.agents/tasks/<task>/`:

- `current.md` is the compact current snapshot.
- `history.sqlite` is append-only visible conversation history accessed through
  `joshix:task-context`.
- `files/` holds accessible shared attachments.
- `.agents/tasks/.gitignore` self-ignores the entire task area before
  conversation data is created.

Task context is local coordination state. Do not stage it, treat it as durable
documentation, clean it up incidentally, or couple it to ticket or deploy
status.

## Specs And Plans

`.agents/specs/` and `.agents/plans/` hold semi-temporary working artifacts.

- Specs are reviewed design artifacts used while planning or implementing work.
- Plans are executable task artifacts used while implementing work.
- Once work is implemented, durable decisions belong in repo documentation,
  product docs, code comments, or other permanent project files.
- Do not treat specs or plans as never-ending documentation. They should be
  removed or archived once their durable decisions have been captured elsewhere.

## Conventions

- Put formal design drafts in `specs/`.
- Put task-by-task implementation instructions in `plans/`.
- Put lightweight notes and scratch handoffs in `context/`.
- Put top-level Codex/Claude per-task shared state in `tasks/`; subagents never
  read or write it.
- Prefer repo-relative links when referencing files from agent artifacts.
- Do not stage, commit, push, or open pull requests unless the user explicitly asks.
