---
name: dispatching-parallel-agents
description: Use when execution is authorized and two or more meaningful tasks may be safe to run concurrently
---

# Dispatching Parallel Agents

This skill is the single owner of parallel-safety, scheduling, fallback, and
start/completion reporting policy. Callers identify candidate work and preserve
their own quality gates; they do not copy this policy.

**Core principle:** Parallel-first after execution authorization for safe
independent work; serial when safety, independence, or coordination value is
uncertain.

## Authorization Boundary

Apply this policy only after the user or an applicable workflow has authorized
execution. Parallel dispatch does not broaden the approved scope or authorize
writes, git operations, external effects, or product decisions that were not
already authorized.

## Parallel-Safety Decision

Parallelize only when at least two meaningful tasks have no semantic dependency,
have disjoint write ownership, do not share unsafe mutable resources, and have
a safe focused feedback loop or safely deferred feedback.

Stay serial when the problem is not yet decomposed into independent domains,
one change may invalidate another, ownership or independence is uncertain,
verification cannot be isolated, or delegation overhead is unlikely to pay
back.

Briefly report why the work is serial; do not add orchestration machinery to a
serial task.

An older plan without `Depends on:` receives the same conservative
classification as ad hoc work. Absence of the field is neither an error nor
evidence of independence. File or resource overlap is a serialization
constraint, not a directed dependency.

## Scheduling

Use a host-reported concurrency limit when available. When capacity is unknown,
begin with at most two concurrent workers; this is a bootstrap, not a durable
slot limit.

1. **Completion-aware:** Observe individual returns and backfill capacity with
   the most useful ready implementation, review, or fix.
2. **Join-all:** Launch a bounded ready wave, wait for the whole wave, then
   schedule the next wave.
3. **Serial:** Run the same authorized work and quality gates one at a time when
   concurrent workers are unavailable.

## Shared Checkout

Concurrent writers receive exclusive file and mutable-resource scopes. While
writes overlap, workers run only focused checks that do not consume another
lane's unstable files or mutate shared outputs. Broad builds, full suites,
repository-wide checks, shared generators, mutable caches, and fixed ports wait
for serial integration unless explicitly isolated.

When a worker returns, compare its actual changed files and touched resources
with its declared scope before releasing dependents. Inspect and resolve
unexpected overlap serially.

If required verification is temporarily unsafe, the lead runs it at the
first safe serialization point or dispatches a verifier.
The lane stays pre-review until it passes. Classify failure as lane-local or
cross-lane, return it to the responsible original worker when continuation is
supported, or dispatch a fully briefed replacement, then repeat verification.

Reviewer input contains the lane's exact scope and a lane-scoped diff or
equivalent change summary including untracked files, never an aggregate
in-flight working-tree diff.

## Model and Reasoning

Delegated workers use the current/default model and reasoning effort. Let host
inheritance cascade and do not downgrade or override either unless the user,
repository, or platform explicitly requires it. If reasoning controls or
reliable metadata are absent, use the host default and do not claim a specific
effort was enforced.

## Reporting

Reporting applies only to work entering this parallel-dispatch policy.

Before dispatch, report parallel lanes, serial phases and reasons, the
expected critical path, and expected peak concurrency.

After fresh verification, report what actually overlapped and the
actual critical path when identifiable. Also report
serial waits, retries, or re-serialization, and meaningful topology variance.

Always provide the qualitative account. Add timing only when observed event
boundaries support it; otherwise omit numbers. When supported, wall time runs
from authorized execution through fresh verification, serial-equivalent time
sums material node durations, savings is their difference, reduction is savings
divided by serial-equivalent time, and throughput is serial-equivalent time
divided by wall time.

Use a Mermaid dependency graph when there are at least two concurrent lanes and
three meaningful work items; otherwise use compact text.
Always emit the Mermaid fence at that threshold. A meaningful work item is a
separately tracked implementation, shared-foundation, or integration node;
routine reviews do not count merely to cross the threshold. Reuse the topology
at completion.

## Failure Handling

- A lane-local question pauses only that lane; a shared scope, architecture,
  interface, or assumption question pauses affected lanes and is raised to the
  owner when approved context cannot answer it.
- A blocked lane stops its descendants, not unrelated authorized work.
- If all runnable work finishes while required work remains blocked, emit an
  interim completed/blocked/waiting report and do not claim completion.
- Same-worker continuation is preferred when supported; otherwise give a fresh
  worker the full task, scoped change context, findings, and verification
  evidence.
- After every lane passes its caller-owned reviews, perform serial integration,
  broad checks, whole-change review, and fresh verification.
