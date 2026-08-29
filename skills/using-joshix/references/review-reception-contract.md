# Review Reception Contract

This contract applies only when an artifact-owning agent receives another
agent's code, plan, or spec review. The roles, not fresh `apply`, `fix`, or
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

Rejected, deferred, unclear, and unverified findings remain unchanged with
evidence-backed reasoning in the shared conversation. Complete all independent
objective work before the first owner question. Do not add orchestration state
or a dispute ledger.

## Failure boundary

Expected pre-application diagnostics and a deliberate TDD-red result may guide
an accepted change. After application begins, the first unexpected edit or
verification failure stops further edits to that artifact for the turn,
preserves its exact current state, and does not attempt same-turn repair or
automatic rollback. Do not rerun the failed verification in the same turn
unless an external condition changes.

Report verified, `changed-but-unverified` or `partial`, and `unattempted`
findings by name, plus the failing command or evidence needed for recovery. Do
not classify these failure-state entries as `VALID` or claim they were updated,
handled, completed, or fixed.

## Excluded authority

Automatic reception never authorizes unrelated refactoring, new product scope,
new architecture, staging, commits, other Git operations, or deployment.
