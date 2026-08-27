# Progress DAG

This is the canonical progress-visualization policy for joshix planning and
development workflows.

## Trigger

Emit a Mermaid progress DAG when the top-level workflow has an active tracked
task list with at least three tracked nodes. The tracked list is the trigger;
do not estimate whether work feels “substantial.” Ordinary questions and one-
or two-node work do not get a DAG.

## Ownership

The top-level coordinator emits the DAG for Josh. Dispatched workers never
emit, update, or persist it. Worker findings change the coordinator's tracked
state; the coordinator presents the next user-facing graph.

## Emission times

Emit the graph:

- When qualifying planning or execution begins.
- When tracked node state changes.
- When a blocker changes dependencies or the viable path.
- At completion.

Do not re-emit an unchanged graph merely because another commentary message
is due.

## Stable topology and state

- Keep node IDs and labels stable between updates.
- Show actual dependencies and available parallelism instead of forcing a line.
- Condense large plans into meaningful phase nodes when the full task list is
  hard to read.
- Completed nodes use `done`; in-flight nodes use `active`.
- Do not assign a class to todo nodes, so they retain Mermaid's regular/default
  styling.
- Define the state classes in every emitted graph:

```mermaid
flowchart LR
  T1["Define behavior"] --> T2["Implement helper"]
  T2 --> T3["Verify handoff"]
  classDef done fill:#173b2c,stroke:#34d399,color:#dcfce7,stroke-width:2px
  classDef active fill:#183b5f,stroke:#60a5fa,color:#dbeafe,stroke-width:3px
  class T1 done
  class T2 active
```

At completion, all completed nodes receive `done` and no node remains `active`.

## Shared-context boundary

The DAG is a user-facing conversation update. If shared task context is active,
the visible response containing it is recorded like any other outward-facing
message. Do not write the DAG as shared task state, do not add a separate
diagram file, and do not use an old DAG instead of the active plan and
`current.md`.

## Source-only output

For every qualifying DAG update, keep the Mermaid source fence in the response.
The Mermaid source fence is the user-facing artifact. A client may render it
natively, but the agent does not create, inspect, attach, or persist a fallback
image.

Failure to display Mermaid visually is not a workflow failure. Keep the source
available and continue the workflow. If the source graph is too large to read,
condense it into meaningful phase nodes or change its layout direction.
