---
name: requesting-code-review
description: Use when completing tasks, implementing major features, or reviewing substantial changes before proceeding
---

# Requesting Code Review

Request a focused code review to catch concrete issues before they cascade.
Provide the reviewer with relevant implementation context, requirements,
changed files, diff context, and prior reasoning. With no active workflow
policy, dispatch every reviewer in an isolated context with every required
artifact, requirement, and prior reasoning item embedded in the dispatch
prompt. Never use inherited or forked conversation history for that
policy-absent review context.

**Core principle:** Review concrete risks before proceeding.

## Active workflow policy

When repository guidance declares `joshix-workflow-policy:`, read
`../using-joshix/references/workflow-policy.md` and
`../using-joshix/references/autonomous-review.md` before dispatch. That central
protocol replaces the manual dispatch and unbounded feedback rules below. With
no policy, keep this skill's existing behavior unchanged.

Invoke the installed `joshix-review review` operation with only the opposite
provider, canonical repository root, and exact task folder. Every invocation
starts one fresh reviewer process. The reviewer reads prior reasoning from
SQLite and discovers the relevant artifact and Git scope through the bridge's
narrow read-only commands.

The bridge performs one provider attempt. On success it validates the small
review result, appends it as an ordinary SQLite message, and returns the review
plus its history ID. On cancellation or failure it appends nothing, starts no
retry or fallback, and returns one direct result for the coordinator to report.

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

With an active workflow policy, tier-defined review rigor is authoritative.
Use only the review gates required by the task-level tier; do not carry the
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

## How to Request

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

Under an active policy, follow the semantic continuation and stop conditions in
`autonomous-review.md`; do not add pass counters or transport state.

## Example

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
use the selected tier's gate count and placement instead.

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
