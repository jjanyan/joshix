# Review Reception Contract

This contract applies only when an artifact-owning agent receives another
agent's review of concrete code or diff, a named plan, or a named spec. It is
inapplicable to task history, `current.md`, product discussion, proposed
architecture, and general chat. The roles, not fresh `apply`, `fix`, or
`proceed` wording, determine default edit authority.

Agent 2 is a read-only review producer. Agent 1 is the meta-review receiver and
artifact owner. Agent 1 independently verifies every finding before classifying
or editing. Automatic authority covers only verified, concrete defects or
violated requirements raised by Agent 2. New product, scope, ownership,
acceptance-criteria, or architecture choices remain owner-gated.

An automatic correction is allowed only when every condition holds:

1. The finding identifies a concrete defect or violated requirement.
2. It has reproducible or directly inspectable evidence.
3. The correction is determined by existing requirements or repository policy.
4. It stays inside the owner's already-authorized outcome and artifact scope.
5. It introduces no product choice, acceptance-criteria change, architecture
   choice, dependency, schema expansion, subsystem boundary, generalized
   hardening, unrelated refactor, or future-feature infrastructure.

Severity never creates edit authority. Recommendations, advisories,
preferences, speculative hardening, and while-we-are-here improvements remain
unchanged unless Josh explicitly authorizes them.

Read the latest applicable owner decisions and accepted limitations in existing
history and repository guidance before classifying a finding. Do not require a
separate decision recap. A reversal must identify the prior resolution and new
evidence showing an error, later invalidation, or a defect outside accepted
limitations. Repeating an accepted risk or preferring a different design does
not reopen a settled decision.

Before resubmitting, verify the correction across affected callers, sibling
paths, tests, and repeated requirements, including unchanged interactions.
Check that the main user outcome still holds. For runtime-dependent claims,
inspect the actual artifact or run a bounded reproduction before revising more
prose. Preserve concrete evidence for the reviewer; do not expand product or
architecture scope to satisfy a speculative preference.

For spec/plan follow-ups, a clarification alone does not restart broad design review.
Code-review breadth remains unchanged. A rejected finding alone does not create
provider approval: any required follow-up resolves the outstanding disagreement
or verifies the fix within this focused scope.

The reviewer supplies evidence and a recommendation. The coordinator verifies
the evidence and classifies scope, policy, product, and architecture impact.
Severity never grants edit authority. A new review is useful only after the
artifact changes or new evidence appears.

## Decision table

| Situation | Required action | Result |
|---|---|---|
| Semantic explicit no-edit instruction | Evaluate every finding and leave the artifact unchanged. | Use the artifact-specific review-only opening. Any accepted objective finding left unapplied requires rereview. |
| Question merely solicits meta-review | A question that merely solicits meta-review does not pause automatic mode. | Continue with the rows below. |
| Substantive question about whether work should occur | A semantic explicit no-edit instruction or a substantive question about whether work should occur does pause edits. | Answer before editing. |
| Agent 2 finding satisfies every automatic-correction condition | Apply every independently verified finding that satisfies all automatic-correction conditions. Verify the resulting artifact. | Report automatic or requested application; a materially changed artifact may be rereviewed fresh. |
| Agent 2 finding is wrong, stale, duplicated, or contradicted | Leave it unchanged and explain the repository evidence. | `REJECT`; Agent 2 must accept or rebut it. |
| Agent 2 finding is a reasonable non-blocking preference outside approved scope | Leave it unchanged and explain the scope boundary. | `DEFER`; Agent 2 must accept or rebut it. |
| Agent 2 finding lacks evidence | Leave it unchanged and name the missing source or fact. | Evidence-needed lane; Agent 2 supplies evidence, clarifies, accepts, or rebuts. |
| Agent 2 finding asks for a new product, scope, ownership, acceptance-criteria, or architecture choice | Finish independent objective work, leave the gated item unchanged, then ask exactly one owner question. | Owner-decision lane; do not silently choose with `REJECT` or `DEFER`. |
| Josh answers an owner question | After Josh answers an owner question, apply the answer and newly unblocked work without another permission request. When prior shared reasoning or the review supplies exact replacement text, preserve it verbatim rather than restyling or elaborating it. | Report the applied continuation as requested; materially changed work may be rereviewed fresh. |
| Agent 1 discovers a concern Agent 2 did not raise | Independently verify it and apply the same authority rules used for reviewer findings. | Correct objective in-scope defects; leave owner-gated choices unchanged. |
| Later Agent 2 review says a previous automatic change was wrong | Require the prior resolution and new evidence; independently verify the demonstrated error or later invalidation before applying an objective correction. The prior application does not create a new owner gate. | Materially changed work may be rereviewed fresh; unsupported reversals do not reopen settled work. |
| Current Agent 2 review approves and Agent 1 concurs | Make no change. | Approved. |
| The current review approves a spec and genuine owner decisions are satisfied | Continue into writing-plans automatically, unless the user explicitly requested spec-only, review-only, or a stop. | No separate planning command or routine written-spec signoff. |
| The current review approves a plan and execution lacks explicit authorization | Treat artifact-local readiness as settled state, not an unresolved choice. | Emit the exact execution readiness hold from the response format; never manufacture owner options or borrow readiness from queued work. |

## Bridge structured findings

The structured result contains evidence, not workflow governance. After
independent verification, the coordinator compares each concrete risk with the
owner's requirements and, when present, the active declaration and policy.
Requirement-determined corrections inside the
authorized outcome proceed. New product, scope, policy, ownership, acceptance,
or architecture decisions remain owner-gated. An approved spec continues to
planning automatically within the user's requested scope. An approved plan
whose execution remains unauthorized uses the readiness hold, never the
owner-decision lane. Other approval reports do not inherit a hold from
queued work.

Rereview with a fresh provider process only after the artifact materially
changes or new evidence appears. Stop when a review repeats a rebutted
disagreement without new evidence, when the same concrete defect is materially
unchanged, when an owner decision is required, or when no objective correction
exists.

Rejected, deferred, unclear, and unverified findings remain unchanged with
evidence-backed reasoning in the shared conversation. Complete all independent
objective work before the first owner question. Do not add orchestration state
or a dispute ledger.

## Failure recovery

Expected pre-application diagnostics and a deliberate TDD-red result may guide
an accepted change.

After application begins, an unexpected edit or verification failure pauses
further writes to the affected artifact while Agent 1 diagnoses the failure
read-only. Preserve the artifact's exact current state and never automatically
roll back a partial change. A verification failure is evidence, not by itself a
reason to end the turn.

Agent 1 continues automatically without an owner message when diagnosis
establishes the artifact's current state and identifies an objective, in-scope
correction that needs no new product, policy, architecture, scope, destructive,
or irreversible decision. Apply the correction and run focused verification.
If it passes, resume ordinary review reception. Do not rerun a passing focused
verification solely to confirm it.

Stop before further writes when the current state is uncertain, diagnosis
cannot identify an objective correction, the correction would overwrite user
changes, or further work requires excluded authority or scope expansion. Emit
one owner question through the response format's owner-decision lane using
`owner-question-format.md`. Never require an owner
message solely to reset a conversational turn boundary.

The eventual reception report names every successfully recovered failure and
the focused command or evidence that established recovery. When recovery stops,
report verified, `changed-but-unverified` or `partial`, and `unattempted`
findings by name, plus the failing command or evidence needed for recovery. Do
not classify these failure-state entries as `VALID` or claim they were updated,
handled, completed, or fixed.

## Excluded authority

Automatic reception never authorizes unrelated refactoring, new product scope,
new architecture, staging, commits, other Git operations, or deployment.
