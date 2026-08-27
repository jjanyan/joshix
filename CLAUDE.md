# joshix Claude Guidance

This repository is Josh's customized fork for local agent workflows. It
is not being shaped as an upstream PR.

## Working Rules

- Work in the current checkout and current branch by default.
- Do not create worktrees, switch branches, stage, commit, push, or open PRs
  unless the user explicitly asks for that git operation.
- Use `.joshix/` for agent working artifacts:
  - `.joshix/context/` is ignored scratch context.
  - `.joshix/tasks/` is ignored per-task shared context for top-level
    Codex/Claude conversations; subagents do not read or write it, and it is not
    durable documentation.
  - `.joshix/specs/` and `.joshix/plans/` are temporary working artifacts, not
    durable product docs.
- After implementation, durable decisions belong in repo docs, code comments,
  or other permanent project files.
- If the user asks an honest question, answer it before making changes.
- If the user pastes or references an implementation plan without explicitly
  asking for execution, review the plan by default. Do not implement unless
  explicitly asked.
- If the user pastes or references an agent code review, evaluate the review
  item by item before editing. Do not apply fixes unless explicitly asked.
- If the user pastes or references an agent plan review, evaluate the review
  item by item before editing the plan. Do not apply fixes unless explicitly
  asked.
- If the user pastes or references an agent spec review, evaluate the review
  item by item before editing the spec. Do not apply fixes unless explicitly
  asked; when application is requested, apply verified objective corrections
  but stop before new product, scope, or architecture decisions.
- For received review feedback without edit authorization, the first emitted
  agent sentence must be the corresponding sentence below, verbatim:
  - Code: `I'm reviewing the review as feedback to evaluate, not as approval to edit files.`
  - Plan: `I'm reviewing the plan review as feedback to evaluate, not as approval to edit the plan.`
  - Spec: `I'm reviewing the spec review as feedback to evaluate, not as approval to edit the spec.`
  The sentence itself replaces the generic skill announcement and must come
  first; any required shared-task notice still follows on its own line. Repeat
  the same sentence as the first non-empty line of the final response before
  the compact review sections.

## Skill Names

Use the `joshix:` namespace. The bootstrap skill is `joshix:using-joshix`.

Important workflow skills include:

- `joshix:brainstorming`
- `joshix:task-context`
- `joshix:writing-plans`
- `joshix:reviewing-plans`
- `joshix:subagent-driven-development`
- `joshix:executing-plans`
- `joshix:systematic-debugging`
- `joshix:test-driven-development`
- `joshix:code-review`
- `joshix:commit-message`
- `joshix:commit-staged`
- `joshix:requesting-code-review`
- `joshix:receiving-code-review`
- `joshix:receiving-plan-review`
- `joshix:receiving-spec-review`
- `joshix:verification-before-completion`

## Testing

- Codex behavior tests live in `tests/codex/`.
- Claude Code tests live in `tests/claude-code/`; prompt-mode Claude tests may
  cost money, so run them intentionally.
- Prefer focused tests first, then broader suites when the local changes justify
  the cost.
