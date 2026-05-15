---
name: code-review
description: Use when the user asks for joshix code review, JCR, a review of local git changes, "review my code", "check my changes", "look at what I've written", or a full codebase audit.
---

# Code Review

Review code for concrete engineering risk. Findings come first. Do not edit
files, stage, commit, or fix issues unless the user explicitly asks for
implementation.

<EXTREMELY-IMPORTANT>
When this skill is used, the first non-empty sentence MUST be:

```text
I'm using joshix:code-review to review the requested scope.
```

Then produce the review. Do not replace this with a generic heading.
</EXTREMELY-IMPORTANT>

## Scope

Default: review local changes against `HEAD`, including staged and unstaged
tracked changes. Include untracked source, docs, tests, config, and migrations
when they appear intentional. Ignore generated logs, screenshots, build output,
cache directories, and tool artifacts unless they look intended for commit.

Full mode: if the user asks for `--full`, "full audit", or equivalent, review
the whole codebase instead of only local changes.

If a plan, spec, ticket, or pasted requirement is available, review against it.
If not, say the review is risk-based only.

## Context Gathering

For changed-file reviews:

- Inspect the diff first.
- Read each changed file with enough surrounding context to understand behavior.
- Read relevant callers, imports, tests, schemas, migrations, and shared helpers.
- Check verification evidence if present, but do not treat passing tests as proof.

For full audits:

- Map entry points, data flow, storage boundaries, auth boundaries, and external
  integrations.
- Read broadly before forming findings.
- Focus on risks that could affect correctness, security, data, operations, or
  maintainability.

## Calibration

Prioritize:

- Correctness regressions
- Security vulnerabilities
- Data loss or data corruption
- Missing required behavior
- Broken error handling
- Concurrency, async, or lifecycle bugs
- Performance problems with real user or operational impact
- Test gaps that allow meaningful regressions
- Maintainability issues that will compound

Do not report:

- Pure taste
- Cosmetic naming preferences
- Hypothetical rewrites without clear payoff
- "Could be more robust" without a concrete failure mode
- Issues outside the requested scope unless they create immediate risk

Severity:

- Critical: security issue, data loss, broken user-facing behavior, or
  production failure risk.
- Important: likely bug, missing requirement, significant test gap, performance
  problem, or compounding design issue.
- Minor: small cleanup with clear value.
- Refactoring Opportunity: structural improvement worth considering, but not
  required to ship.

## Report Format

Findings first, ordered by severity. Omit empty sections.

```markdown
I'm using joshix:code-review to review the requested scope.

# Code Review

## Critical
- `path/file.ext:line`: Problem.
  Why it matters. Specific fix.

## Important
- `path/file.ext:line`: Problem.
  Why it matters. Specific fix.

## Refactoring Opportunities
- `path/file.ext:line`: Problem.
  What to change and why.

## Minor
- `path/file.ext:line`: Problem.
  Small fix.

## Open Questions / Test Gaps
- Question or missing verification that affects confidence.

## Summary
Briefly state reviewed scope, finding count, and overall readiness.
```

Each finding must include:

- File and line when possible
- What is wrong
- Why it matters
- What to do instead

If the platform supports native inline review comments, use them only for
actionable line-specific findings. The markdown report remains the source of
truth.
