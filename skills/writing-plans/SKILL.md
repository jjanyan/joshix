---
name: writing-plans
description: Use when you have spec or requirements that need implementation sequencing, before touching code
---

# Writing Plans

Make the next work executable without writing the implementation twice. Use the
Work and review rules in `../using-joshix/SKILL.md` to select ceremony and advance
review. Read `../using-joshix/references/workflow-policy.md` when the repository
declares a policy. File count and criticality alone do not create uncertainty.

## Short-planning branch

For an understood repair or mechanical change, write one short plan with:

- The outcome and authorized scope.
- The earliest meaningful proof of the main user outcome.
- Exact files and ordered implementation steps.
- Focused checks and required final completion checks.
- Durable documentation affected by the change.

Do not add a spec, full implementation code, or template boilerplate. Explicit
requests for both spec and plan receive both, kept concise. Disposable
experiments can run first under the bootstrap's rules. For trivial work, an
inline statement of the change and check is enough unless the owner asks for
a document.

Save requested plans to `.joshix/plans/YYYY-MM-DD-<topic>.md` or the owner's
chosen location. Self-review for ambiguity, missing coverage, and scope growth.
A settled short plan requires no independent advance approval unless the owner
or repository requires it. This does not reduce testing or final code review.

## Unresolved design

Use `joshix:brainstorming` when a consequential product or architecture choice
still needs resolution. Do not invent alternatives to reopen settled decisions.
For complex work, retain the approved spec and a detailed plan, adding detail
only where behavior, interfaces, sequencing, or ownership would otherwise be
ambiguous. A runnable acceptance check is more useful than speculative code.

When continuing from an owner-supplied named spec, first apply the bootstrap's
advance-review rule. If review is required, confirm its approval or an explicit
owner override before dependent planning. Reuse an unchanged approved spec;
do not dispatch another reviewer just because this skill was entered.

## Tasks and dependencies

Read relevant source and canonical repo commands before naming files or checks.
Group work by behavior and ownership, preserving existing structure. Include
interfaces or short code examples only when they resolve a real ambiguity.

For decomposed plans, every task declares `**Depends on:** None` or explicit
prerequisite task numbers. Task order is presentational and carries no dependency
meaning. Name overlapping files and shared mutable resources; serialize those
changes. Use `joshix:subagent-driven-development` for independent bounded tasks
and `joshix:executing-plans` for coupled work. Do not create branches or worktrees
unless the owner requests them.

For core behavior and bug fixes, use `joshix:test-driven-development`: reproduce
the main outcome failure before changing behavior, then extend coverage to the
required invariants and affected paths. Docs, configuration and exploratory
work use appropriate verification. Preserve repository-required checks.

## Self-review and selected review

Check the plan once against the actual requirements, files, commands,
dependencies, and durable documentation. Correct gaps together. Do not require
complete implementation code or a separate test for every prose sentence.

When advance review is selected by the bootstrap or required by repository
policy, review before the dependent phase. Active policy uses
`../using-joshix/references/autonomous-review.md`; otherwise use the isolated
reviewer template at `../reviewing-plans/plan-document-reviewer-prompt.md`.
Required review needs approval or the owner's explicit override of that review.
If it remains unresolved, report the concrete blocker without implying readiness.
Apply findings through `joshix:receiving-plan-review`. Use a focused executable
check to settle runtime claims before another speculative rewrite.

## Progress and handoff

When this top-level workflow has at least three tracked nodes, follow
`../using-joshix/references/progress-dag.md` for its canonical trigger,
rendering, state, topology, and updates.

Continue from a spec after required reviews and genuine owner decisions without
another routine planning command. Honor explicit spec-only, review-only, or
stop instructions. Report the plan path and next action plainly.

If execution is already authorized in the conversation, use the appropriate
execution skill and continue. Otherwise end exactly:

`Ready to execute; waiting for your command.`

Do not manufacture a decision or borrow an execution hold from unrelated queued
work. Plans are temporary working artifacts: after implementation, preserve
durable decisions in repository documentation. Remove working artifacts only
as part of explicitly requested cleanup.
