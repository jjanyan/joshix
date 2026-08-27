---
name: receiving-spec-review
description: Use when spec review feedback, pasted spec reviewer comments, or critique of a design spec is provided, including requests to evaluate, apply, address, respond to, or get it done.
---

# Spec Review Reception

Spec review feedback is input to evaluate, not an order to rewrite the spec.

## Default Mode

If the user provides spec review feedback and does not explicitly ask to edit
the spec, begin with this exact sentence:

I'm reviewing the spec review as feedback to evaluate, not as approval to edit the spec.

Treat that exact sentence as the required skill announcement. Do not prepend a
skill-name or repository-context announcement. If the host requires commentary
before tool use, make this exact sentence the first sentence of that commentary.

Then evaluate every claim. Do not edit files or perform git operations unless
the user explicitly asks for that action.

## Evaluation

For each item, read the complete review, check the claim against the spec,
settled user decisions, repository context, and existing requirements, then
decide whether it is correct, false, non-blocking and outside scope, unclear,
or already handled.

## Owner Decision Gate

Objective corrections such as contradictions, missing approved requirements,
placeholders, and broken references may be recommended or applied when edits
are authorized. New product behavior, scope, acceptance criteria, ownership,
or architecture requires Josh's decision when existing requirements do not
already settle it. Application language authorizes verified objective fixes;
it does not authorize a new owner decision.

When the gate triggers, leave that part of the spec unchanged, continue only
independent objective work, and ask one concrete owner question using the
canonical lettered format.

Treat each independent product, scope, acceptance-criteria, ownership, or
architecture request as a separate decision. When several remain, show only
the first in review order. The canonical reference owns the exact presentation
grammar, including plain naming, technical-identifier placement, hidden later
requests, the remaining count, and response order.

Never use `REJECT` or `DEFER` to dispose of an unresolved product, scope, or
architecture request, including when the user says not to make the decision for
them. Preserve the spec and present the choice in the owner-decision lane.

## Authorized Application

When the user explicitly asks to update the spec, verify each item first,
apply objective corrections, preserve rejected or deferred content, test any
machine-checkable contract affected by the edit, and stop before gated items.

## User-Facing Response

Read and follow `../using-joshix/references/review-response-format.md`
completely before composing the response. Use the review-only heading when no
edits were authorized. Use the handled heading and past tense only for completed
objective edits. Map verified claims to `VALID`, `REJECT`, or `DEFER`, and move
unresolved product, scope, ownership, or architecture choices to the
one-at-a-time owner-decision lane.
