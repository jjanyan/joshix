---
name: commit-staged
description: Use when the user asks for joshix commit staged, JCS, or wants Codex to commit already staged changes without staging anything else.
---

# Commit Staged

Create one git commit from exactly the changes that are already staged. Never
stage, unstage, amend, push, create branches, or alter the commit scope.

## Safety Gate

Fail closed unless the worktree contains staged changes and nothing else.

Run:

1. `git status --porcelain`
2. `git diff --cached --stat`
3. `git diff --cached --name-status`
4. `git diff --cached --`
5. `git diff --quiet`
6. `git ls-files --others --exclude-standard`

Proceed only when:

- `git diff --cached --stat` shows staged changes.
- `git diff --quiet` succeeds, meaning there are no unstaged tracked changes.
- `git ls-files --others --exclude-standard` returns no untracked files.

If any unstaged tracked changes, untracked files, or partially staged files
exist, stop. Say the tree is not fully staged and recommend
`joshix:commit-message` so the user can review the staged subset manually.

## Message Rules

Use the same subject and body rules as `joshix:commit-message`:

```text
<type>(<scope>): <imperative summary>

Why: <problem or motivation>
What: <key implementation changes>
Risk: <side effects, migrations, or none>
```

When practical, check recent commit subjects:

```bash
git log -n 20 --format=%s
```

Allowed types are `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`,
`ci`, and `chore`. Keep the subject line at 72 characters or fewer.
Use `Risk: none` when no meaningful side effects, migrations, compatibility
changes, or operational risks are apparent.

## Commit

Create the commit with a multi-line message that preserves the required body:

```bash
git commit \
  -m "type(scope): summary" \
  -m "Why: ..." \
  -m "What: ..." \
  -m "Risk: none"
```

Do not bypass hooks. If a hook fails, stop and report the failure. Do not amend.

## Verify

After committing, run:

1. `git status --porcelain`
2. `git log -1 --format=%B`

Report the commit subject and whether the worktree is clean. Never push unless
the user explicitly asks.
