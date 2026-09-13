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
the plan to `joshix:subagent-driven-development`; that delegates task execution
while this skill retains the core final review and Step 3. The delegated skill
invokes the canonical parallel-dispatch policy. Do not copy scheduling,
capacity, fallback, or reporting rules here.

## The Process

### Step 1: Load and Review Plan
1. Read plan file
2. Check the plan against source and current requirements; resolve technical
   details locally and raise only consequential unanswered owner choices.
3. Create or update the available task list and proceed with unblocked work.

### Step 2: Execute Tasks

Apply the Work and review rules in `../using-joshix/SKILL.md`. For an
owner-supplied named plan, check whether advance review is actually required;
a settled short plan does not acquire that gate merely by being supplied.
Honor explicit repository and tier requirements. If a required plan review has
no approval or owner override, obtain that review before retained implementation;
report the concrete unresolved boundary if approval remains absent. Do not
repeat an unchanged review without new evidence.

With an active policy, read `../using-joshix/references/workflow-policy.md` and
use `../using-joshix/references/autonomous-review.md` for selected reviews.
The coordinator owns scope, evidence, fixes and rebuttals. Use focused checks
until the single final completion gate. Resolve technical details with source
inspection or bounded checks; ask the owner only for new product, policy,
architecture, or scope choices.

For each task:
1. Mark as in_progress
2. Preserve the plan's outcome and constraints. Adapt implementation details to
   new evidence within that scope; record the reason. A new owner choice stops
   only the dependent work.
3. Run verifications as specified
4. Mark as completed

## Progress DAG

When this top-level workflow has at least three tracked nodes, follow the
canonical trigger, rendering, state, topology, and update rules in
`../using-joshix/references/progress-dag.md`.

### Step 3: Complete Development

After all tasks complete and verified:
- With an active workflow policy, unless an explicit owner or repository
  instruction names the completed-implementation boundary, invoke
  `joshix:requesting-code-review` for one core whole-change review of the
  completed implementation, plus any distinct tier-added whole-change gate.
  Obtain approval or the named boundary override before full completion
  verification. Policy absence preserves the existing completion sequence.
- Announce: "I'm using the verification-before-completion skill to verify this work before reporting completion."
- **REQUIRED SUB-SKILL:** Use joshix:verification-before-completion
- Follow that skill to run fresh verification and report evidence before claiming completion
- If the work used `.joshix/specs/` or `.joshix/plans/`, make sure durable
  decisions are reflected in repo documentation where appropriate. Do not treat
  the agent plan/spec as permanent documentation. Follow any explicit closeout
  task for removing or archiving completed `.joshix/` artifacts.

## Failures and interruptions

Diagnose failed checks before further affected edits, then apply a verified
in-scope correction and rerun the affected check. A test failure or stale
implementation detail does not itself require another owner command.

Stop dependent work when an unresolved owner decision, unavailable capability,
uncertain external action, or risk of overwriting user work prevents safe
continuation. Preserve state and report the concrete next action. Use the
bootstrap's Questions and continuation rules after interruptions.

## Integration

**Required workflow skills:**
- **joshix:writing-plans** - Creates the plan this skill executes
- **joshix:requesting-code-review** - Runs the active-policy core final review and tier-added gates
- **joshix:verification-before-completion** - Verify work before reporting completion
