---
name: verification-before-completion
description: Use when about to claim work is complete, fixed, passing, or ready for requested git/release actions - requires fresh verification evidence before making success claims; evidence before assertions always
---

# Verification Before Completion

## Overview

Claiming work is complete without verification is an unsupported claim, not an
engineering result.

**Core principle:** Evidence before claims, always.

This applies to the meaning of the claim, not the exact wording.

## Completion Gate

Apply the bootstrap's Work and review rules first. A preview or experiment
report describes only the observed result; it does not claim completed retained
implementation or trigger its review gate. When finishing the change, preserve
the main outcome proof along with the required completion evidence below.

When loaded repository guidance declares `joshix-workflow-policy:`, read
`../using-joshix/references/workflow-policy.md`. Apply test depth per materially
changed surface, keep manual verification additive, and use focused checks for
slices and review rounds. When this task materially changed any repository
surface, before running the full completion gate, confirm that the core
completed-implementation review has been approved for the current material
state or an explicit owner or repository instruction names the
completed-implementation boundary. If no core completed-implementation review
is recorded for the current material state and no explicit owner or repository
instruction names the completed-implementation boundary, invoke
`joshix:requesting-code-review` as the backstop. If approval or the named
override is still absent, report `Completed-implementation boundary blocked:
opposite-provider approval is absent and no explicit owner or repository
instruction names the completed-implementation boundary.` and stop before the
full completion gate. Run the repository's full completion gates once, after
review sign-off or that named override, at the end. Policy absence preserves
the existing gate.
If a policy-active completion gate fails, diagnose it with focused evidence and
rerun the affected gate after correction. A correction that materially changes
implementation behavior or scope requires a fresh core review before any
completion claim. A check-only or test-expectation correction that leaves the
reviewed behavior and scope unchanged needs only the focused rerun. Review
transport adds no retry loop, numeric work budget, or special recovery
allowance.

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you have not gathered verification evidence in this session, you cannot
claim the work passes, is fixed, or is complete.

## The Gate Function

```
BEFORE claiming completion, correctness, readiness, or success:

1. IDENTIFY: What evidence proves this claim?
2. GATHER: Run the command, inspect the diff, reproduce the behavior, render the
   output, review the checklist, or otherwise collect fresh evidence
3. READ: Check the actual output, exit code, screenshots, rendered artifact,
   diff, or checklist result
4. VERIFY: Does the evidence confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
5. ONLY THEN: Make the claim

Skip any step = unsupported claim
```

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |
| UI renders correctly | Screenshot/rendered output inspected | Dev server started |
| Durable docs updated | Relevant repo docs/product docs changed or not needed | Plan/spec exists in `.joshix/` |
| Agent artifacts cleaned up | Explicit closeout/cleanup task completed | Incidental deletion during unrelated work |

## Red Flags - STOP

- Using "should", "probably", "seems to"
- Expressing completion/correctness before verification ("Done", "fixed",
  "passes", "ready", etc.)
- About to finalize work or perform requested git/release actions without
  verification
- Trusting agent success reports
- Relying on partial verification
- Thinking "just this once"
- Tired and wanting work over
- **ANY wording implying success beyond the evidence you have gathered**

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | Report it as unverified instead |
| "Linter passed" | Linter ≠ compiler |
| "Agent said success" | Verify independently |
| "I'm tired" | Exhaustion ≠ excuse |
| "Partial check is enough" | Partial proves nothing |
| "Different words so rule doesn't apply" | Meaning over phrasing |

## Key Patterns

**Tests:**
```
✅ [Run test command] [See: 34/34 pass] "All tests pass"
❌ "Should pass now" / "Looks correct"
```

**Regression tests (TDD Red-Green):**
```
✅ Write → Run (pass) → Revert fix → Run (MUST FAIL) → Restore → Run (pass)
❌ "I've written a regression test" (without red-green verification)
```

**Build:**
```
✅ [Run build] [See: exit 0] "Build passes"
❌ "Linter passed" (linter doesn't check compilation)
```

**UI / rendered output:**
```
✅ [Open page/render artifact] [Inspect screenshot/output] "The page renders without overlap at desktop and mobile widths"
❌ "Server started, so UI works"
```

**Requirements:**
```
✅ Re-read plan → Create checklist → Verify each → Report gaps or completion
❌ "Tests pass, phase complete"
```

**Agent artifacts:**
```
✅ `.joshix/` spec/plan used → Durable docs updated or explicitly not needed
❌ Treat `.joshix/plans/...` as permanent project documentation
✅ Explicit cleanup task → Completed `.joshix/` artifact removed or archived
❌ Delete unrelated `.joshix/context/` files while doing feature work
```

**Agent delegation:**
```
✅ Agent reports success → Check VCS diff → Verify changes → Report actual state
❌ Trust agent report
```

## Why This Matters

Unsupported completion claims create real engineering cost:
- Broken trust in status reports
- Undefined functions or incomplete integrations shipped
- Missing requirements hidden behind passing tests
- Time wasted on rework after premature closeout
- Durable docs left stale while `.joshix/` planning artifacts drift

## When To Apply

Apply before:
- ANY variation of success/completion claims
- ANY claim of correctness, readiness, or passing state
- Finalizing the task
- Requested git/release actions
- Moving to next task
- Delegating to agents
- Treating `.joshix/` planning artifacts as durable documentation

**Rule applies to:**
- Exact phrases
- Paraphrases and synonyms
- Implications of success
- ANY communication suggesting completion/correctness

## The Bottom Line

**No shortcuts for verification.**

Gather the evidence. Read it. THEN claim the result.

Keep the claim no stronger than the evidence.
