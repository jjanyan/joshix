# joshix Agent Guidance

This repository is Josh's customized fork for local agent workflows. It
is not being shaped as an upstream PR.

## Working Rules

- Work in the current checkout and current branch by default.
- Do not create worktrees, switch branches, stage, commit, push, or open PRs
  unless the user explicitly asks for that git operation.
- Use `.agents/` for agent working artifacts:
  - `.agents/context/` is ignored scratch context.
  - `.agents/specs/` and `.agents/plans/` are temporary working artifacts, not
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

## Skill Names

Use the `joshix:` namespace. The bootstrap skill is `joshix:using-joshix`.

Important workflow skills include:

- `joshix:brainstorming`
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
- `joshix:verification-before-completion`

## Testing

- Codex behavior tests live in `tests/codex/`.
- Claude Code tests live in `tests/claude-code/`; prompt-mode Claude tests may
  cost money, so run them intentionally.
- Prefer focused tests first, then broader suites when the local changes justify
  the cost.
