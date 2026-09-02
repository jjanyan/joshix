# Autonomous Review

Activate this contract only with a valid workflow policy. Policy absent means
the existing joshix review workflow is unchanged.

## Persistent reviewer peer

For policy-active review, OpenAI and Anthropic are the complete authorized
provider set. A Codex coordinator starts Claude; a Claude coordinator starts
Codex. Every current or future model supplied by either provider is authorized
and inherits that machine's normal configuration. Adding another provider or
authorization target requires a joshix code update; repository policy and task
prompts cannot extend the set.

Choose one persistent reviewer session per task and reuse it across plan, spec,
slice, and whole-change gates. The coordinator supplies the exact task folder,
current gate, review target, focused verification, any bounded diff/log scratch
file, and the structured-output contract. The persistent reviewer peer may
read shared task history and the repository as needed; do not reconstruct the
conversation into its prompt.

The coordinator is the only writer to the working tree and shared task state.
The reviewer is read-only: it never initializes a task, appends history,
replaces `current.md`, or edits repository files. Ordinary implementation
workers and policy-absent delegated reviewers keep their existing isolation.

Claude receives `Read`, `Grep`, `Glob`, and only exact task-context helper read
commands. It receives Git evidence through the coordinator-owned bounded
diff/log scratch file, never Git-capable or generic Bash. Codex starts and
resumes with explicit parent `--sandbox read-only --cd <repo-root>` arguments;
the resumed Codex reviewer remains read-only even when personal configuration
selects its model and reasoning effort. Invoke either provider with bounded
turns, wall time, events, raw output, and final review size. Transport uses
argument arrays with `shell: false`.

Install the host launcher once with `install-reviewer-host.mjs`. In steady
state, the coordinator's first cross-provider action is the installed
`joshix-review review` operation; it never invokes the general runner directly.
The launcher accepts only the typed operation and setup-recorded executables.
Do not allow-list Node, a provider CLI, the general runner, or mutable
plugin/cache code. Until setup succeeds, the only bootstrap path is a one-off,
individually reviewed escalation of the general runner with every binary
override removed.

For code-review gates, the coordinator captures only the scoped Git diff/log
needed for the gate using bounded argument-array calls, `--no-ext-diff`,
`--no-textconv`, and no pager. Write those captured bytes to a mode-`0444`
OS-temporary scratch file, pass its absolute path, and remove it after the
bounded provider call. Plan and spec artifacts can be read directly. The
reviewer never receives Git-capable Bash.

Each gate prompt contains only the peer's current job:

```markdown
You are the persistent reviewer peer for this task. Remain read-only.

Task folder: `.joshix/tasks/<exact-task>/`
Read helper: `<absolute-task-context-helper>`
Gate: `<gate>`
Round: `<1|2>`
Review target: `<artifact path or changed-file scope>`
Diff/log evidence: `<none or absolute coordinator-owned scratch-file path>`
Focused verification: `<commands and observed result>`

Read `current.md` and query task history as needed. Inspect the repository and
supplied evidence as needed. Return only JSON matching
`review-result.schema.json`. Never initialize or append task context, edit
repository files, or ask the owner to relay review messages.
```

## Validate, retry, and fall back

Before launch, load the recorded reviewer provider and session from current
review history. Handle the launch result in this order:

1. `sandboxed` or `launcher` means the provider was not attempted. Diagnose and
   repair the local launcher path; do not start fallback or blame the provider.
2. `configuration-stale` is recorded once, then starts a persistent same-role
   fallback and produces one completion notice.
3. An actual terminal provider failure records its bounded diagnostic, then
   starts the persistent same-role fallback.
4. `session-unavailable` replaces that provider session once; it is not
   fallback.
5. A successful fallback provider and session are reused for all later gates.
6. If no automatic reviewer remains, append one canonical transport-failure
   record and emit one capability decision memo.

Validate the result schema, then validate every criticality and surface string
against the active policy and declaration. Invalid membership is `malformed`.
Transport retries do not consume a producer pass.

Retry the requested provider once only for a transient nonzero exit or malformed
review. Do not retry unavailable, unauthorized, timeout, or oversized failures.

If a saved provider session cannot be resumed, start a fresh session with the
same provider and role. It reads SQLite and continues; this is session
replacement, not provider fallback and not an owner decision.

If the other provider is unavailable or unusable after the bounded transport
attempts, start one persistent same-provider reviewer that assumes the same
role for the rest of the task. This is a same-role fallback: for example, if
Anthropic is unavailable to a Codex coordinator, a separate Codex reviewer
replaces Claude. Do not switch on disagreement. Do not probe the unavailable
provider again during the task. If no automatic reviewer can run, emit one
capability decision memo rather than asking the owner to broker individual
rounds.

A pre-spawn argument, path, or schema error is a coordinator configuration
failure. Correct it locally; do not blame, retry, or disable the reviewer path.
An internal runner failure is also local and never disables the reviewer path.

Persist a terminal requested-provider diagnostic only through the bounded
`requestedProviderDiagnostic` field on a successful fallback review record. If
no automatic path succeeds, construct and validate
`review-failure-record.schema.json`, append its single JSON object with speaker
`ReviewerTransport` and the deterministic task/gate/round/path/prompt digest as
the idempotency key, and retain the returned history ID. Never write raw
stdout, stderr, prompts, events, or malformed structured output to history.

A working fallback needs no owner message; note it once in the completion
report. Never turn each round into an owner-brokered message exchange. Every
working automatic path produces zero owner-brokered review messages; a required
review is not a request for the owner to invoke or relay it.

## Record and settle

The runner returns the structured result and session envelope. The coordinator
constructs and validates version 2 of `review-record.schema.json`, including
the provider session ID and `started`, `resumed`, or `replaced` mode. Existing
version 1 history stays readable and unchanged. If the newest usable row is
version 1, start a fresh session on its recorded `usedProvider`; do not invent a
session ID or rewrite the old row.

Provider-reported runtime metadata is diagnostic-only. Copy an available runner
`runtime` object into `reviewer.runtime`; do not ask the reviewer to name its own
model or effort, infer missing effort, or reject a valid review when the
provider emits no runtime metadata. Record model independently; include effort
only when it appears in the provider event.

Compute `promptDigest = sha256(prompt)`,
record it as `sha256:<64hex>`, and compute the append idempotency key as
`sha256(task-identity + "\0" + gate + "\0" + round + "\0" + reviewer-path + "\0" + promptDigest)`.
Append the envelope once with that key and atomically replace the snapshot. The
history content is one JSON object only, with no timestamp, Markdown fence,
heading, or prose; use a temporary content file outside `.joshix/context/` so
human-message conventions cannot alter the record. The compact snapshot field
is:

```markdown
- Review: `<gate>; round <n>; <path>; <provider> session <uuid>; history <id>`
```

Preserve every other required workflow-declaration field. The delegated
producer never records task history.

Price findings through `workflow-policy.md`. Lower findings become visible
deferred observations; higher findings bubble immediately; equal findings enter
one implementer fix or rebuttal. After one rebuttal, the coordinator settles a
`dev` instance choice inside established policy and logs it. A `policy` finding
that establishes, changes, weakens, or violates an expensive-to-reverse rule,
and a `product` finding that changes undecided user-visible behavior, wording,
scope, or what ships, bubbles up. Executing an already authorized decision does
not bubble again.

## Producer and completion-recovery budget

Producer passes, transport attempts, and recovery repairs are separate:

| Event | Producer pass | Recovery repair | Review required |
|---|---:|---:|---|
| Initial implementation submitted | 1 | 0 | Selected gate |
| Fix/rebuttal submitted | 2 | 0 | Same gate, final pass |
| Transport retry/session replacement/fallback | 0 | 0 | Continue current pass |
| Mechanical stale expectation meeting all four conditions | 0 | 1 | No producer review; focused failed-subgate rerun |
| Zero-diagnostic infrastructure retry | 0 | 0 | No producer review; one failed-subgate retry |
| Production/invariant/behavior recovery | 1 remaining pass | 1 | Existing whole-change gate |

Use at most two producer passes per gate. Hitting that cap bubbles with a
decision memo before a third producer pass. A trivial task stops and bubbles before pass two.
The effort alarm can stop the loop earlier. The gate budget
never resets after sign-off. Only focused checks run between passes; full
completion gates run once after sign-off.

A mechanical stale-expectation repair is automatic only when all four
conditions hold: no production code changes, no assertion is weakened, no
invariant or user-visible behavior changes, and coverage is not reduced. Run a
focused check of the repair, then rerun only the failed required subgate. Each
distinct focused-verified repair earns one subgate rerun. The ceiling is two recovery repairs total; a failed, third, or nonqualifying repair stops.

One zero-diagnostic infrastructure retry is allowed only when the failure
occurred before workload start, emitted no product or test diagnostic, the
repository is unchanged since sign-off, and a focused health check proves the
dependency or environment available or the failure conclusively transient.
Retry only the failed subgate. Recurrence, a failed health check, code or test
evidence, or an unknown cause stops; never recurse.

If recovery changes production code, an invariant, or user-visible behavior,
it consumes one recovery repair and one remaining whole-change producer pass.
Before editing, confirm that pass remains. Run focused verification, resume the
same reviewer for the final available pass, and after approval rerun only the
failed required subgate. If no producer pass remains, bubble before editing.
Every stop uses the policy decision memo with question, genuine options, one
recommendation, one context paragraph, and a task-history pointer.
