---
name: requesting-code-review
description: Use when completing tasks, implementing major features, or reviewing substantial changes before proceeding
---

# Requesting Code Review

Request a focused code review to catch concrete issues before they cascade.
Provide the reviewer with relevant implementation context, requirements,
changed files, diff context, and prior reasoning. With no active workflow
policy, dispatch every reviewer in an isolated context with every required
artifact, requirement, and prior reasoning item embedded in the dispatch
prompt. Never use inherited or forked conversation history for that
policy-absent review context.

**Core principle:** Review concrete risks before proceeding.

## Active workflow policy

When repository guidance declares `joshix-workflow-policy:`, read
`../using-joshix/references/workflow-policy.md` and
`../using-joshix/references/autonomous-review.md` before dispatch. That central
protocol replaces the manual dispatch and unbounded feedback rules below. With
no policy, keep this skill's existing behavior unchanged.

| Task reviewer state | Action |
|---|---|
| Saved reviewer session exists | Resume it for the next selected gate or pass. |
| No reviewer session exists | Start the other provider and record its returned session ID. |
| Saved session cannot resume | Replace it on the same provider; continue from shared history. |
| Other provider is unavailable | Start one persistent same-model reviewer in the same role. |
| No automatic reviewer path exists | Emit one capability decision memo. |

Never ask the owner to copy a prompt, paste a result, or relay review messages
unless the owner selects that fallback from the capability memo.

Invoke the installed `joshix-review review` typed operation as the first
cross-provider action. Do not call the general runner directly in steady state.
If the launcher reports `sandboxed` or `launcher`, diagnose the local transport
without claiming the provider was attempted or starting fallback. Record
`configuration-stale` once and use a persistent same-role fallback. An actual
terminal provider failure also falls back after its bounded diagnostic is
recorded. Until host setup succeeds, only a one-off individually reviewed
runner escalation with binary overrides removed may bootstrap review.

The coordinator validates the review, constructs
version-2 `review-record.schema.json`, computes the digest and append key exactly
as defined by the central protocol, and appends the canonical envelope through
task-context `--idempotency-key`. Keep version 1 history unchanged and readable;
a version-1 latest row starts a fresh session on its recorded provider. Retain
the returned history ID whether new or duplicate, then atomically replace the
snapshot with gate, round, path, provider, session ID, and history ID in its
compact `Review:` field while preserving scope, active time, deferred history
IDs, and every other declaration field. If replacement fails, preserve history,
report and rebuild the stale snapshot, and do not dispatch again until repaired.
The invoked reviewer never writes coordinator state.

If no automatic path succeeds, validate one
`review-failure-record.schema.json` object and append it as
`ReviewerTransport` with the same deterministic identity before emitting the
single capability memo. A successful fallback may carry only the bounded
`requestedProviderDiagnostic`; never append raw transport output.

Before each later gate or pass, consult the snapshot and authoritative review
history for the saved provider and session. A recorded provider fallback stays
in the same reviewer role for the rest of the task; do not probe the unavailable
provider again.

Build active-policy prompts from the compact payload in the central contract;
the peer reads prior reasoning from the supplied task instead of receiving a
reconstructed transcript. For Claude code review, capture a bounded scoped
diff/log into the mode-`0444` OS-temporary scratch file defined there. Remove it
after the call and never grant the reviewer Git-capable Bash.

## Model Selection

Personal provider configuration supplies reviewer model and reasoning-effort defaults.
Do not suppress those defaults or downgrade models to conserve cost. Let native
reviewers inherit the current platform selection and cross-provider CLIs load
their normal machine-specific configuration. Override either value only when
the user explicitly requests a task-specific selection.

Provider-reported runtime metadata is diagnostic-only. When the runner returns
`runtime`, copy it unchanged into `reviewer.runtime` in the version-2 history
record. The model is required when that object exists; effort is included only
when the provider event exposes it. Never ask the reviewer to self-report its
model or effort, and never fail an otherwise valid review because runtime
metadata or effort is absent.

## When to Request Review

With an active workflow policy, tier-defined review rigor is authoritative.
Use only the review gates required by the task-level tier; do not carry the
policy-absent mandatory per-task or per-lane gates into the active branch.

**Policy absent — mandatory:**

- After each task in subagent-driven development
- After completing a major feature or risky change
- Before reporting substantial work complete when correctness,
  maintainability, security, data, or operational risk matters

**Policy absent — optional but valuable:**
- When stuck (fresh perspective)
- Before refactoring (baseline check)
- After fixing complex bug

If the latest user message contains an honest question that needs an answer,
answer it before requesting review.

## How to Request

**1. Gather review inputs:**

- `{DESCRIPTION}` - Brief summary of what changed
- `{PLAN_OR_REQUIREMENTS}` - What it should do
- `{PRIOR_REASONING}` - Prior rationale, classifications, or decisions needed
  for review
- `{CHANGED_FILES}` - Files changed by this task or checkpoint
- `{DIFF_CONTEXT}` - Relevant working tree diff, changed-file diff, or code
  snippets to review
- `{VERIFICATION}` - Commands/tests run and results, if available

**2. Dispatch a code reviewer:**

Use the platform's subagent, review, or task tool with the template at
`../code-review/code-reviewer.md`.

**3. Act on feedback:**
- Fix Critical issues immediately
- Fix Important issues before proceeding or reporting completion, unless there
  is a clear technical reason to push back
- Consider Minor issues, but do not let taste-only feedback churn the work
- Push back if reviewer is wrong (with reasoning)

Under an active policy, the implementer fixes or rebuts once. Before a second
producer pass, settle `dev` disagreements locally and bubble `policy` or
`product` disagreements. Never request pass two for a trivial task or pass
three for any task; emit the central decision memo instead.

## Example

```
[Just completed Task 2: Add verification function]

You: Let me request code review before proceeding.

[Dispatch code reviewer subagent]
  DESCRIPTION: Added verifyIndex() and repairIndex() with 4 issue types
  PLAN_OR_REQUIREMENTS: Task 2 from .joshix/plans/deployment-plan.md
  PRIOR_REASONING: Task 1 review established the current indexing and repair assumptions
  CHANGED_FILES: src/index.ts, tests/index.test.ts
  DIFF_CONTEXT: Current working tree diff for the changed files
  VERIFICATION: npm test tests/index.test.ts - passing

[Subagent returns]:
  Findings:
    Important: Missing progress indicators
    Minor: Magic number (100) for reporting interval
  Assessment: Ready to proceed

You: [Fix progress indicators]
[Continue to Task 3]
```

## Integration with Workflows

The bullets below describe the policy-absent workflow. Under an active policy,
use the selected tier's gate count and placement instead.

**Subagent-Driven Development:**
- Review after EACH task
- Catch issues before they compound
- Fix before moving to next task

**Executing Plans:**
- Review after each task or at natural checkpoints
- Get feedback, apply, continue

**Ad-Hoc Development:**
- Review before reporting large or risky work complete
- Review when stuck

## Red Flags

**Never:**
- Under policy absence, skip review because "it's simple"
- Ignore Critical issues
- Proceed with unfixed Important issues
- Argue with valid technical feedback
- Ask for review before answering an honest user question
- Give the reviewer stale or irrelevant diff context
- Ask the reviewer to judge the whole repo when a changed-file scope is enough

**If reviewer wrong:**
- Push back with technical reasoning
- Show code/tests that prove it works
- Request clarification

See template at: skills/code-review/code-reviewer.md
