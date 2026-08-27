# Review Response Format

This contract applies to agents responding to reviewer reports. Reviewer
reports stay detailed: fresh and delegated plan, spec, and code reviewers keep
their existing evidence, severity, recommendation, and readiness formats.

## Response order

1. Preserve any exact review-mode sentence required by the active reception skill.
2. Emit the compact no-decision section when it is non-empty.
3. End with exactly one owner decision when owner input is required.

After Josh answers, acknowledge and record the choice, then present the next
owner decision without repeating the completed compact list. State only how
many decisions remain; do not preview or bundle them.

## Compact no-decision lane

Review-only heading:

```markdown
### No decision needed — no changes made
```

Authorized application heading:

```markdown
### Handled without asking
```

Every item is one bullet:

```markdown
- **one-to-five-word shorthand — VALID | REJECT | DEFER[ · CRITICAL | IMPORTANT | MINOR]** — reason of at most 40 words
```

- `VALID` means the finding is correct and existing requirements, tests, or established repository patterns already determine the answer.
- `REJECT` means the finding is wrong, stale, duplicated, or contradicted by evidence.
- `DEFER` means the idea or harmless preference is reasonable, clearly non-blocking, and already outside approved scope.
- A harmless naming, heading, or style preference is `DEFER`, not `REJECT`, when no repository convention or functional need requires it, even when applying it would create needless churn.
- Urgency is optional, appears only on `VALID` findings, and is used only when it materially helps prioritization.
- Make shorthand handles unique within the response. Locations are optional; include one inside the reason only when it improves clarity.
- State concrete evidence and the proposed action or actual outcome in no more than 40 words.
- Put urgent valid findings first and preserve natural review order otherwise.
- Omit empty sections and repetitive summaries.
- On `Expand <shorthand>`, return full evidence, affected files or plan steps, and the proposed action.
- Never use `REJECT` or `DEFER` to silently choose product behavior, scope, or architecture. Move that item to the owner-decision lane.

## Owner-decision lane

Use ordinary wording, one concrete example, and exactly one owner decision per response.
Offer at least two genuine options lettered `A` through `Z`. Give each option
concrete pros and cons, and mark exactly one recommended option.

When several decisions remain, show only the first in review order. Make the
first non-empty line after `### Your decision needed` a plain one-to-five-word
decision name. Include exactly one concrete `Example:` line before the options.

```markdown
### Your decision needed

**Plain one-to-five-word decision name**

One direct question in simple language.

Example: A concrete situation showing what changes.

- **A. First option — recommended**
  - Pros: Concrete benefits.
  - Cons: Concrete costs or risks.
- **B. Second option**
  - Pros: Concrete benefits.
  - Cons: Concrete costs or risks.
```

If the shown request has a technical identifier, put that exact identifier in
the `Example:` line only. Hide every later request's name, details, example,
and tradeoffs. The remaining count excludes the decision currently shown and
counts only later hidden decisions. When one later decision remains, write the
standalone sentence `One decision remains.` End the response with this owner
section.

Accept a letter-only answer, a modified option, or a new direction. Record the
answer and do not ask it again unless new evidence changes the tradeoff.
Continue independent, already-decided work while waiting, but never implement
the gated item early. If only one path satisfies existing requirements, the
item is `VALID`; do not manufacture alternatives.

## Detailed evidence

Read and evaluate the complete reviewer report before classifying it. Keep that
report available for `Expand`, but do not repeat the detailed report by default.
Investigate or ask a factual clarification before classification when evidence
is insufficient.

Include a readiness line only when it adds information about whether work may
proceed. Automated test failures are evidence, not automatic owner decisions;
verify whether they come from the reviewed change, a stale expectation, the
environment, or pre-existing behavior before classifying them.
