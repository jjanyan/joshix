# joshix

joshix is Josh's local agentic skills framework for coding agents. It keeps the workflow pieces that are useful here: brainstorming, planning, TDD, systematic debugging, subagent-driven execution, review handling, and verification before completion.

This fork is not intended as an upstream contribution target. It is customized for local agent behavior and local installation.

## Installation

### Policy-active autonomous review host

Install the review bridge once from this checkout:

```bash
node skills/requesting-code-review/scripts/install-reviewer-host.mjs
```

The default installation is
`$XDG_DATA_HOME/joshix/reviewer-host` when `XDG_DATA_HOME` is absolute, or
`~/.local/share/joshix/reviewer-host` otherwise. Use
`--install-dir <absolute-path>` to choose another non-Git, non-plugin-cache
location. Setup resolves the real Node, Claude, Codex, and Git executables,
generates one owner-only `bin/joshix-review` executable, and prints the exact
machine-specific permission entries. It installs no runner, schema copy, task
helper copy, manifest, or authentication probe.

Each Codex review is ephemeral and ignores ambient user tooling configuration,
so unrelated plugins or MCP authentication cannot expand or block the narrow
read-only review surface. Codex account authentication remains available.

Put the printed Codex `prefix_rule` in a user `.rules` file and the printed
Claude `Bash(<absolute-launcher> review:*)` entry in the user-level
`permissions.allow` list. The Codex rule matches only the exact absolute
`joshix-review review` argv prefix. The operation accepts only provider,
canonical repository root, and exact task folder. The generated executable
calls only its embedded provider and Git paths. The installer rejects a launcher
path containing whitespace or commas, and every operation rejects either
character class in the repository root or task folder before starting a
provider. Codex [rules use exact argv-prefix
matching](https://developers.openai.com/codex/rules), while Claude's
[CLI and tool permission controls](https://docs.anthropic.com/en/docs/claude-code/cli-usage)
provide the corresponding host allow entry.

Do not put credentials in Codex configuration, widen the whole sandbox's
network or write access, or create a broad allow rule for Node or either
provider CLI. Re-run setup after Node, provider, or Git executables move, then
run the real transport smoke test.

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
local workflow edits can occur between manifest-version changes, do not rely on
`claude plugin update` to recopy changed files. Bump the development plugin
version and refresh the local cache explicitly after workflow changes:

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
and never access shared task context. A policy-active reviewer is a fresh
read-only process that reads the exact supplied task through the installed
bridge.

The artifact-owning agent responds through the matching reception skill. It
independently verifies the review and automatically corrects a finding only
when directly inspectable evidence proves a concrete defect, existing
requirements determine the correction, and the result stays inside the
already-authorized outcome and artifact scope. Review severity alone grants no
edit authority. Product, scope, ownership, and architecture choices remain
owner-gated, and an explicit no-edit instruction keeps the meta-review
read-only. Artifact readiness requires reviewer approval plus the owner agent's
independent concurrence.

### Browser testing

Automated browser tests default to an isolated headless browser. A check that
needs a visible browser uses a separate test browser/profile. Agents may use
Josh's live browser session only when he explicitly requests it; a general
testing request, existing login, hidden tab, or failed isolated run is not that
permission. Missing test tooling or authentication must be reported as a blocker,
not worked around by borrowing his browser session or copying its login.
User-requested previews and the brainstorming visual companion are unchanged.

### Proportional workflow policy

A repository may opt into proportional ceremony and verification by naming a
policy from its loaded guidance or one directly referenced runbook:

```text
joshix-workflow-policy: <repo-relative-path>
```

With or without a policy, ceremony follows the work. Discussion stays
discussion, visual trials stay previews, and isolated disposable experiments
can supply evidence before a formal plan. An understood repair uses one short
plan when useful, implementation, focused outcome proof, and completed-change
review. Advance spec or plan review is for consequential unresolved product or
architecture choices, or an explicit owner or repository requirement. A plan
file alone does not create a review gate.

Repository criticality controls test depth and additional review rigor;
complexity independently controls planning detail. Tier-required gates remain
binding. Prove the main user outcome early, check affected paths together, and
use executable evidence to settle technical claims. Preserve settled decisions
and existing authorization after questions or interruptions. Repository safety,
authorization, and completion checks remain unconditional. Agents do not use
elapsed time to control review, pass budgets, or authority.

Policy-active reviews pair Codex with Claude and Claude with Codex; OpenAI and
Anthropic are the complete built-in provider boundary. Every selected review
starts one fresh opposite-provider process with read-only repository and task
access. The reviewer receives one exact, artifact-neutral instruction and
infers whether the active work is a spec, plan, implementation, or cross-layer
combination from SQLite and the repository.

Run `joshix-review review ...` as the **only command in its shell call**.
Prepare files and append logs in separate calls. Do not bundle the launcher with
Python, heredocs, `cd`, chains, or pipes. The wrapper does not elevate itself:
the saved narrow Codex rule allows the standalone command to run outside the
sandbox. A default-permissions tool call alone does not prove where it ran.

The bridge makes one provider attempt. On success it validates the result and
appends an ordinary SQLite message. Failures preserve terminal stdout and stderr
diagnostics bounded to 16 KiB. Authentication errors include recovery guidance:
if the original call was bundled, the coordinator retries once standalone. If
it was already standalone or that retry fails, stop and report the error to the
user; the account may actually be logged out. The bridge itself never retries,
changes credentials, or alters permissions. Other failures and cancellation
stop without retry or fallback; SIGINT/SIGTERM is forwarded and appends no review.

Reviewers recover the latest applicable owner decisions and accepted limitations
from existing history and repository guidance; no mandatory recap or new
artifact is required. Reopening a settled issue needs the prior resolution and
new evidence showing it was wrong, later invalidated, or left a defect outside
the accepted risk. Initial spec/plan review covers the artifact. Follow-ups
inspect corrections and their consequences, including unchanged interactions;
clarification does not restart broad review. Code-review breadth is unchanged.
Required provider approval and owner authority remain intact.

Mechanical work with settled behavior defaults to a short plan, with or without
a workflow policy. File count and criticality alone do not require long planning.
Explicit requests for both spec and plan get both concise artifacts. Verification
and required artifact reviews keep their existing rigor.

After required spec reviews and genuine owner decisions, continue directly to
planning without another command or routine written-spec signoff. Honor explicit
spec-only, review-only, or stop requests. An approved plan still needs execution
authorization; when absent, end with `Ready to execute; waiting for your command.`

Owner decisions use the [shared rendered question template](skills/using-joshix/references/owner-question-format.md):
a prominent question, short concrete summary, two to four choices, and a Pro and
Con for each. Dialogs are allowed. There are no timed defaults: silence, elapsed
time, Skip, and dismissal do not answer the question. Continue independent work
while the decision remains pending; accept the eventual answer without routine
reconfirmation.

Ordinary subagents remain outside top-level shared task context in both policy
modes. Compaction behavior and chat-log insertion tools are unchanged.

joshix is parallel-first after execution is authorized when meaningful tasks
are independent, have disjoint ownership, and can be verified safely. Coupled,
uncertain, overlapping, and unsafe shared-state work stays inline or serial.
`dispatching-parallel-agents` owns the reusable policy;
`subagent-driven-development` invokes it for suitable plans.

Every top-level Git-backed Codex or Claude task creates or connects to a private
`.joshix/tasks/<task>/` workspace before substantive work, including one-turn
questions. The workspace gives both agents the same compact current state,
visible-message history, and accessible files. The provider reviewer is
read-only; the installed bridge alone appends its validated result as an
ordinary reviewer message.

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
