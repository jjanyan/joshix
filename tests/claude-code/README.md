# Claude Code Skills Tests

Automated behavior and orchestration tests for joshix skills using the Claude
Code CLI.

## Test layers

The repository uses complementary test layers:

1. `tests/static/` contains deterministic, model-free contract checks for
   required skill wording and platform mappings.
2. `tests/codex/`, the focused tests in this directory, and
   `tests/skill-triggering/` are probabilistic model-backed checks. They verify
   that Codex, Claude Code, and activation prompts follow the intended routing
   and workflow guidance.
3. Two Claude Code orchestration tests exercise representative execution
   topologies end to end:
   - `test-subagent-driven-development-integration.sh` runs two disjoint
     implementation lanes followed by their dependent integration task.
   - `test-executing-plans-coupled-integration.sh` runs a small plan whose tasks
     share files and must stay inline rather than dispatching implementation
     workers.

Model-invoking tests are intentional and cost-bearing. Run focused tests first,
then broader suites when the change justifies the time and model usage.

## Requirements

- Claude Code CLI installed and in `PATH` (`claude --version` should work)
- This checkout available as the local plugin; the helpers pass `--plugin-dir`
  to Claude invocations
- Python 3 and Node.js for transcript and fixture verification

## Running tests

Run the fast focused suite:

```bash
tests/claude-code/run-skill-tests.sh
```

Run a specific focused test:

```bash
tests/claude-code/run-skill-tests.sh \
  --test test-subagent-driven-development.sh
```

Run the independent-lane orchestration case:

```bash
tests/claude-code/run-skill-tests.sh \
  --integration \
  --test test-subagent-driven-development-integration.sh \
  --timeout 1800
```

Run the coupled-inline orchestration case:

```bash
tests/claude-code/run-skill-tests.sh \
  --integration \
  --test test-executing-plans-coupled-integration.sh \
  --timeout 1800
```

Use `--verbose` to stream full test output. Without it, the runner prints full
output only for failures.

## What the orchestration cases prove

### Independent two-lane plan

The fixture gives Tasks 1 and 2 disjoint files and makes Task 3 depend on both.
It verifies:

- both implementation workers start before either returns;
- each lane records a successful `SPEC OUTCOME: PASS` before quality review;
- each quality review returns successfully with
  `QUALITY OUTCOME: APPROVED` before Task 3 starts;
- Task 3 completes its own spec and quality gates before an approved final
  whole-change review starts;
- all six fixture files exist and the public module exports both operations;
- the final Node test suite passes;
- the final response records `OVERLAP OBSERVED: TASKS 1 AND 2` and includes
  Mermaid source; and
- execution creates no extra commit.

`assert-parallel-transcript.py` derives overlap, completed worker results,
successful lane and whole-change review outcomes, and dependency-gate order
from Claude session tool-use and tool-result events. A count of dispatched
tasks is not treated as concurrency evidence.

The harness reports task-tracking tool use when present but does not fail when
it is absent. Headless Claude Code may expose `TaskCreate` and `TaskUpdate` only
as deferred tools, while the Agent events above directly prove the required
coordination behavior.

### Coupled inline plan

The fixture has two tasks that both modify `src/counter.js` and
`test/counter.test.js`. It verifies:

- no Agent or Task call is dispatched;
- both operations are implemented and tests pass;
- the final response contains only
  `EXECUTION MODE: INLINE; REASON: SHARED FILE OWNERSHIP`;
- no parallel topology or Mermaid overhead is emitted; and
- execution creates no extra commit.

## Test utilities

- `test-helpers.sh` supplies Claude invocation, timeout, assertion, and
  temporary-project helpers.
- `assert-parallel-transcript.py` validates implementation overlap, lane and
  whole-change review order, and the absence of any Agent/Task dispatch in
  coupled mode.
- `analyze-token-usage.py` reports session and subagent token usage for
  cost visibility.

Claude transcripts are stored under `~/.claude/projects/`, with the working
directory encoded into the project directory name. The orchestration fixtures
run Claude inside unique temporary projects so their transcript lookup does not
race unrelated sessions.

Run the durable model-free transcript fixtures directly:

```bash
python3 tests/claude-code/assert-parallel-transcript.py --self-test
```

The fixtures cover synchronous completion, async launch followed by completion,
async completion via delivered or undelivered `<task-notification>` events,
incomplete async launches, dependency-gate order, exact review-outcome markers,
and coupled execution with zero delegated calls.

## Adding tests

1. Prefer a deterministic assertion in `tests/static/` when wording or file
   structure is enough.
2. Use a focused model-backed test only when behavior must be observed.
3. Add full orchestration coverage only for a representative topology that
   cannot be proven by the lower layers.
4. Register Claude tests in `run-skill-tests.sh`.
5. Make intentional model usage and expected runtime visible in the test.

The larger fixtures under `tests/subagent-driven-dev/go-fractals` and
`tests/subagent-driven-dev/svelte-todo` remain manual benchmarks. They are not
contract tests and are intentionally unchanged.
