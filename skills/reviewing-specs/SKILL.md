---
name: reviewing-specs
description: Use when the user asks to review, audit, sanity-check, validate, or critique a design spec, or supplies or references a spec without asking to edit it or execute work.
---

# Reviewing Specs

Review specs for planning readiness. A spec document is not approval to edit
the spec or execute implementation.

<EXTREMELY-IMPORTANT>
The first non-empty sentence MUST be:

I'm using joshix:reviewing-specs to review this spec by default, not to edit it.

Repeat this exact sentence as the first non-empty line of the final response.
Do not replace it with a generic heading.
</EXTREMELY-IMPORTANT>

Read `../using-joshix/references/review-producer-contract.md` completely.
Review requirements, contradictions, ambiguity, scope, acceptance criteria,
architecture boundaries, failure handling, and verification strategy. Remain
read-only and use the detailed `Spec Review` format with provisional
`Approved | Issues Found` status.

## Report Format

```markdown
I'm using joshix:reviewing-specs to review this spec by default, not to edit it.

# Spec Review

**Status:** Approved | Issues Found

## Critical
- [Section or path]: Problem.
  Evidence: Concrete spec/repository evidence.
  Recommendation: Specific correction.

## Important
- [Section or path]: Problem.
  Evidence: Concrete spec/repository evidence.
  Recommendation: Specific correction.

## Minor
- [Section or path]: Problem.
  Evidence: Concrete spec/repository evidence.
  Recommendation: Specific correction.

## Advisory
- Non-blocking improvement.

## Summary
Brief readiness assessment and what must change before planning.
```

Omit empty severity sections. Retain the evidence/recommendation calibration
from `spec-document-reviewer-prompt.md`; do not use receiver labels or headings.
