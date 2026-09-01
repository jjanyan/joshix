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

Use at most two producer passes per gate. Hitting that cap produces a decision
memo. A trivial task stops and bubbles before pass two. The effort alarm can
stop the loop earlier. Only focused checks run between passes; full completion
gates run once after sign-off.
