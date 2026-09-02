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
- If the user asks a substantive honest question about whether work should
  occur, answer it before making changes. A question that merely asks for
  meta-review (`What do you think?`, `Thoughts?`, or `Is this right?`) does not
  pause automatic review reception.
- If the user pastes or references an implementation plan without explicitly
  asking for execution, review the plan by default. Do not implement unless
  explicitly asked.
- If the user provides a supplied or referenced spec without explicitly asking
  to edit it or execute implementation, review the spec by default with
  `joshix:reviewing-specs` and remain read-only.
- First identify what the reviewer evaluated. Use artifact reception only for
  concrete code or diff, a named plan, or a named spec. Task history,
  `current.md`, product discussion, proposed architecture, and general chat are
  context, not review artifacts and receive a normal conversational response.
  The phrase `review` alone does not select artifact reception.
- Receiving another agent's concrete code, named plan, or named spec review
  enters automatic meta-review by role. Use the matching
  `joshix:receiving-*` skill and follow the
  single decision table in
  `skills/using-joshix/references/review-reception-contract.md` plus the single
  response grammar in
  `skills/using-joshix/references/review-response-format.md`. Those references
  own objective application, semantic explicit no-edit behavior, owner-gated
  product and architecture decisions, convergence, and reporting; do not restate
  them here.
- Pre-tool exception: semantic explicit no-edit mode must use the matching
  sentence below verbatim as the first emitted agent sentence; do not prepend a
  generic skill announcement. The response grammar governs its later placement.
  - Code: `I'm reviewing the review as feedback to evaluate, not as approval to edit files.`
  - Plan: `I'm reviewing the plan review as feedback to evaluate, not as approval to edit the plan.`
  - Spec: `I'm reviewing the spec review as feedback to evaluate, not as approval to edit the spec.`
  Use this exception only when the user semantically says review only, do not
  edit, do not apply, or keep the artifact unchanged. `What do you think?`,
  `Thoughts?`, and `Is this right?` remain automatic and must never trigger the
  no-edit opening.

## Skill Names

Use the `joshix:` namespace. The bootstrap skill is `joshix:using-joshix`.

Important workflow skills include:

- `joshix:brainstorming`
- `joshix:task-context`
- `joshix:writing-plans`
- `joshix:reviewing-plans`
- `joshix:reviewing-specs`
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
