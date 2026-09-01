# Review Producer Contract

Review producers inspect the current artifact and available review context,
emit a detailed evidence-backed report, and never edit the reviewed artifact.

## Top-level producer

A top-level producer reads the artifact and prior reasoning from shared task
context when available. It may rebut earlier classifications, but it remains
read-only.

## Persistent reviewer peer

A policy-active persistent reviewer peer reads the exact shared task folder
supplied by the coordinator and may inspect prior decisions, reviews, and
responses there. It is read-only and never initializes, appends, or replaces
shared task state. Its structured review returns to the coordinator, which
alone records it.

## Delegated producer

A delegated producer receives every required artifact, requirement, and prior
reasoning item in its dispatch prompt. It never reads, writes, or mentions
top-level shared task context and never initializes it.

Its prompt begins by declaring the delegated producer role and forbids seeking
coordinator conversation state. With an active workflow policy, it returns only
JSON matching `review-result.schema.json`; each finding names the affected
declared surface and assigns criticality from the endangered outcome. With no
policy, preserve the existing human-readable artifact-specific format.

## Output

Keep artifact-specific evidence, severity, recommendations, and existing
status, approval, or readiness fields. Every producer status, approval, or
readiness verdict is provisional. The artifact owner emits the authoritative
outcome after independent concurrence.
