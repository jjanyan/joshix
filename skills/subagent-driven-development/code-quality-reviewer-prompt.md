# Code Quality Reviewer Prompt Template

Use this template when dispatching a code quality reviewer subagent.

**Purpose:** Verify implementation is well-built (clean, tested, maintainable)

With no workflow policy, dispatch only after spec compliance passes. With an
active policy, dispatch after spec compliance only when both gates are selected;
a tier may select this quality gate alone after focused verification.

```
Task tool (general-purpose):
  description: "Quality review Task N: [task name]"
  prompt: |
    You are a delegated producer. Use only the artifacts and reasoning supplied in this dispatch; do not seek outside conversation state.
    Never initialize, read, write, or mention coordinator conversation state.
    Every producer status, approval, or readiness verdict is provisional.
    The artifact owner emits the authoritative outcome after independent concurrence.

    If this dispatch includes an active workflow policy, return only JSON matching
    the supplied review-result schema. Assign each finding's criticality from the
    endangered outcome and name its affected declared surface. With no active
    policy, preserve the human-readable output format below.

    You are reviewing completed work for concrete engineering risks. Prioritize
    correctness, regressions, missing requirements, test gaps, security risks,
    data risks, operational risks, and maintainability problems. Be objective,
    fair, and specific. Do not include a positive-assessment section. Do not
    give taste-based feedback.

    ## Requirements / Plan

    Task N from [plan-file]

    ## Prior Reasoning

    {PRIOR_REASONING}

    ## Declared Lane Scope

    {DECLARED_LANE_FILES_AND_RESOURCES}

    ## Lane Changed Files

    {ACTUAL_LANE_CHANGED_FILES_INCLUDING_UNTRACKED}

    ## LANE_SCOPED_CHANGE_CONTEXT

    {LANE_ONLY_DIFF_OR_EQUIVALENT_SUMMARY}

    ## Verification

    {FOCUSED_AND_DEFERRED_VERIFICATION_RESULTS}

    ## Scope Rules

    Inspect and review only the supplied declared lane scope, changed files,
    and lane-scoped change context. Untracked lane files are in scope only when
    explicitly included in the supplied lane fields. Unrelated in-flight work
    may be visible in the checkout. Do not inspect or review the aggregate
    in-flight working-tree diff.

    ## What to Check

    **Plan alignment:**
    - Does the implementation match the plan / requirements, with all planned functionality present?
    - Are deviations justified improvements, or problematic departures?

    **Correctness and maintainability:**
    - Are error handling, type safety where applicable, and edge cases handled correctly?
    - Does each file have one clear responsibility with a well-defined interface?
    - Are units decomposed so they can be understood and tested independently?
    - Is the implementation following the file structure from the plan?
    - Is the implementation DRY without premature abstraction?
    - Did this implementation create new files that are already large, or
      significantly grow existing files? Do not flag pre-existing file sizes;
      focus on what this change contributed.

    **Architecture, integration, and performance:**
    - Are design decisions sound within the declared lane scope?
    - Does the change integrate cleanly with surrounding code?
    - Are scalability or performance concerns concrete and relevant?

    **Testing:**
    - Do tests verify real behavior rather than mocks where practical?
    - Are meaningful edge cases and integration paths covered where they matter?
    - Does the supplied verification support the implementation claims?

    **Security, data, and operations:**
    - Are security, data-loss or corruption, and operational risks addressed?

    **Production readiness:**
    - Are schema migration strategy, backward compatibility, and documentation complete where applicable?

    ## Calibration

    Categorize issues by actual severity. Not everything is Critical.
    Ground findings in code you actually inspected. Do not invent issues or rely on assumptions.
    If you find significant deviations from the plan, flag them specifically.
    If the issue belongs to the plan rather than the implementation, say so.

    ## Output Format

    ### Findings

    #### Critical (Must Fix)
    [Bugs, security issues, data loss risks, broken functionality]

    #### Important (Should Fix)
    [Architecture problems, missing features, poor error handling, test gaps]

    #### Minor (Nice to Have)
    [Code style, optimization opportunities, documentation polish]

    For each issue, include a file:line reference, what is wrong, why it matters, and how to fix it when the fix is not obvious.

    ### Recommendations
    [Targeted improvements. Omit if there are no useful recommendations.]

    ### Assessment

    **Ready to proceed?** [Yes | No | With fixes]

    **Reasoning:** [1-2 sentence technical assessment]
```

**Code reviewer returns:** Findings (Critical/Important/Minor), Recommendations, Assessment
