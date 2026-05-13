# Agent Workflows

Compass agents should work as a factory line: Plan chooses one valuable increment, Develop implements exactly that increment, and Reflect occasionally adjusts direction. Each handoff should leave the next agent with concise, durable context.

## Plan

- Ground plans in the repository before choosing work.
- Produce one commit-sized `immediate` plan with a meaningful verify command.
- Preserve `estimatedDifficulty` and `verifyTimeoutMs` when they matter.
- Use `search_docs` and `read_doc` when local guidance would sharpen quality, testing, or workflow choices.

## Develop

- Start by understanding the relevant files and tests.
- Commit only finished, verified work.
- Leave clear feedback for Plan, especially when scope changes or a verify command is wrong.
- Keep the main worktree clean; Compass may run Develop inside a disposable worktree and promote only after post-checks pass.

## Reflect

- Look for drift across sessions rather than rewriting strategy by habit.
- Update long-term direction only when a draft, completion, or repeated failure changes the actual route.
- Record durable lessons, not status logs.
