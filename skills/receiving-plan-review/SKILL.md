---
name: receiving-plan-review
description: Use when receiving pasted Plan Review feedback, plan reviewer comments, critiques of an implementation plan, or questions like "what do you think of this plan review?"
---

# Plan Review Reception

Read and follow
`../using-joshix/references/review-reception-contract.md` and
`../using-joshix/references/review-response-format.md` completely. The first is
the single decision table for authority and convergence; the second is the
single response grammar. Do not restate either here. The canonical reference
owns the exact presentation grammar.

## Reception Mode

Receiving another agent's plan review enters automatic meta-review mode by
role. Verify the report against the plan, approved spec, repository context,
and workflow rules, then follow the canonical decision table. Semantic explicit
no-edit mode uses the bootstrap's plan-specific exact opening, placed by the
canonical response grammar, and never starts implementation.

When a workflow policy is active and the report is structured, apply the
canonical policy-active tier validation and pricing before the plan-specific
classification below. Policy absence preserves existing reception behavior.

## Plan Classification

Objective plan findings include missing approved requirements, placeholders
that block implementation, undefined files or dependencies, contradictory task
order or test expectations, scope beyond the approved spec, and missing required
documentation or verification work.

Wording preferences, alternate task naming, and workable split/combine
suggestions are normally non-blocking `DEFER` items. When ordering alone is the
defect, preserve headings and change only order. When relocating commands,
symbols, or details, move their single occurrence and remove the stale source;
preserve the plan topology and do not create duplicates.

## Owner Decision Gate

New product behavior, scope, ownership, or architecture requested by plan
feedback requires Josh's decision unless approved requirements already settle
it. New acceptance criteria are gated on the same basis. A reviewer-requested
new class, module, service, policy object, owner, layer, dependency, directory,
registry, or extraction is gated unless already approved or established.

Do not use `REJECT` or `DEFER` to choose an unresolved gated question.
Automatic reception never authorizes implementation, unrelated plan expansion,
staging, commits, branches, pushes, pull requests, or deployment.
