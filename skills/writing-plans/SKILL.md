---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans for a skilled engineer who has limited project context. Document what they need to know: which files to touch for each task, code, testing, docs they might need to check, and how to verify the work. Give them the whole plan as bite-sized tasks. DRY. YAGNI. Use the repository's testing norms.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Git context:** Plans should assume implementation happens in the current checkout and current branch. Include branch or worktree setup only when the user explicitly requested it.

**Testing context:** Require TDD for core behavior changes, bug fixes, and testable logic. If expected behavior cannot be expressed clearly, include a clarification step before implementation. For docs, config, metadata, generated assets, exploratory spikes, and mechanical refactors where tests would be artificial, use repo-appropriate verification instead.

**Save plans to:** `.agents/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

Plans in `.agents/plans/` are execution artifacts, not permanent
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

## Task Structure

````markdown
### Task N: [Component Name]

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

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Execution Handoff

After saving the plan, offer execution choice:

**"Plan complete and saved to `.agents/plans/<filename>.md`. Recommended execution: <subagent-driven or inline>, because <brief reason>.**

**Subagent-driven** is a good fit when tasks touch disjoint files or can be reviewed independently.

**Inline execution** is a good fit when tasks are tightly coupled, small, or likely to require continuous judgment in one context.

**Proceed with the recommended approach, or use the other one?"**

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use joshix:subagent-driven-development
- Fresh subagent per task + two-stage review

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use joshix:executing-plans
- Batch execution with checkpoints for review
