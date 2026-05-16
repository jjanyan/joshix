---
name: reviewing-plans
description: Use when the user asks to review, audit, sanity-check, validate, or critique an implementation plan, or when the user provides or references a plan without an explicit execution instruction.
---

# Reviewing Plans

Review implementation plans for execution readiness. A plan document is not
approval to execute.

<EXTREMELY-IMPORTANT>
When this skill is used, the first non-empty sentence MUST be:

```text
I'm using joshix:reviewing-plans to review this plan by default, not to execute it.
```

Then review the plan. Do not replace this with a generic heading.
</EXTREMELY-IMPORTANT>

## Default Mode

If the user provides, pastes, links, or references an implementation plan
without an explicit execution instruction, treat it as a request to review the
plan. Do not ask whether to review or execute.

Execution is opt-in. Use `joshix:executing-plans` or
`joshix:subagent-driven-development` only when the user explicitly says to
execute, implement, start, apply, carry out, get this done, or equivalent.

Do not edit files, implement tasks, update the plan, stage, commit, branch,
push, or open a PR unless the user explicitly asks for that action.

## What To Review

Read the full plan before reacting. If a spec, issue, ticket, or pasted
requirements are available, review the plan against them. Inspect repo context
only as needed to verify concrete claims such as file paths, commands, existing
APIs, test conventions, or ownership boundaries.

Check for:

- Missing requirements or scope creep relative to the spec/request
- TODOs, placeholders, vague steps, or undefined acceptance criteria
- Task ordering problems, hidden dependencies, or contradictory steps
- Files, commands, functions, imports, services, or artifacts that do not exist
  and are not clearly created by earlier steps
- TDD violations for core behavior changes, bug fixes, and testable logic
- Missing targeted tests, broader verification, or explicit failure checks
- Missing durable documentation or cleanup when the change affects product,
  architecture, operations, or developer workflow
- Whether the plan correctly chooses `joshix:subagent-driven-development` for
  independent tasks or `joshix:executing-plans` for tightly coupled work

## Calibration

Flag issues that would make an implementer build the wrong thing, get stuck,
violate workflow rules, skip necessary verification, or leave important
decisions undocumented.

Do not block on wording preferences, task naming style, minor decomposition
differences, or "nice to have" additions unless they create real implementation
risk.

## Report Format

Findings first, ordered by severity. Omit empty sections.

```markdown
I'm using joshix:reviewing-plans to review this plan by default, not to execute it.

# Plan Review

**Status:** Approved | Issues Found

## Critical
- [Task/Step]: Problem.
  Evidence: Concrete plan/spec/repo evidence.
  Recommendation: Specific fix.

## Important
- [Task/Step]: Problem.
  Evidence: Concrete plan/spec/repo evidence.
  Recommendation: Specific fix.

## Minor
- [Task/Step]: Problem.
  Evidence: Concrete plan/spec/repo evidence.
  Recommendation: Specific fix.

## Advisory
- Non-blocking improvement.

## Summary
Brief readiness assessment and what must change before execution.
```

## Relationship To Other Plan Skills

- `joshix:reviewing-plans`: reviews a plan document itself.
- `joshix:receiving-plan-review`: evaluates another agent's review feedback
  about a plan.
- `joshix:executing-plans`: executes a plan only after explicit execution
  instruction.
