# Review Reception Contract

This contract applies only when an artifact-owning agent receives another
agent's review of concrete code or diff, a named plan, or a named spec. It is
inapplicable to task history, `current.md`, product discussion, proposed
architecture, and general chat. The roles, not fresh `apply`, `fix`, or
`proceed` wording, determine default edit authority.

Agent 2 is a read-only review producer. Agent 1 is the meta-review receiver and
artifact owner. Agent 1 independently verifies every finding before classifying
or editing. Automatic authority covers only objective findings raised by Agent
2 and accepted by Agent 1. New product, scope, ownership,
acceptance-criteria, or architecture choices remain owner-gated.

## Decision table

| Situation | Required action | Result |
|---|---|---|
| Semantic explicit no-edit instruction | Evaluate every finding and leave the artifact unchanged. | Use the artifact-specific review-only opening. Any accepted objective finding left unapplied requires rereview. |
| Question merely solicits meta-review | A question that merely solicits meta-review does not pause automatic mode. | Continue with the rows below. |
| Substantive question about whether work should occur | A semantic explicit no-edit instruction or a substantive question about whether work should occur does pause edits. | Answer before editing. |
| Agent 2 finding is verified and objective | Apply every independent accepted objective finding raised by Agent 2. Verify the resulting artifact. | Report automatic or requested application; any changed artifact requires rereview. |
| Agent 2 finding is wrong, stale, duplicated, or contradicted | Leave it unchanged and explain the repository evidence. | `REJECT`; Agent 2 must accept or rebut it. |
| Agent 2 finding is a reasonable non-blocking preference outside approved scope | Leave it unchanged and explain the scope boundary. | `DEFER`; Agent 2 must accept or rebut it. |
| Agent 2 finding lacks evidence | Leave it unchanged and name the missing source or fact. | Evidence-needed lane; Agent 2 supplies evidence, clarifies, accepts, or rebuts. |
| Agent 2 finding asks for a new product, scope, ownership, acceptance-criteria, or architecture choice | Finish independent objective work, leave the gated item unchanged, then ask exactly one owner question. | Owner-decision lane; do not silently choose with `REJECT` or `DEFER`. |
| Josh answers an owner question | After Josh answers an owner question, apply the answer and newly unblocked work without another permission request. When prior shared reasoning or the review supplies exact replacement text, preserve it verbatim rather than restyling or elaborating it. | Report the applied continuation as requested; a changed artifact requires rereview. |
| Agent 1 discovers a concern Agent 2 did not raise | A newly discovered concern from Agent 1 remains unchanged until Agent 2 agrees in a later review. | If Agent 2 approved, approval is disputed; otherwise explain the concern for the next pass. |
| Later Agent 2 review says a previous automatic change was wrong | If a later Agent 2 pass identifies a previously applied automatic change as wrong, that report is an ordinary new finding. Verify it and apply an objective correction automatically; the prior application does not create a new owner gate. | A changed artifact requires rereview. |
| Current Agent 2 review approves and Agent 1 concurs | Make no change. | Approved. |
| The current review approves a spec or plan and that artifact's immediate next phase lacks explicit authorization | Treat artifact-local readiness as settled state, not an unresolved choice. | Emit the exact readiness hold from the response format; never manufacture owner options or borrow readiness from queued work. |

## Policy-active structured findings

After independent verification, validate a structured finding's surface and
criticality against the active declaration and policy, then price it before the
legacy finding classification above:

| Comparison | Required action | Result |
|---|---|---|
| Lower than the affected changed surface | Append an idempotent deferred observation and reference its history ID in the snapshot. Never implement it without explicit owner authorization. | Settled and visibly deferred; it does not force another producer pass. |
| Equal to the affected changed surface | Fix or rebut once within authorized scope. | Continue the bounded review loop. |
| Higher than the affected changed surface | Stop before editing and emit the decision memo immediately. | Bubble-up. |
| Not tied to one changed surface | Compare with the task-level criticality. | Apply the same lower, equal, or higher action. |

Unknown names make the producer result malformed; never guess. Severity remains
separate from criticality. After one unresolved rebuttal, `dev` instance choices
inside established policy are coordinator-settled and logged; new or changed
`policy` and `product` choices bubble up. An approved spec or plan whose own
immediate next phase remains unauthorized uses the readiness hold, never the
owner-decision lane. Other approval reports do not inherit a hold from queued
work.

Rejected, deferred, unclear, and unverified findings remain unchanged with
evidence-backed reasoning in the shared conversation. Complete all independent
objective work before the first owner question. Do not add orchestration state
or a dispute ledger.

## Failure recovery

Expected pre-application diagnostics and a deliberate TDD-red result may guide
an accepted change. Bounded retry and fallback protocols defined elsewhere
remain authoritative.

After application begins, an unexpected edit or verification failure pauses
further writes to the affected artifact while Agent 1 diagnoses the failure
read-only. Preserve the artifact's exact current state and never automatically
roll back a partial change. A verification failure is evidence, not by itself a
reason to end the turn.

Agent 1 continues automatically without an owner message when diagnosis
establishes the artifact's current state and identifies an objective, in-scope
correction that needs no new product, policy, architecture, scope, destructive,
or irreversible decision. Apply one correction for that failure and run
focused verification. If it passes, resume ordinary review reception. Do not
rerun a passing focused verification solely to confirm it. A failure in that
correction or its focused check ends automatic correction rather than opening
another attempt. Across one review application, no more than two such
corrections may be attempted.

For policy-active completion-gate recovery, follow `autonomous-review.md`.
Its producer-pass, infrastructure-retry, and recovery-repair budgets supersede
this general reception rule.

Stop before further writes when the current state is uncertain, recovery risks
overwriting user changes, recovery requires excluded authority or scope
expansion, a recovery pass fails, a third recovery pass would be required, or a
review, effort, or scope cap fires. Emit one owner question through the response
format's owner-decision lane; under an active workflow policy, use its decision
memo format. Never require an owner message solely to reset a conversational
turn boundary.

The eventual reception report names every successfully recovered failure and
the focused command or evidence that established recovery. When recovery stops,
report verified, `changed-but-unverified` or `partial`, and `unattempted`
findings by name, plus the failing command or evidence needed for recovery. Do
not classify these failure-state entries as `VALID` or claim they were updated,
handled, completed, or fixed.

## Excluded authority

Automatic reception never authorizes unrelated refactoring, new product scope,
new architecture, staging, commits, other Git operations, or deployment.
