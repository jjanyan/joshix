# joshix

joshix is Josh's local agentic skills framework for coding agents. It keeps the workflow pieces that are useful here: brainstorming, planning, TDD, systematic debugging, subagent-driven execution, review handling, and verification before completion.

This fork is not intended as an upstream contribution target. It is customized for local agent behavior and local installation.

## Installation

### Policy-active autonomous review host

Install the narrowly privileged reviewer launcher once from this checkout:

```bash
node skills/requesting-code-review/scripts/install-reviewer-host.mjs
```

The default installation is
`$XDG_DATA_HOME/joshix/reviewer-host` when `XDG_DATA_HOME` is absolute, or
`~/.local/share/joshix/reviewer-host` otherwise. Use
`--install-dir <absolute-path>` to choose another non-Git, non-plugin-cache
location. Setup resolves and records the real Node, Claude, and Codex
executables; copies the runner, schema, and task-context helper into an
owner-only host directory; checks `claude auth status` and `codex login status`;
and prints the exact machine-specific permission entries.

Put the printed Codex `prefix_rule` in a user `.rules` file and the printed
Claude `Bash(<absolute-launcher> review:*)` entry in the user-level
`permissions.allow` list. The Codex rule matches only the exact absolute
`joshix-review review` argv prefix; the launcher itself accepts one typed
operation, validates repository-local prompt data and hard bounds, and calls
only setup-recorded provider executables. Coordinators pass the canonical
realpath of the Git top level; setup pins PATH-resolved Node shebangs to the
recorded Node executable. Codex [rules use exact argv-prefix
matching](https://developers.openai.com/codex/rules), while Claude's
[CLI and tool permission controls](https://docs.anthropic.com/en/docs/claude-code/cli-usage)
provide the corresponding host allow entry.

If setup reports `approvals_reviewer = "guardian_subagent"`, migrate it to
`"auto_review"` when automatic escalation review is desired. Leave a missing
setting missing. Restart Codex and Claude after changing permissions or plugin
installations; existing sessions may retain loaded policy.

Do not put credentials in Codex configuration, widen the whole sandbox's
network or write access, select reviewer executables through PATH at launch
time, or create a persistent allow rule for Node, either provider CLI, the
general runner, or a plugin/cache path. Re-run setup after Node or provider
executables move; stale configuration fails closed and the coordinator uses
the recorded same-role fallback when available.

### Codex

The local Codex plugin is defined in `.codex-plugin/plugin.json`. For local development, point Codex at this checkout through your local plugin marketplace/configuration.

Expected skill names use the `joshix:` namespace, for example:

- `joshix:using-joshix`
- `joshix:task-context`
- `joshix:brainstorming`
- `joshix:writing-plans`
- `joshix:subagent-driven-development`
- `joshix:code-review`
- `joshix:commit-message`
- `joshix:commit-staged`
- `joshix:reviewing-plans`
- `joshix:reviewing-specs`
- `joshix:receiving-code-review`
- `joshix:receiving-plan-review`
- `joshix:receiving-spec-review`
- `joshix:verification-before-completion`

### Claude Code

The Claude plugin metadata lives in `.claude-plugin/`. During local testing, the Claude test harness passes this repository as `--plugin-dir`, so tests exercise the skills in this checkout instead of any globally installed plugin.

The user installation comes from the local `joshix-dev` marketplace. Because
the development manifest remains at version `1.2.0`, `claude plugin update`
reports that it is current without recopying changed files. Refresh the local
cache explicitly after workflow changes:

```bash
claude plugin uninstall joshix@joshix-dev --scope user --keep-data --yes
claude plugin install joshix@joshix-dev --scope user --yes
```

Start a new Claude session after reinstalling; an existing session may retain
skills it already loaded.

### OpenCode

The OpenCode plugin entrypoint is `.opencode/plugins/joshix.js`. See `.opencode/INSTALL.md` for harness-specific notes.

### Gemini

Gemini loads `GEMINI.md`, which points at the local `using-joshix` bootstrap and Gemini tool mapping.

## Workflow

1. **brainstorming** refines rough ideas before implementation.
2. **writing-plans** turns approved requirements into executable plans under `.joshix/plans/`.
3. **reviewing-plans** and **reviewing-specs** review pasted or referenced plans and specs by default; execution requires an explicit instruction.
4. **subagent-driven-development** or **executing-plans** executes approved plans.
5. **test-driven-development** applies RED-GREEN-REFACTOR for core behavior changes and bug fixes.
6. **code-review**, **requesting-code-review**, **receiving-code-review**, **receiving-plan-review**, and **receiving-spec-review** handle review workflows.
7. **commit-message** drafts commit messages from staged changes without mutating git state.
8. **commit-staged** commits only when all local changes are already staged.
9. **verification-before-completion** requires fresh evidence before claiming work is done.

When an active joshix planning or development workflow has at least three tracked nodes,
the top-level agent emits a Mermaid source DAG at the start, on state or
dependency changes, and at completion. Completed work is green, in-flight work
is blue, and todo work keeps Mermaid's default styling. The source fence is the
user-facing artifact; clients may render it natively, and agents do not create a
PNG fallback. Subagents do not emit the DAG, and it is not shared task state.

Plan, spec, and code review producers remain read-only and return detailed,
evidence-backed reports. Top-level producers may use prior shared reasoning;
ordinary delegated producers receive the required context in their dispatch
and never access shared task context. A policy-active persistent reviewer peer
is the narrow exception described below.

The artifact-owning agent responds through the matching reception skill. It
independently verifies the review, automatically applies agreed objective
findings, and reports afterward. Product, scope, ownership, and architecture
choices remain owner-gated, and an explicit no-edit instruction keeps the
meta-review read-only. Artifact readiness requires reviewer approval plus the
owner agent's independent concurrence.

### Proportional workflow policy

A repository may opt into proportional ceremony and verification by naming a
policy from its loaded guidance or one directly referenced runbook:

```text
joshix-workflow-policy: <repo-relative-path>
```

Without that declaration, joshix keeps its existing workflow unchanged. With
it, repository-defined criticality controls verification and review rigor;
task complexity independently controls planning ceremony; and the effort
estimate only drives the proportional cost alarm. Repository safety,
authorization, and completion rules remain unconditional at every level.

Policy-active reviews use one persistent reviewer peer per task. Codex pairs
with Claude and Claude pairs with Codex; OpenAI and Anthropic are the complete
built-in provider boundary, including their current and future models. Adding
another provider requires a joshix update, not repository configuration.
Activating a repository workflow policy also activates this pairing, so review
may send repository content between OpenAI and Anthropic.

Both peers may read the repository and shared task history. The coordinator
alone edits files and appends history. It automatically relays review,
fix/rebuttal, and rereview turns until approval or a real bubble-up. If the
other provider is unavailable, a separate same-model reviewer assumes the same
role for the task. A lost provider session is replaced from SQLite. Review
turns remain bounded and recorded idempotently; only the absence of every
automatic reviewer path becomes one capability decision memo.

Without a workflow-policy declaration, joshix review behaves as before.
Ordinary subagents remain outside top-level shared task context in both modes.

Approval never implies authorization for the next phase. A completed approved
spec ends with `Ready to plan; waiting for your command.` and a completed
approved plan ends with `Ready to execute; waiting for your command.` These are
hold states, not fabricated owner decisions.

joshix is parallel-first after execution is authorized when meaningful tasks
are independent, have disjoint ownership, and can be verified safely. Coupled,
uncertain, overlapping, and unsafe shared-state work stays inline or serial.
`dispatching-parallel-agents` owns the reusable policy;
`subagent-driven-development` invokes it for suitable plans.

Every top-level Git-backed Codex or Claude task creates or connects to a private
`.joshix/tasks/<task>/` workspace before substantive work, including one-turn
questions. The workspace gives both agents the same compact current state,
visible-message history, and accessible files. The top-level coordinator owns
writes; only a declared policy-active reviewer peer may read the supplied task.

## Agent Artifacts

Use `.joshix/` for working artifacts:

- `.joshix/context/` is ignored scratch context.
- `.joshix/tasks/` is ignored per-task Codex/Claude handoff state. Each task
  contains a compact `current.md`, append-only `history.sqlite`, and shared
  `files/`; a nested `.gitignore` self-ignores the area before conversation data
  is written. It is local coordination state, not durable documentation.
- `.joshix/specs/` holds temporary reviewed specs while work is active.
- `.joshix/plans/` holds temporary implementation plans while work is active.

After work is complete, durable decisions belong in normal repo docs, code comments, or other permanent project files.

## Testing

Codex behavior tests live in `tests/codex/`.

Claude Code behavior tests live in `tests/claude-code/`. These tests call Claude prompt mode and may cost money, so run them intentionally.

Model-free workflow contracts live in `tests/static/`. Codex and Claude Code
guidance tests invoke models and should be run intentionally. Representative
orchestration tests are intentionally small because they are slower and
cost-bearing.

## License

MIT License. See `LICENSE` for details.

## Origin

joshix is a personalized fork of Superpowers, adapted for Josh's local
agent workflow and preferences.
