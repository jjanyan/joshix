# Testing joshix Skills

joshix tests workflow policy at three levels so fast deterministic checks carry
most of the load and model-backed tests are reserved for behavior that requires
an agent.

## Test layers

### 1. Model-free contracts

`tests/static/` checks required skill contracts and platform mappings without
invoking a model. Run this layer first:

```bash
tests/static/run-tests.sh
```

These checks are deterministic and inexpensive. They catch wording drift and
missing integration surfaces, but they do not prove that a model follows the
guidance.

The static runner also aggregates the model-free transcript and decision
oracles used before paying for live model execution. Run an individual oracle
directly when narrowing a failure:

```bash
python3 tests/claude-code/assert-parallel-transcript.py --self-test
bash tests/claude-code/test-executing-plans-coupled-integration.sh --oracle-only
bash tests/claude-code/test-subagent-driven-development-integration.sh --oracle-only
DISPATCHER_GUIDANCE_ORACLE_ONLY=1 bash tests/codex/test-dispatching-parallel-agents-guidance.sh
bash tests/claude-code/test-subagent-driven-development.sh --oracle-only
```

### 2. Probabilistic behavior checks

The focused suites invoke models to observe routing and workflow choices:

- `tests/codex/` checks Codex behavior;
- `tests/claude-code/` checks Claude Code behavior; and
- `tests/skill-triggering/` checks skill activation prompts.

Because outputs can vary, these tests assert important behaviors rather than
exact prose. They are intentional and cost-bearing: run the smallest relevant
test first, then expand only when the local changes justify the time and model
usage.

### 3. Representative orchestration checks

Two Claude Code integration tests cover the execution topologies that matter:

- `test-subagent-driven-development-integration.sh` executes a plan with two
  independent, disjoint implementation lanes and one dependent integration
  task.
- `test-executing-plans-coupled-integration.sh` executes two tasks that share
  the same source and test files, so implementation must remain inline.

Run them intentionally:

```bash
tests/claude-code/run-skill-tests.sh \
  --integration \
  --test test-subagent-driven-development-integration.sh \
  --timeout 1800

tests/claude-code/run-skill-tests.sh \
  --integration \
  --test test-executing-plans-coupled-integration.sh \
  --timeout 1800
```

Each can take 10–30 minutes and consumes model tokens.

## Concurrency evidence

The independent-lane test parses the Claude session JSONL with
`tests/claude-code/assert-parallel-transcript.py`. It proves overlap only when
both implementer tool-use events occur before the first matching successful
tool-result event. It also verifies, per lane, explicit successful PASS and
APPROVED review outcomes, holds the dependent integration task until both
starting lanes pass, and requires an approved final whole-change review after
the integration lane passes its own review gates.

This tool-event ordering is the concurrency evidence. Merely counting Task or
Agent calls does not prove that work overlapped.

In coupled mode, the same analyzer rejects every Agent or Task dispatch. The
test also checks that the response explains the inline decision and does not
claim parallel topology.

Run its durable model-free transcript fixtures with:

```bash
python3 tests/claude-code/assert-parallel-transcript.py --self-test
```

The analyzer treats a missing top-level `toolUseResult.status` as a synchronous
completion, `completed` as completed, and every other status (including
`async_launched`) as incomplete until a later completion arrives for the same
tool-use ID. On harnesses with async agents (Claude Code >= 2.1), that
completion is a `<task-notification>` block carrying the tool-use ID, a
`completed` status, and the agent's final result text. The analyzer accepts it
from a delivered user message or from the `queue-operation` enqueue event, so
completion is still proven when the coordinator consumes the result through the
task output file and the queued notification is removed before delivery.

Task-tracking tool use is reported when observed but is not a pass condition.
Claude Code may expose `TaskCreate` and `TaskUpdate` only as deferred tools in
headless sessions; the transcript's dispatch, completion, and review events are
the reliable orchestration evidence.

## What the orchestration fixtures verify

The independent fixture checks:

- disjoint files for its two starting lanes;
- observed implementation overlap;
- successful PASS-before-APPROVED review order within each lane;
- dependency-aware integration;
- an approved final whole-change review after the integration lane closes;
- a passing final Node test suite;
- an exact affirmative overlap decision and Mermaid topology; and
- unchanged git history.

The coupled fixture checks:

- shared file ownership produces an exact inline execution decision;
- both requested operations and tests are completed;
- no Agent/Task call or parallel-topology report appears; and
- unchanged git history.

## Choosing the right layer

- Use a static contract for exact text, file presence, or platform mapping.
- Use a focused model-backed test for a single routing or behavioral decision.
- Use an orchestration test only when event ordering or full workflow
  integration is the subject under test.

The larger examples in `tests/subagent-driven-dev/go-fractals` and
`tests/subagent-driven-dev/svelte-todo` remain manual benchmarks for richer
workloads. They are not contract tests and should not be added to the routine
automated suites.

## Troubleshooting Claude tests

Claude orchestration sessions are stored under `~/.claude/projects/`, with the
working directory encoded in the directory name. The integration tests create
unique temporary projects and run Claude from those projects, which keeps
session lookup isolated from concurrent runs.

Use `--verbose` to stream output, and raise the per-test timeout with
`--timeout 1800` for orchestration cases. `analyze-token-usage.py` can inspect a
session JSONL when token and cost details are needed.
