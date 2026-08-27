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
Treat the exact sentence as the required skill announcement. Do not prepend a
skill-name or repository-context announcement.

Then evaluate the review item by item. Do not edit files, stage, commit, branch,
or start implementation unless the user explicitly asks for that action.

## How To Evaluate

For each review item:

1. Read the full review before reacting.
2. Check the claim against the plan, spec, repo context, and existing workflow
   rules.
3. Classify settled findings as `VALID`, `REJECT`, or `DEFER` under the
   canonical response contract.
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

## Owner Decision Gate

Objective plan corrections may be recommended or applied when edits are
authorized. New product behavior, scope, ownership, or architecture requested
by plan feedback requires Josh's decision when existing requirements do not
already settle it. Application language authorizes verified objective fixes;
it does not authorize a new owner decision.

When the gate triggers, leave that part of the plan unchanged, continue only
independent objective work, and ask one concrete question using the canonical
one-at-a-time owner-decision format.

Treat each independent product, scope, ownership, or architecture request as a
separate decision. When several remain, show only the first in review order.
The canonical reference owns the exact presentation grammar, including plain
naming, technical-identifier placement, hidden later requests, the remaining
count, and response order.

Never use `REJECT` or `DEFER` to dispose of an unresolved architecture request,
including when the user says not to make the decision for them. That instruction
means preserve the plan and present the choice in the owner-decision lane.

## If Asked To Apply The Review

Even when the user asks you to apply plan review feedback, evaluate the items
first. Push back on invalid, stale, speculative, or scope-expanding comments
before editing. Clarify blocking ambiguities before changing the plan.
Apply objective corrections minimally. When reordering existing steps, copy
their heading wording verbatim and change only the ordinal when the verified
feedback changes ordering alone. Add, split, or rename steps only when the
verified feedback itself requires that structural change.

## User-Facing Response

Read and follow `../using-joshix/references/review-response-format.md`
completely before composing the response. Map verified review claims to
`VALID`, `REJECT`, or `DEFER` only after checking plan, spec, and repository
evidence.

Use the review-only heading when no plan edits were authorized. When
application was authorized, use the handled heading and past tense for
completed objective work. Move every unresolved product, scope, ownership, or
architecture choice to the one-at-a-time owner-decision lane.

## Bottom Line

Plan reviews improve plans only after their claims are checked. Evaluate first;
edit only when explicitly asked.
