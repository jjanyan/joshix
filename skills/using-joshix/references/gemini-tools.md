# Gemini CLI Tool Mapping

Skills use Claude Code tool names. When you encounter these in a skill, use your platform equivalent:

| Skill references | Gemini CLI equivalent |
|-----------------|----------------------|
| `Read` (file reading) | `read_file` |
| `Write` (file creation) | `write_file` |
| `Edit` (file editing) | `replace` |
| `Bash` (run commands) | `run_shell_command` |
| `Grep` (search file content) | `grep_search` |
| `Glob` (search files by name) | `glob` |
| `TodoWrite` (task tracking) | `write_todos` |
| `Skill` tool (invoke a skill) | `activate_skill` |
| `WebSearch` | `google_web_search` |
| `WebFetch` | `web_fetch` |
| `Task` tool (dispatch subagent) | `@agent-name` (see [Subagent support](#subagent-support)) |

## Subagent support

Gemini CLI supports subagents natively via the `@` syntax. Use the built-in `@generalist` agent to dispatch any task — it has access to all tools and follows the prompt you provide.

When a skill says to dispatch a named agent type, use `@generalist` with the full prompt from the skill's prompt template:

| Skill instruction | Gemini CLI equivalent |
|-------------------|----------------------|
| `Task tool (joshix:implementer)` | `@generalist` with the filled `implementer-prompt.md` template |
| `Task tool (joshix:spec-reviewer)` | `@generalist` with the filled `spec-reviewer-prompt.md` template |
| `Task tool (joshix:code-reviewer)` | `@code-reviewer` (bundled agent) or `@generalist` with the filled review prompt |
| `Task tool (joshix:code-quality-reviewer)` | `@generalist` with the filled `code-quality-reviewer-prompt.md` template |
| `Task tool (general-purpose)` with inline prompt | `@generalist` with your inline prompt |

### Prompt filling

Skills provide prompt templates with placeholders like `{WHAT_WAS_IMPLEMENTED}` or `[FULL TEXT of task]`. Fill all placeholders and pass the complete prompt as the message to `@generalist`. The prompt template itself contains the agent's role, review criteria, and expected output format — `@generalist` will follow it.

### Parallel execution capabilities

- Dispatch/capacity: request independent `@generalist` or named-agent tasks
  together. If Gemini does not report a capacity limit, let the canonical
  policy begin with at most two workers.
- Observation: treat a multi-agent prompt conservatively as a join-all wave
  unless the host exposes individual completion events.
- Continuation: when same-worker continuation is unavailable, dispatch a fully
  briefed replacement with the lane scope, change context, findings, and
  verification evidence.
- Questions: workers return `NEEDS_CONTEXT`; the lead owns user questions
  through `ask_user`.
- Reasoning: inherit model and reasoning controls when exposed; otherwise use
  the Gemini default without claiming a specific effort.

## Additional Gemini CLI tools

These tools are available in Gemini CLI but have no Claude Code equivalent:

| Tool | Purpose |
|------|---------|
| `list_directory` | List files and subdirectories |
| `save_memory` | Persist facts to GEMINI.md across sessions |
| `ask_user` | Request structured input from the user |
| `tracker_create_task` | Rich task management (create, update, list, visualize) |
| `enter_plan_mode` / `exit_plan_mode` | Switch to read-only research mode before making changes |
