# Codex Tool Mapping

Skills use Claude Code tool names. When you encounter these in a skill, use your platform equivalent:

| Skill references | Codex equivalent |
|-----------------|------------------|
| `Task` tool (dispatch subagent) | `spawn_agent` (see [Subagent dispatch requires multi-agent support](#subagent-dispatch-requires-multi-agent-support)) |
| Multiple `Task` calls (parallel) | Multiple `spawn_agent` calls |
| Task returns result | `wait_agent` |
| Continue the same worker | `followup_task` |
| `TodoWrite` (task tracking) | `update_plan` |
| `Skill` tool (invoke a skill) | Skills load natively — just follow the instructions |
| `Read`, `Write`, `Edit` (files) | Use your native file tools |
| `Bash` (run commands) | Use your native shell tools |

## Parallel execution capabilities

- Dispatch/capacity: start independent workers with multiple `spawn_agent`
  calls and respect platform-reported capacity. When capacity is unknown, the
  canonical policy starts with two workers.
- Observation: `wait_agent` supports completion-aware coordination.
- Continuation: use `followup_task` for an existing idle worker; otherwise brief
  a replacement.
- Questions: workers return `NEEDS_CONTEXT`; the lead resolves user questions.
- Reasoning: delegated workers inherit the current/default model and reasoning
  effort unless explicit user, repo, or platform guidance overrides them.

## Subagent dispatch requires multi-agent support

Add to your Codex config (`~/.codex/config.toml`):

```toml
[features]
multi_agent = true
```

This enables `spawn_agent` and `wait_agent` for skills like
`dispatching-parallel-agents` and `subagent-driven-development`.

Legacy note: Codex builds before `rust-v0.115.0` exposed spawned-agent
waiting as `wait`. Current Codex uses `wait_agent` for spawned agents. The
`wait` name now belongs to code-mode `exec/wait`, which resumes a yielded exec
cell by `cell_id`; it is not the spawned-agent result tool.

## Git Workflow

Default to the current checkout and current branch. Do not stage, commit,
create or switch branches, create worktrees, merge, push, or open pull requests
unless the user explicitly asks for that git operation.

When a skill needs to summarize git state, use read-only commands:

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

- `GIT_DIR != GIT_COMMON` -> already in a linked worktree; use it as-is
- `BRANCH` empty -> detached HEAD; do not create a branch unless asked

The agent can still run tests and draft commit messages or PR descriptions when
requested.

When staging or committing, include only files intentionally changed for the task
unless the user asks otherwise.
