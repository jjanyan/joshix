# joshix

joshix is Josh's local agentic skills framework for coding agents. It keeps the workflow pieces that are useful here: brainstorming, planning, TDD, systematic debugging, subagent-driven execution, review handling, and verification before completion.

This fork is not intended as an upstream contribution target. It is customized for local agent behavior and local installation.

## Installation

### Codex

The local Codex plugin is defined in `.codex-plugin/plugin.json`. For local development, point Codex at this checkout through your local plugin marketplace/configuration.

Expected skill names use the `joshix:` namespace, for example:

- `joshix:using-joshix`
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
2. **writing-plans** turns approved requirements into executable plans under `.agents/plans/`.
3. **reviewing-plans** reviews pasted or referenced plans by default; execution requires an explicit instruction.
4. **subagent-driven-development** or **executing-plans** executes approved plans.
5. **test-driven-development** applies RED-GREEN-REFACTOR for core behavior changes and bug fixes.
6. **code-review**, **requesting-code-review**, **receiving-code-review**, and **receiving-plan-review** handle review workflows.
7. **commit-message** drafts commit messages from staged changes without mutating git state.
8. **commit-staged** commits only when all local changes are already staged.
9. **verification-before-completion** requires fresh evidence before claiming work is done.

## Agent Artifacts

Use `.agents/` for working artifacts:

- `.agents/context/` is ignored scratch context.
- `.agents/specs/` holds temporary reviewed specs while work is active.
- `.agents/plans/` holds temporary implementation plans while work is active.

After work is complete, durable decisions belong in normal repo docs, code comments, or other permanent project files.

## Testing

Codex behavior tests live in `tests/codex/`.

Claude Code behavior tests live in `tests/claude-code/`. These tests call Claude prompt mode and may cost money, so run them intentionally.

## License

MIT License. See `LICENSE` for details.

## Origin

joshix is a personalized fork of Superpowers, adapted for Josh's local
agent workflow and preferences.
