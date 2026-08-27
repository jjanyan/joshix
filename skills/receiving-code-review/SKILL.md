---
name: receiving-code-review
description: Use when code review feedback, code review comments, pasted agent code reviews, or critique of code changes are provided, including requests to evaluate, fix, apply, address, respond to, or get it done.
---

# Code Review Reception

<EXTREMELY-IMPORTANT>
If the user provides a pasted code review, agent code review, code review
comments, or review-like critique of code changes and does not explicitly ask
you to implement changes, your first non-empty sentence MUST say you are
reviewing the review. Do this before code research, findings, summaries, or
recommendations.

Use this exact sentence:

```text
I'm reviewing the review as feedback to evaluate, not as approval to edit files.
```

Do not replace it with a general skill/workflow announcement.
Treat the exact sentence as the required skill announcement. Do not prepend a
skill-name or repository-context announcement. If the host requires commentary
before tool use, make this exact sentence the first sentence of that commentary.
</EXTREMELY-IMPORTANT>

## Overview

Code review feedback is input to evaluate, not an order to execute.

**Core principle:** Default to review-review mode. Verify before implementing.
Ask before assuming. Technical correctness over social compliance.

<EXTREMELY-IMPORTANT>
The Owner Decision Gate is mandatory before file edits in implementation mode.
When review feedback asks for product behavior, user-facing meaning, new
architecture, new modules/classes/services, or ownership-boundary changes, stop
and ask the owner before editing that item. "Fix these", "apply this", and "get
it done" do not override this gate.

Each independently requested architecture change is a separate owner decision.
Never merge independent review items into one umbrella question or option set.
When several remain, present only the first in review order. The canonical
reference owns the exact presentation grammar, including plain naming,
technical-identifier placement, hidden later requests, the remaining count,
and response order.
The gate blocks only the gated item. In implementation mode, complete every
verified independent objective fix before asking the first owner question; never
delay objective work because a separate review item is gated.
</EXTREMELY-IMPORTANT>

## Default: Review-Review Mode

When the user provides code review feedback, pasted agent code review, code
review comments, or review-like critique of code changes, treat it as something
to evaluate unless they explicitly ask you to make changes.

Immediately announce the mode so the user knows you are reviewing the review,
not starting edits:

```text
I'm reviewing the review as feedback to evaluate, not as approval to edit files.
```

This exact sentence is the only permitted review-only opening.

Do not start with a result or summary. These first sentences are wrong because
they skip the mode announcement:
- "I evaluated the review against the current repo."
- "I checked the current repo."
- "The review is mixed."
- "No files were changed."

In review-review mode:
- Do not edit files.
- Do not stage, commit, branch, or open review requests.
- Read the relevant code, diffs, tests, and docs needed to evaluate the claims.
- Respond item by item with a researched technical assessment.
- Classify each settled item as `VALID`, `REJECT`, or `DEFER` under the
  canonical response contract.
- Cite concrete codebase evidence when possible.
- Identify overreach, missing context, speculation, duplicate findings, and
  taste-based suggestions.
- Recommend what to do next, but do not do it unless explicitly asked.

Only switch from review-review mode to implementation mode when the user
explicitly asks, for example: "fix these", "get it done", "apply this",
"make the changes", or equivalent.

## Response Pattern

```
WHEN receiving review feedback:

1. ANNOUNCE: State review-review mode before analysis
2. READ: Complete feedback without reacting
3. UNDERSTAND: Identify each concrete claim or requested change
4. RESEARCH: Check against codebase reality
5. EVALUATE: Technically sound for this codebase?
6. GATE: Classify objective fixes separately from owner decisions
7. RESPOND: Use the canonical compact lane for settled findings and one owner decision when needed
8. WAIT: Do not implement unless explicitly told to act
```

## Owner Decision Gate

Before recommending or implementing a review item, classify the decision type.

- **Objective fixes:** clear bugs, broken tests, regressions, typos, missing
  focused tests, violated existing contracts, or violations of already-established
  repo patterns. These may be recommended or implemented when the user asks,
  after verification.
- **Product/owner decisions:** intended user-facing behavior, UX semantics,
  business rules, access policy, defaults, data retention, user promises,
  acceptance criteria, or copy that changes product meaning. Ask the owner before
  editing when the answer is not already specified.
- **Architecture decisions:** new abstractions, ownership boundaries, persistence
  models, API contracts, dependencies, cross-cutting services, migration
  strategies, or patterns not already established in the repo. Ask the owner
  before editing when the decision is new or ambiguous.
- **Reviewer-requested architecture:** a review item that asks for a new class,
  module, service, layer, policy object, shared owner, central registry, or
  extraction is an architecture decision unless the user/spec already approved
  that structure or the repo already has the same local pattern.
- **Unclear:** if an item could fit more than one category, treat it as gated
  and ask.

The reviewer's recommendation is not owner approval. "Fix these", "apply this",
or "get it done" authorizes verified objective fixes; it does not authorize
inventing product behavior or introducing new architecture.

When the gate triggers:
1. Explain why the item needs owner input.
2. Ask one concrete question with a recommendation and the tradeoff.
3. Do not edit the gated item until the owner answers.
4. Continue independent objective fixes only if they do not depend on the gated
   decision.

The mandatory gate above governs objective-work-first behavior.

Do not create a new class, module, service, policy object, directory, dependency,
or cross-cutting abstraction solely because a reviewer requested it. Ask first.
If you make independent objective fixes while leaving a gated item unedited, the
final response must include the concrete owner question. Do not only say that
approval is needed.

Use the canonical owner-decision lane referenced under User-Facing Response.
It supplies the required direct question, concrete example, lettered options,
pros and cons, and exactly one recommendation.

## If Asked To Implement

When the user explicitly asks to apply review feedback:

```
1. Evaluate the feedback first
2. Run the Owner Decision Gate for each item before editing files
3. Clarify gated, unclear, or conflicting items before editing them
4. Implement verified objective fixes one item at a time
5. Test each meaningful fix
6. Verify no regressions
7. Report what changed and what was gated, then ask only the next owner
   question. State only how many decisions remain. Do not preview or bundle
   later decisions.
```

Do not blindly apply the entire review. If an item is wrong, stale, speculative,
or conflicts with user/repo guidance, push back with technical reasoning before
editing.

## Honest Questions

If review feedback or the user's message contains a real question, answer the
question before making changes.

Examples:
- "Is this reviewer right?" means evaluate and answer, not edit.
- "What do you think of this review?" means evaluate and answer, not edit.
- "Which of these should we do?" means recommend a path, not edit.

Rhetorical questions paired with an explicit action request can still be acted
on, but only after the review items are understood.

## Source-Specific Handling

### From the User

User feedback has priority, but it still needs technical clarity.

- Implement only when the user explicitly asks for implementation.
- Ask when scope, expected behavior, or acceptance criteria are unclear.
- Explain when a request conflicts with codebase constraints, prior decisions,
  or test evidence.
- Avoid ceremonial agreement; respond with evidence, decisions, or action.

### From External or Agent Reviewers

External and agent review feedback is a set of claims to check.

Before accepting a finding:
1. Is it technically correct for this codebase?
2. Does it break existing behavior?
3. Is there a reason the current implementation exists?
4. Does it apply to supported platforms, versions, or configurations?
5. Does the reviewer have the relevant context?
6. Is it a real risk, or just a preference?

If you cannot verify an item, say what evidence is missing and whether the next
step should be investigation, clarification, or rejection.

## YAGNI Check

When a reviewer asks for a "proper", "complete", or "production-ready" version
of something, check actual usage before expanding scope.

```
IF reviewer suggests building more:
  Search for actual usage and requirements

  IF unused or unsupported by requirements:
    Recommend removing or deferring instead of building

  IF used and required:
    Implement properly only after explicit user instruction
```

## When To Push Back

Push back when:
- The suggestion breaks existing functionality
- The reviewer lacks relevant context
- The item is speculative or taste-based
- The item violates YAGNI
- The item is technically incorrect for this stack
- Compatibility or migration constraints apply
- The item conflicts with user or repo guidance

How to push back:
- Use technical reasoning, not defensiveness
- Reference code, tests, docs, or requirements
- Ask specific questions when the correct path is ambiguous
- Involve the user when the tradeoff is product, architecture, or scope

## Response Tone

Keep responses concise, technical, and evidence-based.

Avoid performative agreement:
- Do not say "You're absolutely right" before checking.
- Do not say "Great point" as a substitute for analysis.
- Do not say "Let me implement that now" unless the user explicitly asked for
  implementation and you have verified the item.

Brief courtesy is fine, but it must not replace verification, evidence, or a
clear decision.

## User-Facing Response

Read and follow `../using-joshix/references/review-response-format.md`
completely before composing the response. Map verified review claims to
`VALID`, `REJECT`, or `DEFER` only after checking repository evidence.

Use the review-only heading when no edits were authorized. When application was
authorized, use the handled heading and past tense for completed objective
work. Move every unresolved product, scope, ownership, or architecture choice
to the one-at-a-time owner-decision lane.

If the review includes automated test output, separate review findings from test
failures. Test failures are evidence, but still verify whether they are caused
by the reviewed changes, environment issues, stale tests, or pre-existing
behavior.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Pasted review triggers edits | Announce review-review mode and evaluate only |
| Blind implementation | Verify against codebase first |
| Partial understanding | Clarify all blocking ambiguities first |
| Assuming reviewer is right | Check code, tests, docs, and requirements |
| Avoiding pushback | Technical correctness over social comfort |
| Treating taste as requirement | Separate objective risk from preference |
| Treating review as product approval | Use the Owner Decision Gate before editing |
| Adding new architecture from review feedback | Ask the owner before introducing new patterns |
| Can't verify, proceed anyway | State limitation and ask for direction |

## Bottom Line

Review feedback is evidence to reason about.

Evaluate it. Explain what is valid. Push back on what is wrong. Make changes
only when the user explicitly asks and the Owner Decision Gate allows it.
