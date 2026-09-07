---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans for a skilled engineer who has limited project context. Document what they need to know: which files to touch for each task, code, testing, docs they might need to check, and how to verify the work. Give them the whole plan as bite-sized tasks. DRY. YAGNI. Use the repository's testing norms.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain.

## Workflow policy router

If loaded repository guidance declares `joshix-workflow-policy:`, read
`../using-joshix/references/workflow-policy.md` first. For `trivial`, skip this
skill. For `routine`, continue only when the plan is the task's one selected
planning artifact, unless the user explicitly requests both spec and plan.
Mechanical work with settled behavior uses the short-planning branch below,
with or without an active policy. Otherwise `complex` and policy-absent work
continues through the detailed sections. File count and high criticality alone
do not create design complexity; concrete unresolved behavior or architecture
justifies expansion.

Before authoring a plan from an owner-supplied named spec under an active
workflow policy, check ordinary task history for opposite-provider approval of
the unchanged spec or an explicit owner or repository instruction naming the
spec boundary. If neither exists and no opposite-provider review of the
unchanged spec is recorded, review that spec through
`../using-joshix/references/autonomous-review.md`. If approval or the named
override is still absent, report `Spec boundary blocked: opposite-provider
approval is absent and no explicit owner or repository instruction names the
spec boundary.` and stop before plan authoring. This is an entry backstop, not
a second review of an artifact that just completed the `brainstorming`
boundary.

### Short-planning branch

Use this branch for mechanical work with settled behavior under either policy
mode, and for active-policy `routine` work selecting a plan. Write one short
plan containing outcome, authorized scope, exact files, ordered implementation
steps, focused checks, and final completion checks. Do not duplicate complete
implementation code or add detailed task boilerplate. Explicit requests for
both spec and plan receive both concise artifacts, with the required reviews.
Otherwise do not add a brainstorm or spec solely to satisfy the full workflow.

Self-review for ambiguity, missing coverage, and scope growth. Save the plan in
`.joshix/plans/` (or the requested location). Under an active policy, review the written implementation plan through `../using-joshix/references/autonomous-review.md`, unless
an explicit owner or repository instruction names the plan boundary. Continue
only with provider approval or that named override; otherwise report `Plan
boundary blocked: opposite-provider approval is absent and no explicit owner
or repository instruction names the plan boundary.` Apply tier-added review
rigor too. Without a policy, retain the required plan review from the
policy-absent plan review heuristic below. Shorter planning does not reduce testing
or required artifact reviews.

Then stop before the detailed legacy sections below. If execution is not already
authorized, end exactly:

`Ready to execute; waiting for your command.`

### Owner decisions and transitions

Read `../using-joshix/references/owner-question-format.md` for genuine questions.
Continue from a spec automatically once its required reviews and genuine owner
decisions are satisfied; no separate planning command or routine written-spec
signoff. Honor explicit spec-only, review-only, or stop instructions. Plan review
and implementation authorization remain required.

All remaining detailed sections apply to nonmechanical `complex` and
policy-absent work.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Git context:** Plans should assume implementation happens in the current checkout and current branch. Include branch or worktree setup only when the user explicitly requested it.

**Testing context:** Require TDD for core behavior changes, bug fixes, and testable logic. If expected behavior cannot be expressed clearly, include a clarification step before implementation. For docs, config, metadata, generated assets, exploratory spikes, and mechanical refactors where tests would be artificial, use repo-appropriate verification instead.

**Save plans to:** `.joshix/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

Plans in `.joshix/plans/` are execution artifacts, not permanent
documentation. Include closeout work that updates durable repo documentation
when implementation changes product behavior, architecture, operational
workflow, or developer workflow. Do not treat the plan itself as the final
record of the change. Once the work is implemented and durable docs are updated,
the plan/spec should be removed or archived as part of explicit cleanup, not left
as never-ending documentation.

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Add or update the focused test" - step
- "Run the targeted verification" - step
- "Implement the focused change" - step
- "Run the tests and make sure they pass" - step

## Progress DAG

When this top-level workflow has at least three tracked nodes, follow the
canonical trigger, rendering, state, topology, and update rules in
`../using-joshix/references/progress-dag.md`.

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** Choose `joshix:subagent-driven-development` when tasks are independent enough for isolated implementation and review. Choose `joshix:executing-plans` when work is tightly coupled, small, or better handled inline. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Dependency Metadata

Every task declares `**Depends on:** None` or explicit prerequisite task
numbers. Task order is presentational and carries no dependency meaning.
Overlapping files or shared mutable resources are safety constraints that may
force serialization; they do not create an inferred directed dependency.

## Task Structure

````markdown
### Task N: [Component Name]

**Depends on:** None

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

- [ ] **Step 1: Add or update focused test coverage**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run targeted verification**

Run: `pytest tests/path/test.py::test_name -v`
Expected: Fails before the implementation if this is a new behavior, or passes if updating coverage for existing behavior

- [ ] **Step 3: Implement the focused change**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

````

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

## Remember
- Exact file paths always
- Complete code in every step — if a step changes code, show the code
- Exact commands with expected output
- DRY, YAGNI, TDD for core behavior and bug fixes, and repo-appropriate verification for everything else

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

**4. Durable docs:** If the work changes durable product behavior,
architecture, operations, or developer workflow, does the plan include a task to
update the appropriate repo documentation? If not, add one.

**5. Dependencies:** Does every task state `Depends on: None` or explicit task
numbers? Are semantic prerequisites explicit rather than implied by order? Are
overlapping files or mutable resources called out even when no dependency
exists?

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Plan Review Decision

With an active workflow policy, unless an explicit owner or repository
instruction names the plan boundary, review the written implementation plan
through `../using-joshix/references/autonomous-review.md` after self-review and
before owner handoff or execution. The task-level tier may add review rigor,
but it does not suppress this core boundary. Re-review only after a material
plan correction or new evidence, using the existing reception and semantic
stopping rules. If the review is not approved and no explicit owner or
repository instruction names the plan boundary, report the blocked disclosure
below and stop before the execution handoff.

Use this active-policy execution-handoff disclosure:

```text
Core plan review approved and accounted for. Issues found: [count]. [Accepted/rejected summary]. No open blocking review items remain.
```

```text
Plan boundary blocked: opposite-provider approval is absent and no explicit owner or repository instruction names the plan boundary.
```

### Policy-absent plan review heuristic

Under an active policy, do not use this heuristic or its skip disclosure.

With policy absent, after self-review decide whether to request an independent plan review using
`../reviewing-plans/plan-document-reviewer-prompt.md`.

Default to requesting plan review unless the plan is clearly small and low risk.
Use judgment, but silence is not allowed: the execution handoff must state
whether plan review happened.

**Plan review may be skipped when all of these are true:**
- 1-2 tasks
- Single-file, tightly localized, docs-only, prompt-only, config-only,
  test-only, or mechanical cleanup
- No meaningful behavior, architecture, data, deployment, or agent-workflow
  change
- No multi-agent execution expected
- No ambiguity in how the spec maps to the plan

**Request plan review when any of these apply:**
- 3+ implementation tasks
- Multiple files/modules, cross-cutting behavior, or multi-agent execution
- User-facing or agent-facing behavior changes
- Changes to testing workflow, skill behavior, prompts, execution orchestration,
  persistence, auth, CI, deployment, migrations, or generated artifacts
- New abstractions or durable documentation/process changes
- Any meaningful ambiguity in spec-to-plan coverage

If review is skipped, say why:

```text
No plan review requested: this is a small, low-risk plan because [reason].
```

If review is requested, account for it before offering execution:

```text
Plan review completed and accounted for. Issues found: [count]. [Accepted/rejected summary]. No open blocking review items remain.
```

## Execution Handoff

After saving and reviewing the plan, report the recommendation declaratively:

**"Plan complete and saved to `.joshix/plans/<filename>.md`. [Plan review disclosure]. Recommended execution: <subagent-driven or inline>, because <brief reason>."**

**Subagent-driven** is a good fit when tasks touch disjoint files or can be reviewed independently.

**Inline execution** is a good fit when tasks are tightly coupled, small, or likely to require continuous judgment in one context.

Approval is not execution authorization. Unless the same owner message already
explicitly authorizes execution, do not ask a question, manufacture an A/B
choice, or re-request approval. End exactly:

`Ready to execute; waiting for your command.`

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use joshix:subagent-driven-development
- Policy absent: fresh subagent per task plus two-stage review. Active policy:
  preserve the reviewed plan boundary and add only the task-level tier's lane
  review gates.

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use joshix:executing-plans
- Batch execution with checkpoints for review
