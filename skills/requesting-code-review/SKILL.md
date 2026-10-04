---
name: requesting-code-review
description: Use when completing tasks, implementing major features, or reviewing substantial changes before proceeding
---

# Requesting Code Review

Request a focused code review to catch concrete issues before they cascade.
Provide the reviewer with relevant implementation context, requirements,
changed files, diff context, and prior reasoning. Codex and Claude Code always
use the opposite-provider bridge below unless the owner explicitly overrides
provider selection. Workflow policy controls review gates, not provider routing.

**Core principle:** Review concrete risks before proceeding.

## Codex and Claude Code review transport

Read `../using-joshix/references/autonomous-review.md` before dispatch, with or
without a workflow policy. Also read
`../using-joshix/references/workflow-policy.md` when repository guidance declares
`joshix-workflow-policy:`. On Codex and Claude Code the bridge replaces the
native dispatch instructions below; policy absence never selects a native
same-provider reviewer.

Invoke the installed `joshix-review review` operation with only the opposite
provider, canonical repository root, and exact task folder. Every invocation
starts one fresh reviewer process. The reviewer reads prior reasoning from
SQLite and discovers the relevant artifact and Git scope through the bridge's
narrow read-only commands.

Run `joshix-review review` as the only command in its shell call. NEVER combine
it with file preparation, logging, heredocs, command chains, pipelines, or
another command. Prepare files in separate calls. In the configured Codex
installation, the saved narrow allow rule permits the standalone launcher to
run outside the sandbox automatically. The wrapper itself does not elevate.
Default tool permissions alone do not establish whether execution stayed
sandboxed.

The bridge performs one provider attempt. On success it validates the small
review result, appends it as an ordinary SQLite message, and returns the review
plus its history ID. On cancellation or failure it appends nothing, starts no
retry or fallback, and returns one direct result for the coordinator to report.

On an `authentication` result, inspect the original shell call. If the launcher
was bundled, retry once as a standalone command. If it was already standalone,
or that retry fails, stop and report the underlying error to the user: the
account may actually be logged out. This is the only coordinator retry
exception; the bridge never retries internally or changes credentials.

Independently verify every finding. Apply only concrete,
requirement-determined corrections within the owner's authorized outcome and
scope. Start a new explicit review with another fresh process only after the
artifact materially changes or new evidence appears. Stop for an owner
decision, repeated rebutted disagreement without new evidence, a materially
unchanged defect, or the absence of an objective correction.

## Model Selection

The bridge does not choose or pin reviewer models or reasoning effort. Each
isolated native CLI uses the provider/account defaults available without
loading unrelated user tool configuration. Do not add downgrade flags to
conserve cost. A task-specific model or effort override requires an explicit
user request.

## When to Request Review

Use the bootstrap's Work and review rules to distinguish a requested preview
or disposable experiment from a completed retained change. Do not start final
review merely because the user asks to extend a visual trial. First collect
focused evidence for the main outcome and affected interactions; reserve the
full completion checks for after review.

With an active workflow policy, run the core completed-implementation review
once unless an explicit owner or repository instruction names that boundary.
Tier-defined review rigor may add distinct whole-change, slice, or lane gates;
it does not suppress or duplicate the core review. Do not carry the
policy-absent mandatory per-task or per-lane gates into the active branch.

**Policy absent — mandatory:**

- After each task in subagent-driven development
- After completing a major feature or risky change
- Before reporting substantial work complete when correctness,
  maintainability, security, data, or operational risk matters

**Policy absent — optional but valuable:**
- When stuck (fresh perspective)
- Before refactoring (baseline check)
- After fixing complex bug

If the latest user message contains an honest question that needs an answer,
answer it before requesting review.

## Native dispatch — other hosts or explicit owner override

This section is not the default for Codex or Claude Code. Dispatch every native
reviewer in an isolated context with every required artifact, requirement, and
prior reasoning item embedded in the dispatch prompt. Never use inherited or
forked conversation history for that native review context.

**1. Gather review inputs:**

- `{DESCRIPTION}` - Brief summary of what changed
- `{PLAN_OR_REQUIREMENTS}` - What it should do
- `{PRIOR_REASONING}` - Prior rationale, classifications, or decisions needed
  for review
- `{CHANGED_FILES}` - Files changed by this task or checkpoint
- `{DIFF_CONTEXT}` - Relevant working tree diff, changed-file diff, or code
  snippets to review
- `{VERIFICATION}` - Commands/tests run and results, if available

**2. Dispatch a code reviewer:**

Use the platform's subagent, review, or task tool with the template at
`../code-review/code-reviewer.md`.

**3. Act on feedback:**
- Fix Critical issues immediately
- Fix Important issues before proceeding or reporting completion, unless there
  is a clear technical reason to push back
- Consider Minor issues, but do not let taste-only feedback churn the work
- Push back if reviewer is wrong (with reasoning)

For bridge reviews, follow the semantic continuation and stop conditions in
`autonomous-review.md`; do not add pass counters or transport state.

## Native dispatch example — no workflow policy

```
[Just completed Task 2: Add verification function]

You: Let me request code review before proceeding.

[Dispatch code reviewer subagent]
  DESCRIPTION: Added verifyIndex() and repairIndex() with 4 issue types
  PLAN_OR_REQUIREMENTS: Task 2 from .joshix/plans/deployment-plan.md
  PRIOR_REASONING: Task 1 review established the current indexing and repair assumptions
  CHANGED_FILES: src/index.ts, tests/index.test.ts
  DIFF_CONTEXT: Current working tree diff for the changed files
  VERIFICATION: npm test tests/index.test.ts - passing

[Subagent returns]:
  Findings:
    Important: Missing progress indicators
    Minor: Magic number (100) for reporting interval
  Assessment: Ready to proceed

You: [Fix progress indicators]
[Continue to Task 3]
```

## Integration with Workflows

The bullets below describe the policy-absent workflow. Under an active policy,
use the core completed-implementation review plus the selected tier's
additional gate count and placement instead.

**Subagent-Driven Development:**
- Review after EACH task
- Catch issues before they compound
- Fix before moving to next task

**Executing Plans:**
- Review after each task or at natural checkpoints
- Get feedback, apply, continue

**Ad-Hoc Development:**
- Review before reporting large or risky work complete
- Review when stuck

## Red Flags

**Never:**
- Under policy absence, skip review because "it's simple"
- Ignore Critical issues
- Proceed with unfixed Important issues
- Argue with valid technical feedback
- Ask for review before answering an honest user question
- Give the reviewer stale or irrelevant diff context
- Ask the reviewer to judge the whole repo when a changed-file scope is enough

**If reviewer wrong:**
- Push back with technical reasoning
- Show code/tests that prove it works
- Request clarification

See template at: skills/code-review/code-reviewer.md
