---
name: requesting-code-review
description: Use when completing tasks, implementing major features, or reviewing substantial changes before proceeding
---

# Requesting Code Review

Request a focused code review to catch concrete issues before they cascade.
Provide the reviewer with relevant implementation context, requirements,
changed files, and diff context. By default, provide focused context instead of
the full session history. Inherit or fork session context only when the
platform or task genuinely requires it.

**Core principle:** Review concrete risks before proceeding.

## Model Selection

Use the current/default model for delegated review work. Do not downgrade models
to conserve cost. If the platform inherits the current model by default, let
that cascade to reviewer subagents. Avoid overriding model selection unless the
user, repo guidance, or platform-specific workflow explicitly calls for a
different model.

## When to Request Review

**Mandatory:**
- After each task in subagent-driven development
- After completing a major feature or risky change
- Before reporting substantial work complete when correctness,
  maintainability, security, data, or operational risk matters

**Optional but valuable:**
- When stuck (fresh perspective)
- Before refactoring (baseline check)
- After fixing complex bug

If the latest user message contains an honest question that needs an answer,
answer it before requesting review.

## How to Request

**1. Gather review inputs:**

- `{DESCRIPTION}` - Brief summary of what changed
- `{PLAN_OR_REQUIREMENTS}` - What it should do
- `{CHANGED_FILES}` - Files changed by this task or checkpoint
- `{DIFF_CONTEXT}` - Relevant working tree diff, changed-file diff, or code
  snippets to review
- `{VERIFICATION}` - Commands/tests run and results, if available

**2. Dispatch a code reviewer:**

Use the platform's subagent, review, or task tool with the template at
`code-reviewer.md`.

**3. Act on feedback:**
- Fix Critical issues immediately
- Fix Important issues before proceeding or reporting completion, unless there
  is a clear technical reason to push back
- Consider Minor issues, but do not let taste-only feedback churn the work
- Push back if reviewer is wrong (with reasoning)

## Example

```
[Just completed Task 2: Add verification function]

You: Let me request code review before proceeding.

[Dispatch code reviewer subagent]
  DESCRIPTION: Added verifyIndex() and repairIndex() with 4 issue types
  PLAN_OR_REQUIREMENTS: Task 2 from .joshix/plans/deployment-plan.md
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
- Skip review because "it's simple"
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

See template at: requesting-code-review/code-reviewer.md
