---
name: receiving-code-review
description: Use when code review feedback, code review comments, pasted agent code reviews, or critique of code changes are provided, including requests to evaluate, fix, apply, address, respond to, or get it done.
---

# Code Review Reception

Read and follow
`../using-joshix/references/review-reception-contract.md` and
`../using-joshix/references/review-response-format.md` completely. The first is
the single decision table for authority and convergence; the second is the
single response grammar. Do not restate either here. The canonical reference
owns the exact presentation grammar.

## Reception Mode

Receiving another agent's code review enters automatic meta-review mode by
role. Verify the report against the code, tests, approved requirements, and
repository guidance, then follow the canonical decision table. Semantic
explicit no-edit mode uses the bootstrap's code-specific exact opening, placed
by the canonical response grammar.

When a workflow policy is active and the report is structured, apply the
canonical policy-active tier validation and pricing before the code-specific
classification below. Policy absence preserves existing reception behavior.

## Code Classification

Objective findings include verified bugs, regressions, broken tests, typos,
missing focused tests, violated approved contracts, and violations of an
established repository pattern. Invalid, stale, speculative, taste-only, and
unverified findings are not objective authority.

For every claim, check technical correctness, compatibility, actual usage,
approved behavior, and whether the reviewer had the relevant context. Push back
with code, test, documentation, or requirement evidence. Check actual usage
before accepting requests for a "proper", "complete", or "production-ready"
expansion.

## Owner Decision Gate

- **Product/owner decisions:** intended user-facing behavior, UX semantics,
  business rules, access policy, defaults, retention, user promises, meaning,
  ownership, scope, or acceptance criteria.
- **Architecture decisions:** a new abstraction, ownership boundary,
  persistence model, API contract, dependency, cross-cutting service, migration
  strategy, or pattern.
- **Reviewer-requested architecture:** a new class, module, service, policy
  object, owner, layer, dependency, directory, registry, or extraction is gated
  unless already approved or established.

Each independently requested architecture change is a separate owner decision.
After objective work, ask only the next owner question, state only how many
decisions remain. Do not preview or bundle later decisions.

## Code Application

Apply accepted code corrections surgically. Replace stale behavior in place;
do not append or shadow a second result. Preserve unrelated comments, exports,
declarations, tests, and surrounding structure. Verify observable behavior, not
merely the presence of new text. Never refactor unrelated code.

Automatic reception never authorizes staging, commits, branches, pushes, pull
requests, deployment, unrelated refactoring, new product scope, or new
architecture.
