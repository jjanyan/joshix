# Review Response Format

This contract applies to agents responding to reviewer reports about concrete
code or diff, a named plan, or a named spec. It does not apply to task history,
`current.md`, product discussion, proposed architecture, or general chat.
Reviewer reports stay detailed: fresh and delegated plan, spec, and code
reviewers keep their existing evidence, severity, recommendation, and readiness
formats.

## Response grammar

Emit only non-empty lanes, in this order:

| Position | Emit when | Exact form |
|---|---|---|
| 0 | Semantic explicit no-edit mode | Artifact-specific opening defined by the bootstrap. It is the first emitted agent sentence and first non-empty line of the final response. It replaces the generic skill announcement; any required shared-task notice follows on its own line. |
| 1 | Settled findings exist, or a change was applied | Exactly one applicable settled lane heading plus compact finding bullets. |
| 2 | A reviewer claim cannot be settled from available evidence | `### Evidence needed — no changes made` plus evidence bullets. |
| 3 | The outcome is informative | `### Review outcome` plus exactly one outcome. |
| 4 | Owner input is required | `### Your decision needed`; this is always the final section. |

After Josh answers, acknowledge and record the choice, then present the next
owner decision without repeating completed findings. Do not reclassify the
owner's choice as `VALID`, `REJECT`, or `DEFER`.

### Settled lane

Choose exactly one heading:

| Heading | Use only when |
|---|---|
| `### No decision needed — no changes made` | The compact no-decision lane is non-empty, Agent 1 applied no changes, and no owner decision is required. Omit it for clean approval, no findings, unsettled-evidence-only responses, and owner-decision-only responses. |
| `### Handled without asking` | Automatic mode actually applied at least one change without an explicit apply, fix, or proceed request. |
| `### Applied as requested` | An explicit application request actually resulted in at least one change, or an owner-answer continuation applied the answer or newly unblocked work. |

The settled item grammar is:

```markdown
### No decision needed — no changes made

- **one-to-five-word shorthand — VALID | REJECT | DEFER[ · CRITICAL | IMPORTANT | MINOR]** — reason of at most 40 words
```

- `VALID` means the finding is correct and existing requirements, tests, or
  established repository patterns determine the answer.
- `REJECT` means the finding is wrong, stale, duplicated, or contradicted by
  evidence.
- `DEFER` means the idea or harmless preference is reasonable, clearly
  non-blocking, and already outside approved scope. A harmless naming, heading,
  or style preference is `DEFER`, not `REJECT`, even when applying it would
  create needless churn.
- `VALID`, `REJECT`, and `DEFER` apply only to actual review findings. Never
  render approval as a `VALID` issue. Never force an unclear or unverified
  claim into a settled label.
- Urgency is optional and appears only on `VALID` findings when it materially
  helps prioritization.
- Use unique shorthand handles. State concrete evidence and the proposed action
  or actual outcome in no more than 40 words. Preserve natural review order
  except for urgent valid findings. Omit empty sections and repetitive summaries.
- Under an active workflow policy, include each finding's repository tier tag.
  A priced lower-tier finding is shown as a deferred observation with its task
  history ID; do not imply it was implemented or still needs routine brokering.
- On `Expand <shorthand>`, return full evidence, affected files or plan steps,
  and the proposed action.
- Never use `REJECT` or `DEFER` to silently choose product behavior, scope, or
  architecture. Move that item to the owner-decision lane.

### Evidence lane

This lane is distinct from the settled issue lane. Do not label these items
`VALID`, `REJECT`, or `DEFER`. Leave the artifact unchanged and use `Rereview
required`. Name the specific missing evidence and the action Agent 2 must take.

```markdown
### Evidence needed — no changes made

- **short handle** — Missing evidence: {specific unavailable source or fact}. {what Agent 2 must provide, clarify, accept, or rebut}
```

### Outcome lane

The review producer's `**Status:** Approved | Issues Found` is provisional. It
communicates review readiness, not the authoritative artifact outcome. After
independent verification, Agent 1 emits exactly one authoritative artifact
outcome unless an owner-decision lane alone communicates the only unresolved
blocker. Do not suppress the outcome when applied changes, unresolved
disagreement, or unsettled evidence make it informative.

Use the exact `### Review outcome` lane whenever an outcome is emitted; never
substitute an inline `Outcome:` label.

| Outcome | Use only when |
|---|---|
| **Approved** — Agent 1 agrees that no actual findings remain. | `Approved` requires a current Agent 2 approval plus Agent 1 concurrence with no unresolved dispute. |
| **Rereview required** — Another Agent 2 pass is required because the artifact changed, an accepted objective finding remains unapplied, or a reviewer-raised finding remains unsettled, disputed, or lacks evidence. | Any artifact change; any rejected or deferred finding Agent 2 has not accepted; any unsettled evidence; or any accepted-but-unapplied finding. In semantic explicit no-edit mode, any accepted objective finding left unapplied requires `**Rereview required**`. |
| **Approval disputed** — Agent 2 approved the artifact, but Agent 1 identified a newly discovered concern that must wait for Agent 2's next review. | Agent 2 approved, but Agent 1 does not concur because of a new concern. |

When `Rereview required` follows a `REJECT` or `DEFER`, its outcome reason must
explicitly state that Agent 2 must accept or rebut Agent 1's reasoning.

### Owner-decision lane

Use ordinary wording, one concrete example, and exactly one owner decision per
response. Offer at least two genuine options lettered `A` through `Z`. Give each
option concrete pros and cons, and mark exactly one recommended option.

Make the first non-empty line after `### Your decision needed` a plain
one-to-five-word decision name. Include exactly one concrete `Example:` line
before the options.

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
the `Example:` line only. Hide every later request's details and tradeoffs. The
remaining count excludes the shown decision. When one later decision remains,
write the standalone sentence `One decision remains.` End the response with
this owner section.

Accept a letter-only answer, modified option, or new direction. Record it and
do not ask again unless new evidence changes the tradeoff. Continue independent,
already-decided work while waiting, but never implement the gated item early. If
only one path satisfies existing requirements, the item is `VALID`; do not
manufacture alternatives.

### Evidence and detail

Read and evaluate the complete reviewer report before classifying it. Keep it
available for `Expand`, but do not repeat the detailed report by default.
Investigate or ask a factual clarification when evidence is insufficient.
Include a readiness line only when it adds information about whether work may
proceed. Automated test failures are evidence, not automatic owner decisions;
verify whether they come from the reviewed change, a stale expectation, the
environment, or pre-existing behavior before classifying them.

### Readiness hold

Approval is not authorization for the next phase. A readiness hold is local to
the reviewed artifact and its immediate next phase. Use it only when the
current review just approved a spec whose next phase is planning or a plan
whose next phase is execution, and that phase requires an explicit owner
command. Never infer a readiness hold from another queued task, plan, or
artifact. Never append one after implementation or code-review completion.
When no genuine unresolved choice remains, never emit `### Your decision
needed`, invent options, or ask a question. When a hold applies, report the
settled state and end with exactly one applicable line:

`Ready to plan; waiting for your command.`

`Ready to execute; waiting for your command.`

Use the owner-decision lane only for a real unresolved choice. When a genuine
choice exists, render the lane and options; do not merely describe its grammar.
