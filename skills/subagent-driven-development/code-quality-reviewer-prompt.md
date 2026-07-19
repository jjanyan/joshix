# Code Quality Reviewer Prompt Template

Use this template when dispatching a code quality reviewer subagent.

**Purpose:** Verify implementation is well-built (clean, tested, maintainable)

**Only dispatch after spec compliance review passes.**

```
Task tool (general-purpose):
  description: "Quality review Task N: [task name]"
  Use template at requesting-code-review/code-reviewer.md

  PLAN_OR_REQUIREMENTS: Task N from [plan-file]
  DECLARED_LANE_SCOPE: {DECLARED_LANE_FILES_AND_RESOURCES}
  LANE_CHANGED_FILES: {ACTUAL_LANE_CHANGED_FILES_INCLUDING_UNTRACKED}
  LANE_SCOPED_CHANGE_CONTEXT: {LANE_ONLY_DIFF_OR_EQUIVALENT_SUMMARY}
  VERIFICATION: {FOCUSED_AND_DEFERRED_VERIFICATION_RESULTS}
```

Inspect and review only the supplied declared lane scope, changed files, and
lane-scoped change context. Untracked lane files are in scope only when they
are explicitly included in the supplied lane fields. Unrelated in-flight work
may be visible in the checkout. Do not inspect or review the aggregate
in-flight working-tree diff.

**In addition to standard code quality concerns, the reviewer should check:**
- Does each file have one clear responsibility with a well-defined interface?
- Are units decomposed so they can be understood and tested independently?
- Is the implementation following the file structure from the plan?
- Did this implementation create new files that are already large, or significantly grow existing files? (Don't flag pre-existing file sizes — focus on what this change contributed.)

**Code reviewer returns:** Findings (Critical/Important/Minor), Recommendations, Assessment
