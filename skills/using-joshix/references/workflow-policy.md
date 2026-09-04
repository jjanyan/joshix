# Workflow Policy

Use this contract only when loaded repository guidance declares a workflow
policy. It makes process cost proportional without weakening repository rules.

## Discovery

The active root guidance loaded by the host, or one required-guidance runbook
it explicitly references, may contain one standalone directive outside fenced
code, blockquotes, and examples:

```text
joshix-workflow-policy: <repo-relative-path>
```

Resolve the path from the Git root. Do not search conventional filenames,
nested instructions, or a second reference hop. Symlinked guidance works
because the loaded content is authoritative, not its filename.

| Loaded guidance state | Action |
|---|---|
| No eligible directive | Policy absent: use the existing joshix workflow unchanged. |
| One valid directive and complete policy | Activate this contract for the task. |
| Invalid, duplicate, dangling, or incomplete directive | Stop policy activation and emit one capability decision memo. Never partially activate or guess. |

The policy must define:

- tiers in explicit highest-to-lowest order;
- how materially changed surfaces map to tiers;
- how endangered outcomes and invariants map to finding tiers;
- test depth and review rigor for every tier;
- required completion checks; and
- unconditional repository safety and authorization rules.

The detailed review protocol lives in `autonomous-review.md`. Repository policy
does not authorize providers or models.

## Task declaration

When repository changes are anticipated, record this after shared task context
exists and before planning or the first edit:

- every materially changed surface, its repository tier, the changed effect,
  and a one-line justification;
- one task complexity (`trivial`, `routine`, or `complex`) and justification;
- the requested outcome and authorized scope.

Read-only investigation needs no declaration. If changes become likely during
investigation, declare before editing. Reading a surface for display does not
change what it computes, stores, authorizes, or guarantees and does not make it
materially changed.

Criticality and complexity are independent. Criticality controls verification
and review rigor. Complexity alone controls planning ceremony. Neither axis is
derived from predicted or elapsed duration.

The highest-criticality changed surface sets task-level review rigor. Test
depth and finding comparisons stay surface-specific.

A bare tier or complexity replaces the currently discussed value. An explicit
assignment such as `complexity: trivial` does the same. Ordinary sentences
containing a value do not override it. If the field is ambiguous, keep the
current declaration and ask one clarification. Echo accepted overrides at the
next state transition.

## Planning ceremony

| Complexity | Required ceremony |
|---|---|
| `trivial` | No brainstorm, spec, or plan. |
| `routine` | Exactly one short design note or implementation plan, whichever resolves the real uncertainty. |
| `complex` | Existing brainstorm, spec, detailed plan, and decomposition into implementation slices. Review of documents and slices remains tier-controlled. |

Criticality never adds planning documents. Complexity never changes test depth.
Policy absence preserves the existing unconditional workflow.

## Verification and scope

Apply each surface's policy-defined test depth. Manual execution and inspection
are additive; they never substitute for required automated coverage or the
repository's completion checks.

Slices use focused checks. Run full completion gates once, after review
sign-off, at the end. If a final gate fails, diagnose with focused checks,
correct objective in-scope defects, and rerun the relevant required check.

Before implementing work beyond the requested outcome and authorized scope—new
subsystems, invariants, dependencies, generalized hardening, or future-feature
infrastructure—record a blocked transition and bubble up. Do not implement the
expansion first.

Report progress only on `started`, `done`, `blocked`, or `bubble-up` state
transitions. Never repost an unchanged graph on a timer.

## Finding pricing

The reviewer supplies evidence and a recommendation. The coordinator verifies
the evidence and classifies scope, policy, product, and architecture impact.
Severity and criticality are separate. The coordinator maps a verified finding
to the repository tier of the outcome or invariant it endangers, independently
of the surface hosting the defect.

| Finding comparison | Action |
|---|---|
| Lower than its affected changed surface | Leave it unchanged unless the owner authorizes that additional scope. |
| Equal to its affected changed surface | Apply the evidence-bounded correction rule or rebut within authorized scope. |
| Higher than its affected changed surface | Stop and bubble up immediately. |
| `task-wide` | Compare with the task-level tier. |
| Unchanged surface | Compare with the task-level tier; bubble if higher, otherwise leave it outside the current scope. |

A new review is useful only after the artifact materially changes or new
evidence appears. The coordinator stops on an owner decision, repeated
disagreement without new evidence, an unchanged concrete defect, or the absence
of an objective authorized correction. See `autonomous-review.md` for the thin
review transport.

## Bubble-up line

- `dev`: an instance choice inside established policy; the coordinator decides
  and records evidence.
- `policy`: establishes, changes, weakens, or violates a rule, introduces a new
  dependency/subsystem/schema/security model, or is expensive to reverse;
  bubble up.
- `product`: changes undecided user-visible behavior, wording, scope, or what
  ships; bubble up.

Executing an already authorized decision never bubbles again.

Use one decision memo, not a transcript:

```markdown
### Your decision needed

**Short decision name**

Question: One concrete question.

Context: One paragraph explaining why work stopped.

History: `.joshix/tasks/<task>/` messages <ids>.

- **A. Recommended option — recommended**
  - Pros: ...
  - Cons: ...
- **B. Other genuine option**
  - Pros: ...
  - Cons: ...
```

Do not emit this lane for a settled phase merely waiting for an explicit next
command.
