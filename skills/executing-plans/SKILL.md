---
name: executing-plans
description: Use when the user explicitly asks to execute, implement, apply, start, carry out, or get done a written implementation plan
---

# Executing Plans

## Overview

Load plan, review critically, execute all tasks, report when complete.

<EXTREMELY-IMPORTANT>
Do not use this skill merely because the user provides or references a plan. A
plan document is not approval to execute. If the user provides a plan without an
explicit execution instruction, STOP and use `joshix:reviewing-plans` instead.
Do not interpret the general coding-agent default to make changes as execution
approval for a pasted plan.
</EXTREMELY-IMPORTANT>

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Routing:** Execute small or tightly coupled plans inline with this skill. When
two or more tasks are independently implementable with disjoint scopes, route
the plan to `joshix:subagent-driven-development`; that skill invokes the
canonical parallel-dispatch policy. Do not copy scheduling, capacity, fallback,
or reporting rules here.

## The Process

### Step 1: Load and Review Plan
1. Read plan file
2. Review critically - identify any questions or concerns about the plan
3. If concerns: Raise them with your human partner before starting
4. If no concerns: Create or update the available task list and proceed

### Step 2: Execute Tasks

If a workflow policy is active, read
`../using-joshix/references/workflow-policy.md` and
`../using-joshix/references/autonomous-review.md`. Before each edit, next
planned step, reviewer dispatch, and state transition, check authorized scope
and the active-time alarm. Stop before new subsystems, invariants, dependencies,
generalized hardening, or future infrastructure. Use focused checks until the
single final completion gate, and report progress only on `started`, `done`,
`blocked`, or `bubble-up` transitions. The coordinator owns every bounded
review pass, fix or rebuttal, local `dev` settlement, history append, and
snapshot replacement; never ask the owner to broker a routine round. The
central autonomous-review table also owns post-signoff producer passes,
mechanical repairs, infrastructure retries, and production recovery; do not
invent another retry budget here.

For each task:
1. Mark as in_progress
2. Follow each step as written (plan has bite-sized steps). If new facts
   contradict the plan or make a step stale, stop and raise the mismatch
   before proceeding.
3. Run verifications as specified
4. Mark as completed

## Progress DAG

When this top-level workflow has at least three tracked nodes, follow the
canonical trigger, rendering, state, topology, and update rules in
`../using-joshix/references/progress-dag.md`.

### Step 3: Complete Development

After all tasks complete and verified:
- With an active workflow policy, invoke `joshix:requesting-code-review` for
  each task-level tier-selected whole-change gate and complete its autonomous
  bounded loop. Do not start full completion verification before review
  sign-off. Policy absence preserves the existing completion sequence.
- Announce: "I'm using the verification-before-completion skill to verify this work before reporting completion."
- **REQUIRED SUB-SKILL:** Use joshix:verification-before-completion
- Follow that skill to run fresh verification and report evidence before claiming completion
- If the work used `.joshix/specs/` or `.joshix/plans/`, make sure durable
  decisions are reflected in repo documentation where appropriate. Do not treat
  the agent plan/spec as permanent documentation. Follow any explicit closeout
  task for removing or archiving completed `.joshix/` artifacts.

## When to Stop and Ask for Help

**STOP executing immediately when:**
- Hit a blocker (missing dependency, test fails, instruction unclear)
- Plan has critical gaps preventing starting
- You don't understand an instruction
- New evidence contradicts the plan or makes a planned step stale
- Verification fails repeatedly

**Ask for clarification rather than guessing.**

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**
- Partner updates the plan based on your feedback
- Fundamental approach needs rethinking

**Don't force through blockers** - stop and ask.

## Remember
- Review plan critically first
- Follow plan steps as written, but stop on contradictions or stale steps
- Don't skip verifications
- Reference skills when plan says to
- Keep `.joshix/` artifacts temporary or semi-temporary; durable decisions
  belong in repo documentation
- Stop when blocked, don't guess
- Work in the current checkout and branch unless the user explicitly requested a branch or worktree

## Integration

**Required workflow skills:**
- **joshix:writing-plans** - Creates the plan this skill executes
- **joshix:requesting-code-review** - Runs active-policy tier-selected review gates
- **joshix:verification-before-completion** - Verify work before reporting completion
