---
name: commit-message
description: Use when the user asks for joshix commit message, JCM, a commit message, commit subject/body, or a summary of staged changes for a compliant commit.
---

# Commit Message

Draft a commit message only. Do not stage, unstage, commit, amend, or otherwise
modify git state unless the user explicitly asks for that operation.

## Scope

Default: inspect only staged changes.

Run:

1. `git diff --cached --stat`
2. `git diff --cached --name-status`
3. `git diff --cached --` or targeted staged diffs

Ignore unstaged and untracked files unless the user explicitly asks to include
them. If no changes are staged, say no staged changes were found and ask whether
to use unstaged changes instead.

When practical, check recent commit subjects:

```bash
git log -n 20 --format=%s
```

Prefer the repo's existing scope and phrasing when it does not conflict with
the required format below.

## Message Rules

Produce a commit message in this format:

```text
<type>(<scope>): <imperative summary>

Why: <problem or motivation>
What: <key implementation changes>
Risk: <side effects, migrations, or none>
```

Allowed types are `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`,
`ci`, and `chore`.

Subject requirements:

- Use imperative mood, such as `add`, `fix`, `remove`, `rename`, `validate`, or
  `persist`.
- Keep the subject line at 72 characters or fewer.
- Do not end the subject with a period.
- Be specific about the changed behavior or subsystem.
- Avoid vague summaries such as `update`, `fix stuff`, `wip`, or `misc cleanup`.

Body requirements:

- Include a body for every non-trivial change.
- Use exactly the labels `Why:`, `What:`, and `Risk:`.
- Use `Risk: none` when no meaningful side effects, migrations, compatibility
  changes, or operational risks are apparent.
- Include a `BREAKING CHANGE:` footer when staged changes introduce
  incompatible behavior or interface changes.

## Type And Scope Selection

Choose the type from the dominant staged intent:

- `feat`: user-visible capability or newly supported behavior
- `fix`: bug fix or incorrect behavior correction
- `refactor`: internal restructuring without behavior change
- `perf`: performance improvement
- `test`: tests only or test infrastructure focused changes
- `docs`: documentation only
- `build`: dependencies, packaging, build system, generated artifacts
- `ci`: continuous integration workflows or automation
- `chore`: maintenance that does not fit the other types

Choose a concise scope from the most specific useful subsystem, package, route,
feature, or file group. Prefer established local names over invented categories.

When multiple unrelated staged changes are present, either draft the best single
message for the dominant coherent change and mention the secondary staged area,
or say the staged changes look like multiple commits and provide separate
suggested messages.

## Output

Return one fenced `text` block containing the proposed commit message. Add at
most one short note outside the block only when there is ambiguity, such as
mixed staged concerns or inferred risk.
