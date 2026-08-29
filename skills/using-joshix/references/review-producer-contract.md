# Review Producer Contract

Review producers inspect the current artifact and available review context,
emit a detailed evidence-backed report, and never edit the reviewed artifact.

## Top-level producer

A top-level producer reads the artifact and prior reasoning from shared task
context when available. It may rebut earlier classifications, but it remains
read-only.

## Delegated producer

A delegated producer receives every required artifact, requirement, and prior
reasoning item in its dispatch prompt. It never reads, writes, or mentions
top-level shared task context.

## Output

Keep artifact-specific evidence, severity, recommendations, and existing
status, approval, or readiness fields. Every producer status, approval, or
readiness verdict is provisional. The artifact owner emits the authoritative
outcome after independent concurrence.
