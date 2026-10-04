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

The static runner also executes deterministic shared-task and reviewer
transport suites. Run these focused model-free checks while narrowing failures:

```bash
node --disable-warning=ExperimentalWarning --test tests/task-context/task-context.test.mjs
node --disable-warning=ExperimentalWarning --test tests/reviewer-host/reviewer-host.test.mjs
bash tests/static/test-autonomous-review-contract.sh
bash tests/static/test-review-reception-contract.sh
bash tests/static/test-workflow-policy-contract.sh
bash tests/static/test-readiness-hold-contract.sh
```

These commands are deterministic and model-free.

The host suite proves one provider spawn, fresh-process profiles, literal argv
transport, command-token-bounded Claude permissions, confined task and Git
reads, ordinary SQLite append, fresh-process rereview continuity, completed-
result validation, bounded terminal stdout/stderr diagnostics, authentication
guidance, signal propagation, direct failure
results, permission-unsafe path rejection before provider spawn, and a one-file
owner-only install. Static and focused contract oracles cover the semantic stop
conditions for owner decisions, repeated rebuttal without evidence, unchanged
defects, transport failures, and cancellation.

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

Focused policy and autonomous-review behavior checks are:

```bash
tests/codex/run-skill-tests.sh --test test-workflow-policy-behavior.sh
tests/codex/run-skill-tests.sh --test test-workflow-proportionality-behavior.sh
tests/codex/run-skill-tests.sh --test test-discussion-review-routing-behavior.sh
tests/codex/run-skill-tests.sh --test test-completion-gate-recovery-behavior.sh
tests/codex/run-skill-tests.sh --test test-autonomous-review-loop-behavior.sh
tests/codex/run-skill-tests.sh --test test-opposite-provider-routing-behavior.sh
bash tests/codex/test-readiness-hold-behavior.sh
bash tests/codex/test-review-followup-scope-behavior.sh
bash tests/codex/test-owner-question-wait-behavior.sh
bash tests/codex/test-owner-question-no-timer-behavior.sh
bash tests/codex/test-browser-test-isolation-behavior.sh
bash tests/codex/test-receiving-spec-review-owner-decision-gate-behavior.sh
tests/claude-code/run-skill-tests.sh --test test-autonomous-review-loop-behavior.sh
node tests/reviewer-host/real-codex-claude-smoke.mjs
```

The opposite-provider routing test makes one read-only model call with the
relevant skill instructions and 20 synthetic decisions. A single Codex model
evaluates scenarios for Claude and Codex coordinators, with and without policy,
for spec, plan, code, and lane reviews; missing-bridge cases must block and
assigned reviewers must not delegate recursively. This does not run a Claude
coordinator or launch reviewers. The live host smoke above separately exercises
both reviewer providers through the installed bridge; it tests transport, not
the coordinator's routing decision.

The source-only follow-up, question/wait, readiness, workflow-policy, and owner
reception checks use repository skills in isolated fixtures. They cover settled
decisions versus new interaction defects, rendered choices without timed
consent, automatic plan-file creation, and short mechanical planning under both
policy modes. Some Codex builds inject a higher-priority Default-mode prohibition on textual
multiple-choice messages. When that blocks the live question tests, keep the
failure visible. Use the explicit `CODEX_OWNER_QUESTION_ARTIFACT=1` mode on
`test-owner-question-wait-behavior.sh`, `test-readiness-hold-behavior.sh`, and the representative spec owner-gate test
to verify a generated UI report artifact plus waiting/authority behavior. This
mode does not prove live chat/dialog rendering; report that limitation rather
than treating artifact-mode success as a live UI pass.

`test-owner-question-no-timer-behavior.sh` tests waiting independently of choice
formatting. Real Codex turns must ask before a dependent edit, complete separate
work, leave a dismissed question unanswered despite elapsed time, and apply the
eventual explicit answer. The test rejects observed agent timers, announced
defaults, and repeated questions. It does not inspect native desktop dialog
chrome or prove that every future model response will comply. Set
`JOSHIX_TEST_SKILLS_DIR` to an installed plugin's `skills` directory to repeat
this check against that installation.

`test-browser-test-isolation-behavior.sh` runs five fresh Codex sessions against
a simulated browser driver: ordinary headless testing, a check requiring a
separate visible browser, missing test authentication, unavailable isolated
tooling, and an explicit request to inspect a named live tab. It checks actual
tool calls and matching fixture logs, including concrete blocker reports and
positive successful checks. No real browser, personal profile, cookies, or
login is accessed. This measures agent choices with a mocked tool, not native
desktop browser integration or guaranteed future adherence.

Set `JOSHIX_TEST_SKILLS_DIR` to an installed plugin's `skills` directory to test
its bootstrap, and `JOSHIX_BROWSER_TEST_CASE=login-blocked` to run one scenario.
`--oracle-only` runs the deterministic fixture processes and positive/negative
trace checks. `tests/static/test-browser-test-isolation-contract.sh` invokes
that entry point alongside the bootstrap text anchors, and is included in the
normal model-free suite. The baseline reproduced an isolated-login failure
followed by live-session reuse; other unmodified baseline samples already
complied, so neither the failure nor compliance is deterministic.

Static question fixtures reject invalid spacing, missing Pro/Con,
one/five choices, duplicate recommendations, excessive summaries, and fenced
user-visible source. The prompt contract compares the actual bridge instruction
with its authoritative reference.

These commands invoke models and are intentional cost-bearing coverage. The
autonomous-review scripts also expose `--oracle-only` for their deterministic
direction/profile checks. Development slices use focused checks. Advance spec
and plan review follows the shared ceremony rule and explicit repository gates.
Completed retained implementation receives one review before full completion
checks; discussion and previews do not start that gate. Tier rules may add
distinct lane or slice review.

The proportionality fixture observes actual commands and retained edits for an
understood repair, a disposable experiment, a visual preview, and a guarded
repair whose repository policy explicitly requires advance plan review. It
checks failing-then-passing outcome evidence before final review and preserves
the guarded gate. Review transport and visual inspection are simulated; this
test proves workflow choices, not reviewer quality or browser rendering. Set
`JOSHIX_WORKFLOW_CASE=repair|experiment|preview|guarded` to run one case, or
`JOSHIX_TEST_SKILLS_DIR` to compare another skill tree. Do not substitute a
prose-only model answer for observed execution.

The discussion-routing, completion-recovery, reciprocal Claude autonomous-loop,
and real sandbox-to-Claude smoke tests are release gates, not per-round checks.
The reciprocal and smoke tests require the newly installed bridge plus valid
Codex and Claude authentication/permission state. Source verification does not
prove the old installed bridge has changed. Installation and the bridge-dependent
release checks are a separate authorized step; report them as pending until run
against the updated installation. The smoke proves both fresh
provider directions can read ordinary SQLite history, append one ordinary
review message, and leave artifacts plus `current.md` unchanged. Run
`node tests/reviewer-host/real-codex-claude-smoke.mjs --permission-only` to
exercise Claude denial of chained and redirected commands beyond the exact
task-read prefix. That probe is a direct operator prompt using the installed
bridge's pinned Claude executable and exported production permission profile;
the
adversarial commands are not smuggled through the read-only review artifact or
SQLite history.

The reciprocal model sample intentionally covers spec, plan, and code
inference collectively, including a cross-layer defect that contradicts an
approved plan. Each inference assertion comes from an actual read-only reviewer
launched with the canonical artifact-neutral instruction against shared task
history; a coordinator questionnaire that maps described states is not
acceptance evidence. Do not recreate a provider-by-artifact matrix of live
calls; the deterministic layer owns exact transport and profile coverage.

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

The independent-lane fixture, `test-requesting-code-review.sh`, and all workflow
questions in `test-subagent-driven-development.sh` explicitly override provider
selection to exercise native Claude Agent/Task reviewers.
Their native dispatch and outcome-line assertions test that supported override,
not the default opposite-provider route. Under the default bridge route, lane
reviews wait for a verified serialization point and pause implementation writes
until the reviewer returns.

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
- successful PASS-before-APPROVED review order under the explicit native override;
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

Use `--verbose` to stream output, and raise the outer test-harness process
timeout with `--timeout 1800` for orchestration cases. That bound protects CI;
it is not a reviewer-quality deadline or workflow-control signal.
`analyze-token-usage.py` can inspect a session JSONL when token and cost details
are needed.
