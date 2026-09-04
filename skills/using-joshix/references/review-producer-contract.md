# Review Producer Contract

Review producers inspect the current artifact and available review context,
emit a detailed evidence-backed report, and never edit the reviewed artifact.

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
