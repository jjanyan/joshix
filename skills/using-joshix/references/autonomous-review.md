# Autonomous Review

Activate this contract only with a valid workflow policy. Policy absent means
the existing joshix review workflow is unchanged.

## Thin review loop

OpenAI and Anthropic are the complete authorized provider set. A Codex
coordinator starts Claude; a Claude coordinator starts Codex. Every review call
uses one fresh reviewer process. SQLite task history provides continuity; no
provider process state is saved or reused.

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
8. On transport failure or cancellation, report the result and stop.

The reviewer supplies evidence and a recommendation. The coordinator verifies
the evidence and classifies scope, policy, product, and architecture impact.
Severity never grants edit authority. A new review is useful only after the
artifact changes or new evidence appears.

## Exact instruction and mechanical context

The reviewer receives this exact substantive instruction once:

> Challenge assumptions in the spec, plan, and implementation when they create concrete risk; do not treat prior approval as proof of correctness. Read the shared chat and review

Do not rewrite, reorder, prefix, or append substantive review criteria. The
surrounding mechanical prompt may identify the exact repository root, exact
task folder, installed read commands, and response schema. It must not select
an artifact class, review lens, expected conclusion, or priority.

## Read-only provider boundary

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
discarded as it arrives and never terminates a provider. Stderr retains only a
rolling 16 KiB diagnostic tail for a terminal failure message. Diagnostics and
ordinary events are never appended to history.

On success, the bridge appends `JSON.stringify(review)` using only `speaker`
and `content`. The speaker is `Claude Reviewer` or `Codex Reviewer`. This is an
ordinary SQLite message, not an envelope or transport ledger. The bridge
returns `{ok: true, historyId, review}`. A valid review that cannot be appended
returns `history-append` and includes the review so the coordinator can report
the exact result without pretending it entered history.

## Terminal results

There is no automatic retry or alternate provider. Direct, unversioned failure
kinds are `invalid-request`, `unavailable`, `authentication`, `provider-exit`,
`missing-result`, `malformed-result`, `oversized-result`, `history-read`,
`history-append`, and `internal`. Every spawn error is handled before exit-code
classification; missing or non-executable provider commands are `unavailable`.

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

Use `review-reception-contract.md` for finding authority. A changed artifact is
eligible for a new explicit review call; unchanged work is not. A provider
failure does not authorize a relaunch. Completion verification follows the
repository's declared gates and normal focused diagnosis; review transport does
not create numeric work budgets, special recovery allowances, or additional
proof rituals.
