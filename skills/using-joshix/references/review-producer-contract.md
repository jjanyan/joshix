# Review Producer Contract

Review producers inspect the current artifact and available review context,
emit a detailed evidence-backed report, and never edit the reviewed artifact.

## Settled scope and follow-ups

Establish the latest applicable owner decisions and accepted limitations from
the supplied history/reasoning and repository guidance, including what
superseded earlier discussion. No mandatory recap or new decision artifact is
required. Review within that scope. Prior approval does not prove correctness,
but a limitation knowingly accepted by the owner is not an overlooked defect.

Before reopening a settled issue, identify the decision and new evidence that
its resolution was wrong, invalidated by later changes, or left a defect outside
the accepted limitation. A repeated risk or different preference is insufficient.

Initial spec/plan reviews cover the artifact. Follow-ups inspect corrections
and their consequences, including interactions with unchanged parts. Fixing X
with Y can reveal a fair Y+Z concern; unrelated settled M requires new evidence.
Clarifying wording does not restart broad design review. Code-review breadth
stays unchanged: newly demonstrated in-scope bugs remain reportable even outside
the latest correction.

## Top-level producer

A top-level producer reads the artifact and prior reasoning from shared task
context when available. It may rebut earlier classifications, but it remains
read-only.

## Reviewer peer

A policy-active reviewer peer is a fresh process that reads the exact shared
task folder supplied by the coordinator and may inspect prior decisions,
reviews, and responses there. It is read-only and never initializes, appends,
or replaces shared task state. The installed bridge validates its structured
review and appends that review as an ordinary task-history message.

## Delegated producer

A delegated producer receives every required artifact, requirement, and prior
reasoning item in its dispatch prompt. It never reads, writes, or mentions
top-level shared task context and never initializes it.

Its prompt begins by declaring the delegated producer role and forbids seeking
coordinator conversation state. With an active workflow policy, it returns only
JSON matching `review-result.schema.json`. Give each finding a short title, a
nonempty severity label, concrete evidence, and a specific recommendation. Do
not classify workflow criticality, declared surfaces, decision ownership, pass
count, or transport state; the coordinator owns those decisions. With no
policy, preserve the existing human-readable artifact-specific format.

## Output

Keep artifact-specific evidence, severity, recommendations, and existing
status, approval, or readiness fields. Every producer status, approval, or
readiness verdict is provisional. The artifact owner emits the authoritative
outcome after independent concurrence.

The reviewer supplies evidence and a recommendation. The coordinator verifies
the evidence and classifies scope, policy, product, and architecture impact.
Severity never grants edit authority. A new review is useful only after the
artifact changes or new evidence appears.
