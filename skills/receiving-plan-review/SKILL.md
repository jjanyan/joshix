---
name: receiving-plan-review
description: Use when receiving pasted Plan Review feedback, plan reviewer comments, critiques of an implementation plan, or questions like "what do you think of this plan review?"
---

# Plan Review Reception

Plan review feedback is input to evaluate, not an order to rewrite the plan.

## Default Mode

If the user provides a pasted plan review, reviewer comments, or review-like
critique of a plan and does not explicitly ask you to edit the plan, begin with
this exact mode sentence before repo inspection, findings, summaries, or
recommendations:

```text
I'm reviewing the plan review as feedback to evaluate, not as approval to edit the plan.
```

If another workflow also requires a skill announcement, include the mode
sentence in the same first response before any analysis. A generic statement
like "I'll evaluate the feedback" is not enough.

Then evaluate the review item by item. Do not edit files, stage, commit, branch,
or start implementation unless the user explicitly asks for that action.

## How To Evaluate

For each review item:

1. Read the full review before reacting.
2. Check the claim against the plan, spec, repo context, and existing workflow
   rules.
3. Classify it as `Valid`, `Invalid`, `Needs investigation`, `Needs
   clarification`, `Already handled`, or `Optional/taste`.
4. Cite concrete evidence when possible: task names, step text, file paths,
   spec requirements, or the missing evidence.
5. Recommend whether to fix, reject, defer, clarify, or investigate.

## Calibration

Treat these as real plan issues:

- Missing spec requirements
- Placeholder or vague steps that would block an implementer
- Undefined functions, files, commands, or dependencies referenced by later
  steps
- Contradictory task order, test expectations, or file ownership
- Scope creep that would build something not requested
- Missing durable-docs or verification work when the change requires it

Treat these as non-blocking unless they create real implementation risk:

- Wording preferences
- Alternate task naming styles
- Suggestions to add "more complete" behavior not required by the spec
- Requests to split or combine tasks when the current decomposition is workable

## If Asked To Apply The Review

Even when the user asks you to apply plan review feedback, evaluate the items
first. Push back on invalid, stale, speculative, or scope-expanding comments
before editing. Clarify blocking ambiguities before changing the plan.

## Response Shape

```markdown
I'm reviewing the plan review as feedback to evaluate, not as approval to edit the plan.

1. [Reviewer item]
   Assessment: Valid | Invalid | Needs investigation | Needs clarification | Already handled | Optional/taste
   Evidence: [plan/spec/repo references or missing evidence]
   Recommendation: [fix, reject, defer, clarify, or investigate]
```

## Bottom Line

Plan reviews improve plans only after their claims are checked. Evaluate first;
edit only when explicitly asked.
