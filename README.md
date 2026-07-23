# joshix

joshix is Josh's local agentic skills framework for coding agents. It keeps the workflow pieces that are useful here: brainstorming, planning, TDD, systematic debugging, subagent-driven execution, review handling, and verification before completion.

This fork is not intended as an upstream contribution target. It is customized for local agent behavior and local installation.

## Installation

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
- `joshix:receiving-plan-review`
- `joshix:verification-before-completion`

### Claude Code

The Claude plugin metadata lives in `.claude-plugin/`. During local testing, the Claude test harness passes this repository as `--plugin-dir`, so tests exercise the skills in this checkout instead of any globally installed plugin.

### OpenCode

The OpenCode plugin entrypoint is `.opencode/plugins/joshix.js`. See `.opencode/INSTALL.md` for harness-specific notes.

### Gemini

Gemini loads `GEMINI.md`, which points at the local `using-joshix` bootstrap and Gemini tool mapping.

## Workflow

1. **brainstorming** refines rough ideas before implementation.
2. **writing-plans** turns approved requirements into executable plans under `.joshix/plans/`.
3. **reviewing-plans** reviews pasted or referenced plans by default; execution requires an explicit instruction.
4. **subagent-driven-development** or **executing-plans** executes approved plans.
5. **test-driven-development** applies RED-GREEN-REFACTOR for core behavior changes and bug fixes.
6. **code-review**, **requesting-code-review**, **receiving-code-review**, and **receiving-plan-review** handle review workflows.
7. **commit-message** drafts commit messages from staged changes without mutating git state.
8. **commit-staged** commits only when all local changes are already staged.
9. **verification-before-completion** requires fresh evidence before claiming work is done.

When an active joshix planning or development workflow has at least three tracked nodes,
the top-level agent shows a Mermaid progress DAG at the start, on state or
dependency changes, and at completion. Completed work is green, in-flight work
is blue, and todo work keeps Mermaid's default styling. The graph is a
user-facing update only; subagents do not render it and it is not shared task
state.

joshix is parallel-first after execution is authorized when meaningful tasks
are independent, have disjoint ownership, and can be verified safely. Coupled,
uncertain, overlapping, and unsafe shared-state work stays inline or serial.
`dispatching-parallel-agents` owns the reusable policy;
`subagent-driven-development` invokes it for suitable plans.

Every top-level Git-backed Codex or Claude task creates or connects to a private
`.joshix/tasks/<task>/` workspace before substantive work, including one-turn
questions. The workspace gives both agents the same compact current state,
visible-message history, and accessible files. Subagents never touch this
shared context; their top-level coordinator owns it.

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
