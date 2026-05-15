---
name: receiving-code-review
description: Use when receiving code review feedback, pasted agent reviews, review comments, critique of code changes, or questions like "what do you think of this review?" Unless the user explicitly asks to fix/apply changes, first say "I'm reviewing the review..." before analysis, then evaluate item by item without editing.
---

# Code Review Reception

<EXTREMELY-IMPORTANT>
If the user provides a pasted review, agent review, review comments, or
review-like critique and does not explicitly ask you to implement changes, your
first non-empty sentence MUST say you are reviewing the review. Do this before
code research, findings, summaries, or recommendations.
</EXTREMELY-IMPORTANT>

## Overview

Code review feedback is input to evaluate, not an order to execute.

**Core principle:** Default to review-review mode. Verify before implementing.
Ask before assuming. Technical correctness over social compliance.

## Default: Review-Review Mode

When the user provides review feedback, pasted agent review, review comments,
or review-like text, treat it as something to evaluate unless they explicitly
ask you to make changes.

Immediately announce the mode so the user knows you are reviewing the review,
not starting edits:

```text
I'm reviewing the review as feedback to evaluate, not as approval to edit files.
```

or:

```text
I'll review this feedback item by item before making any changes.
```

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
- Classify each item as valid, invalid, needs investigation, needs
  clarification, already handled, or optional/taste.
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
6. RESPOND: Item-by-item assessment with evidence
7. WAIT: Do not implement unless explicitly told to act
```

## If Asked To Implement

When the user explicitly asks to apply review feedback:

```
1. Evaluate the feedback first
2. Clarify any unclear or conflicting items before editing
3. Implement verified fixes one item at a time
4. Test each meaningful fix
5. Verify no regressions
6. Report what changed and what remains
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

## Item-by-Item Format

Use this shape when reviewing a pasted review:

```markdown
I'm reviewing the review as feedback to evaluate, not as approval to edit files.

1. [Reviewer item]
   Assessment: Valid | Invalid | Needs investigation | Needs clarification | Already handled | Optional/taste
   Evidence: [code/test/doc references or what is missing]
   Recommendation: [fix, reject, defer, clarify, or investigate]

2. [Reviewer item]
   Assessment: ...
```

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
| Can't verify, proceed anyway | State limitation and ask for direction |

## Bottom Line

Review feedback is evidence to reason about.

Evaluate it. Explain what is valid. Push back on what is wrong. Make changes
only when the user explicitly asks.
