---
name: receiving-spec-review
description: Use when spec review feedback, pasted spec reviewer comments, or critique of a design spec is provided, including requests to evaluate, apply, address, respond to, or get it done.
---

# Spec Review Reception

Read and follow
`../using-joshix/references/review-reception-contract.md` and
`../using-joshix/references/review-response-format.md` completely. The first is
the single decision table for authority and convergence; the second is the
single response grammar. Do not restate either here. The canonical reference
owns the exact presentation grammar.

## Reception Mode

Receiving another agent's spec review enters automatic meta-review mode by
role. Verify the report against the spec, settled owner decisions, repository
context, and approved requirements, then follow the canonical decision table.
Semantic explicit no-edit mode uses the bootstrap's spec-specific exact
opening, placed by the canonical response grammar, and never executes the spec.

When a workflow policy is active and the report is structured, apply the
canonical policy-active tier validation and pricing before the spec-specific
classification below. Policy absence preserves existing reception behavior.

## Spec Classification

Objective corrections include verified contradictions, missing approved
requirements, placeholders, stale statements, and broken references. Apply
them minimally while preserving the document's topology and unrelated content.
Test any machine-checkable contract affected by an edit. Harmless heading,
naming, and style preferences are normally non-blocking `DEFER` items.

## Owner Decision Gate

New product behavior, scope, acceptance criteria, ownership, or architecture
requires Josh's decision unless settled requirements already determine it. A
reviewer-requested new class, module, service, policy object, owner, layer,
dependency, directory, registry, or extraction is gated unless already approved
or established.

Do not use `REJECT` or `DEFER` to choose an unresolved gated question.
Automatic reception never authorizes implementation, unrelated spec expansion,
staging, commits, branches, pushes, pull requests, or deployment.
