# Owner Question Format

Use this format for genuine owner decisions during discussion, planning, review
reception, and failure recovery. Ask exactly one decision at a time. If existing
requirements determine the answer, proceed instead of manufacturing choices.

Render the question as Markdown, never as a fenced code block or raw source.
Use an H2 question, a blank line, one short summary, then H3 choice headings.
Normally the question is one sentence; one to six sentences are allowed when
needed. Aim for 50 words in the summary; never exceed 100. Explain in simple,
concrete product terms with no jargon or assumed technical knowledge. A small
example can help; it does not need a separate label or section.

Offer two to four genuine choices, normally two, lettered sequentially A–D.
Mark exactly one choice `— Recommended`. Each heading explains the choice;
each choice has one concise Pro line and one concise Con line. Keep the colon
outside the bold label. Put two trailing spaces after the Pro line for a hard
line break. Preserve the blank lines shown below. Do not add a separate short
decision name, `Your decision needed`, `Example:`, or `History:` field.

## Literal template

```markdown
## {Question in simple, concrete terms}?

{Short summary explaining what changes for the user.}

### Choice A: {Simple explanation} — Recommended

**Pro**: {Concrete benefit.}  
**Con**: {Concrete cost or risk.}

### Choice B: {Simple explanation}

**Pro**: {Concrete benefit.}  
**Con**: {Concrete cost or risk.}
```

Repeat the Choice B block for optional C and D. Put the recommendation on the
appropriate choice, not automatically on A.

## Dialogs and waiting

Question dialogs are allowed. If the dialog cannot render this hierarchy and
spacing, show the rendered question once in the normal response and use short,
matching choice labels in the dialog. Do not duplicate the full question in two
places or expose Markdown syntax to the user.

These waiting rules apply to every owner question, in text or any question
dialog, even when host instructions prevent the requested formatting.
Do not start a decision timer, show a countdown, announce a deadline, or choose
a default after a delay. Do not say you will assume a choice after N seconds.
Elapsed time, silence, Skip, dismissal, a tool timeout, and a preselected option
are not answers or approval. Do not repeatedly reopen or reissue an unanswered question.
Keep dependent work pending until the user answers; continue independent work
that is already authorized. If nothing independent remains, yield without
assuming a choice.

Accept a letter-only answer, a modified option, or free-form direction. Record
the answer and continue newly unblocked work without asking for reconfirmation.
Reopen an answered question only when new evidence changes its tradeoff.
