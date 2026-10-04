---
name: brainstorming
description: Use when exploring a new feature or a consequential unresolved product or architecture choice before implementation
---

# Brainstorming Ideas Into Designs

Understand the user's goal and settle the decisions that affect what gets
built. Apply the Work and review rules in `../using-joshix/SKILL.md` first;
read `../using-joshix/references/workflow-policy.md` when policy is declared.
Discussion does not itself authorize a spec, implementation plan, or code.
A visual trial remains a preview until the owner authorizes finishing it.

## Select the useful work

- Settled repair or mechanical work: use `joshix:writing-plans`' short-planning
  branch when a plan helps. Do not manufacture a design discussion.
- Disposable investigation: state the uncertainty and run the smallest safe
  experiment before prescribing a design, under the bootstrap's boundaries.
- Unresolved design: explore the relevant source and constraints, present the
  meaningful alternatives and a recommendation, and settle real owner choices.
- Explicit spec plus plan: produce both, scaled to the actual uncertainty.
  Existing decisions do not need another approval round.

### Routine design-note terminal

If one short design note resolves the task, record outcome, authorized scope,
chosen approach and focused verification. Self-review it; obtain advance review
only when selected by the bootstrap or explicitly required by repository policy.
Do not add a spec and plan solely to satisfy a checklist. Continue only as far
as the user authorized.

## Resolve design

1. Read enough project context to distinguish existing behavior from proposals.
2. Ask only consequential unanswered questions. For owner decisions, follow
   `../using-joshix/references/owner-question-format.md`; do not repeat settled
   questions or add timed defaults.
3. Explain alternatives when the tradeoff matters. Small choices need a short
   explanation; complex interactions need enough detail to be assessed.
4. Establish the main user outcome and its earliest meaningful proof. Preserve
   existing safety and data guarantees, and name genuine unknowns.
5. Present the resulting design for owner agreement before implementing new
   product or architecture choices. Agreement does not authorize execution
   unless the conversation also requests that work.

Use visual comparisons when useful, following the companion rules below. Do
not broaden a feature into a framework, new subsystem, or unrelated cleanup.
Inspect or reproduce technical claims that can be settled locally instead of
asking the owner to arbitrate speculation.

## Requested spec and planning

Save a requested spec to `.joshix/specs/YYYY-MM-DD-<topic>-design.md`, or the
owner's chosen location. Include the goal, scope, decisions, relevant interfaces
and constraints, acceptance evidence, and remaining uncertainties. Avoid copying
whole implementation code or adding details only to fill a template.

Self-review the spec against the original outcome and the actual source. Resolve
contradictions across affected sections together. Apply the bootstrap's advance
review rule. Codex and Claude Code use
`../using-joshix/references/autonomous-review.md` for selected reviews with or
without a workflow policy. Other hosts use
`../reviewing-specs/spec-document-reviewer-prompt.md` in an isolated review
context. A required unapproved review blocks its dependent phase until approval
or an explicit owner override. Do not create an extra gate for a settled note.

After required reviews and genuine owner decisions, continue directly into
writing-plans when planning is within the requested scope. Explicit spec-only,
review-only, or stop instructions remain effective. No extra planning command
or routine written-spec signoff is needed. Implementation authorization remains
separate. Use the execution readiness hold only when execution is the next
unauthorized phase.

When this top-level workflow has at least three tracked nodes, follow
`../using-joshix/references/progress-dag.md` for canonical trigger, rendering,
state, topology, and updates.

## Visual Companion

A browser-based companion for showing mockups, diagrams, and visual options during brainstorming. Available as a tool — not a mode. Accepting the companion means it's available for questions that benefit from visual treatment; it does NOT mean every question goes through the browser.

**Offering the companion:** When you anticipate that upcoming questions will involve visual content (mockups, layouts, diagrams), offer it once for consent:
> "Some of what we're working on might be easier to explain if I can show it to you in a web browser. I can put together mockups, diagrams, comparisons, and other visuals as we go. This feature is still new and can be token-intensive. Want to try it? (Requires opening a local URL)"

**This offer MUST be its own message.** Do not combine it with clarifying questions, context summaries, or any other content. The message should contain ONLY the offer above and nothing else. Wait for the user's response before continuing. If they decline, proceed with text-only brainstorming.

**Per-question decision:** Even after the user accepts, decide FOR EACH QUESTION whether to use the browser or the terminal. The test: **would the user understand this better by seeing it than reading it?**

- **Use the browser** for content that IS visual — mockups, wireframes, layout comparisons, architecture diagrams, side-by-side visual designs
- **Use the terminal** for content that is text — requirements questions, conceptual choices, tradeoff lists, A/B/C/D text options, scope decisions

A question about a UI topic is not automatically a visual question. "What does personality mean in this context?" is a conceptual question — use the terminal. "Which wizard layout works better?" is a visual question — use the browser.

If they agree to the companion, read the detailed guide before proceeding:
`skills/brainstorming/visual-companion.md`
