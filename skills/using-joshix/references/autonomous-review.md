# Autonomous Review

Use this contract whenever a Codex or Claude Code coordinator requests an
independent spec, plan, or code review, including lane and whole-change reviews.
No workflow-policy declaration is required. The workflow and repository rules
still decide when review is required; this contract decides who reviews and
how. It does not add spec, plan, or review gates to a task.

This is coordinator routing. A reviewer already assigned to produce a review
performs that review read-only; it never delegates it back to the other provider.
Other hosts retain their native isolated-review workflow. An explicit owner
instruction may override provider selection; policy absence is not an override.

## Thin review loop

OpenAI and Anthropic are the complete authorized provider set. A Codex
coordinator starts Claude; a Claude coordinator starts Codex. Every review call
uses one fresh reviewer process. SQLite task history provides continuity; no
provider process state is saved or reused.

Claude Code selects `--provider codex`; Codex selects `--provider claude`.
Never substitute a same-provider subagent when the bridge, other CLI,
authentication, or required permissions are unavailable. Report the concrete
blocker and leave the required review unapproved.

Before dispatch, reuse a recorded approval for the same review scope and
material state rather than requesting an equivalent review under another label.
A lane-only approval does not cover a whole-change gate. For a broader review,
record the completed scope and its verification evidence in shared history;
the broader scope's evidence, not a new label, justifies a fresh review.

The active algorithm is:

1. Select the opposite provider and make one provider attempt through the
   installed `joshix-review review` operation.
2. Give the reviewer the exact task identity, repository root, installed
   task-read and Git-read command forms, response schema, and the canonical
   instruction below.
3. Let the reviewer discover the current spec, plan, implementation, and Git
   scope from SQLite and the repository.
4. On success, consume the ordinary SQLite message appended by the bridge and
   independently verify every finding.
5. Apply only requirement-determined corrections already authorized by the
   owner and within the requested scope.
6. Invoke another fresh reviewer only after the artifact materially changes or
   new evidence appears.
7. Stop on an owner decision, when the reviewer repeats a rebutted disagreement
   without new evidence, when the same concrete defect is materially unchanged,
   or when no objective correction remains.
8. On transport failure or cancellation, report the result and stop, except
   for the narrow bundled-authentication recovery below.

The reviewer supplies evidence and a recommendation. The coordinator verifies
the evidence and classifies scope, policy, product, and architecture impact.
Severity never grants edit authority. A new review is useful only after the
artifact changes or new evidence appears.

## Exact instruction and mechanical context

The reviewer receives this exact substantive instruction once:

> Challenge assumptions in the spec, plan, and implementation when they create concrete risk. Read the shared chat and repository guidance. Establish the latest applicable owner decisions, accepted limitations, and superseded choices before reviewing the current artifact. Evaluate within that scope; prior approval is not proof of correctness, but a knowingly accepted limitation is not an overlooked defect. Before reopening a settled issue, identify the prior decision and new evidence that its resolution was incorrect, invalidated by later changes, or left a defect outside the accepted limitation. Repeating an accepted risk or preferring another design is insufficient. Initial spec and plan reviews cover the artifact. Follow-ups examine corrections and their consequences, including interactions with unchanged parts; do not restart broad review because wording was clarified or relitigate unrelated settled issues without new evidence. Review code for concrete correctness risks, regressions, and missing requirements throughout the task's scope, including outside the latest correction. Read the existing history as needed; no mandatory decision recap or new decision artifact is required.

Do not rewrite, reorder, prefix, or append substantive review criteria. The
surrounding mechanical prompt may identify the exact repository root, exact
task folder, installed read commands, and response schema. It must not select
an artifact class, review lens, expected conclusion, or priority.

## Read-only provider boundary

Run `joshix-review review` as the only command in its shell call. NEVER combine
it with file preparation, logging, heredocs, command chains, pipelines, or
another command. Prepare files in separate calls. In the configured Codex
installation, the saved narrow allow rule permits the standalone launcher to
run outside the sandbox automatically. The wrapper itself does not elevate.
Default tool permissions alone do not establish whether execution stayed
sandboxed.

The provider process may read repository files and the exact task but may not
edit repository or task state. The installed bridge exposes only:

- task reads: `recent`, `since-id`, `since-time`, `search`, `get`, and `check`
  for the exact supplied task;
- Git reads: `status`, `diff`, `diff --cached`, path-filtered diff after a
  literal `--`, one-revision diff, `log`, and `show REVISION` with optional
  paths after a literal `--`.

The bridge rejects unknown options, leading-hyphen revisions, absolute paths,
path traversal, and newline or NUL input. It invokes the installer-resolved Git
executable with literal argument arrays, `shell: false`, no pager or color,
`--no-ext-diff` and `--no-textconv` where applicable, disabled fsmonitor,
disabled hooks, and no external diff. It removes inherited `GIT_*` variables
before setting read-only Git configuration and `GIT_OPTIONAL_LOCKS=0`.

Claude runs fresh in restricted print mode with `Read`, `Grep`, `Glob`, and
`Bash`, but each Bash permission includes the exact repository/task path and an
allowed task-read or Git-read command token. It uses noninteractive deny-on-miss permissions and cannot
invoke write, edit, notebook, task, or agent tools. Codex runs fresh and
ephemeral with `exec --ignore-user-config --ephemeral --ignore-rules --sandbox
read-only --cd <repo-root>`, JSON events, the response schema, and a temporary
final-message file. Ignoring user configuration prevents unrelated plugins and
MCP servers from expanding or breaking the review surface; authentication is
still provided by Codex. Both providers receive the same sanitized environment.

## Result and history

The provider returns only `review-result.schema.json`: root keys `status` and
`findings`; every finding has `title`, `severity`, `evidence`, and
`recommendation`. `approved` requires an empty findings array; `issues`
requires at least one finding. Severity is the reviewer's nonempty label, not a
workflow command.

After the provider exits, the bridge validates the completed compact JSON. A
valid result over 512 KiB is `oversized-result`; ordinary progress output is
discarded as it arrives and never terminates a provider. Retain rolling tails
from terminal stdout errors and stderr; the combined labeled failure message
is bounded to 16 KiB. Plain stdout is only a fallback on nonzero exit.
Provider-declared terminal errors remain failures even with exit code zero.
Successful review text and ordinary events are not authentication diagnostics.
Diagnostics and ordinary events are never appended to history.

On success, the bridge appends `JSON.stringify(review)` using only `speaker`
and `content`. The speaker is `Claude Reviewer` or `Codex Reviewer`. This is an
ordinary SQLite message, not an envelope or transport ledger. The bridge
returns `{ok: true, historyId, review}`. A valid review that cannot be appended
returns `history-append` and includes the review so the coordinator can report
the exact result without pretending it entered history.

## Terminal results

There is no internal retry or alternate provider. Direct, unversioned failure
kinds are `invalid-request`, `unavailable`, `authentication`, `provider-exit`,
`missing-result`, `malformed-result`, `oversized-result`, `history-read`,
`history-append`, and `internal`. Every spawn error is handled before exit-code
classification; missing or non-executable provider commands are `unavailable`.

An `authentication` result includes the original diagnostic and fixed recovery
guidance. The coordinator checks its original shell call: if the launcher was
bundled, retry once as a standalone command. If it was already standalone, or
the standalone retry fails, stop and report the error to the user; the account
may actually be logged out. This is the only coordinator retry exception. The
bridge cannot infer the parent call shape and never retries or changes
credentials. A generic exit code 1 is not proof of authentication failure.

Cancellation is separate from ordinary failure. `SIGINT` or `SIGTERM` is
forwarded to the provider process group, with forced cleanup only after the
explicit signal grace period. Cancellation appends nothing and starts no retry
or fallback. The bridge prints exactly one JSON line. Success exits 0, ordinary
failure exits 1, and cancellation exits 130 or 143.

## Installation boundary

`install-reviewer-host.mjs` installs one owner-only
`bin/joshix-review` executable containing the exact resolved Node, Claude,
Codex, and Git paths. It installs no mutable runner, schema copy, helper copy,
manifest, digest, authentication probe, write-capability proof, provider help
probe, or compatibility shim. During upgrade it removes only the known obsolete
`config.json` and `lib/` paths after the new executable is safely written.

## Convergence and completion

Use `review-reception-contract.md` for finding authority. A material correction
or new evidence makes work eligible for a fresh review call; unchanged work
without new evidence does not. A provider
failure does not authorize a relaunch except for the bundled-authentication
case above. Completion verification follows the
repository's declared gates and normal focused diagnosis; review transport does
not create numeric work budgets or additional
proof rituals.

A clarification alone does not restart broad spec or plan review. When a
required follow-up remains, verify the outstanding findings and the correction's
affected interactions. A rejection is not provider approval; unresolved required
boundaries remain subject to the existing approval and semantic stop rules.
