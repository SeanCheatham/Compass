# Compass

Compass is a recursive iteration tool for autonomous project development. It can wrap either the Claude Agent SDK or the Codex SDK to run a tight **Plan → Develop** loop, driven by draft plans you submit through a local web UI.

## Vision

Drop a one-line idea — a feature, a fix, a direction — into the Compass UI. The Plan agent refines it and writes the next concrete plan. The Develop agent implements that plan, commits, and leaves notes. The loop repeats until you say it's done.

## Installation

```bash
git clone https://github.com/SeanCheatham/Compass.git
cd Compass
npm install
npm run build
npm link
```

This makes the `compass` command available globally.

**Prerequisites**: Node.js >= 20.0.0

## Usage

```bash
cd ~/code/my-project
compass
```

Compass will:

1. Confirm you're inside a git repository.
2. Refuse to start if another `compass` is already running here (pidfile lock), or if the working tree is dirty.
3. Create `.compass/` next to your code (and add it to `.gitignore`).
4. Start the web UI on a local port and print the URL.
5. Idle until you submit a draft plan from the UI.
6. From there: Plan refines → Develop implements → repeat.

Flags:

- `--auto-stash` — stash uncommitted changes on startup as `compass-auto-stash` instead of refusing to start.
- `--require-approval` — pause after each Plan run and wait for explicit UI approval before Develop runs. Default is auto-accept.
- `--agent-sdk claude|codex` — choose the agent SDK. Defaults to `claude`; can also be set with `COMPASS_AGENT_SDK`.

When using `--agent-sdk codex`, Compass uses the Codex SDK defaults unless you
set `COMPASS_CODEX_MODEL` to a specific Codex-compatible model.

Press Ctrl+C to stop. Run `compass status` at any time to print the current `state.json` and `drafts.md`.

## Architecture

### Two agents

**Plan** — read-only over the codebase. Mutates state only through the runner handoff.
- Reads the current state, drafts, last feedback, lessons, and a cached symbol map of the repo (all injected into its system prompt).
- Produces the full `completed` / `immediate` / `midTerm` / `longTerm` state.
- With Claude, calls `set_state(...)`; with Codex, returns structured PlanState JSON.
- Sets `immediate` to `null` when there is no concrete next step. The runner idles and waits for drafts.

**Develop** — full read/write over the codebase, plus shell, web fetch/search, sub-agents, and skills.
- Implements the current `immediate.plan`.
- Iterates until `immediate.verify` exits 0 (default 10-minute timeout, override via `COMPASS_VERIFY_TIMEOUT_MS`).
- Commits changes (`git add` + `git commit`).
- Leaves feedback for the next Plan run and signals completion. With Claude this is `set_feedback(...)` then `signal_complete(...)`; with Codex it is the final structured JSON `{ feedback, bypassVerify }`.
- Setting `bypassVerify: true` tells the runner to skip the verify post-check this iteration — Develop uses this when it determines mid-implementation that the verify command can't pass without Plan revisiting the plan, avoiding two doomed retry attempts.

After Develop signals completion, the runner enforces three post-checks:
1. The completion handoff happened (skipping it is treated as a failed iteration).
2. The `verify` command from `immediate` must exit 0 (skipped when Develop sets `bypassVerify: true`).
3. `git status --porcelain` must be empty (everything committed or gitignored).

If any fail, the runner re-prompts Develop with the failure (up to 3 attempts) before yielding to Plan. If an attempt is cut off mid-task (budget exhausted, max turns hit, or stream ends without the completion handoff), the runner skips further retries and spins up a single dedicated **Cleanup pass** with a fresh budget — its job is to either finish the in-flight work or revert it to a clean state so Plan gets a clean handoff.

### MCP tools

With the Claude Agent SDK, Compass exposes a small in-process MCP server to the
agents. With the Codex SDK, Compass uses structured final JSON for the same
runner handoffs: Plan returns the next `PlanState`, Reflect returns either
`null` or a rewritten `PlanState`, and Develop returns `{ feedback,
bypassVerify }`.

| Tool             | Plan | Develop | Purpose                                                                      |
|------------------|------|---------|------------------------------------------------------------------------------|
| `set_state`      | ✓    |         | Replace the full PlanState. Runner persists to `state.json` after Plan ends. |
| `set_feedback`   |      | ✓       | Leave feedback for the next Plan run.                                        |
| `signal_complete`|      | ✓       | Signal iteration done.                                                       |
| `read_lessons`   | ✓    | ✓       | Read `lessons.md` (already injected into system prompts; rare).              |
| `set_lessons`    | ✓    | ✓       | Replace `lessons.md` (use for compaction).                                   |
| `append_lesson`  | ✓    | ✓       | Append a single bullet to `lessons.md`. Preferred for the common case.       |

### State

Everything lives in `.compass/` inside your repo (gitignored, per-repo):

```
{repo}/.compass/
├── state.json    # Plan owns. Mutated only by the runner after Plan handoff.
├── drafts.md     # User owns (via UI). Runner snapshots+clears before Plan runs.
├── lessons.md    # Plan + Develop. Long-term memory; persists across iterations.
└── COMPASS.md    # User owns (via UI or disk). Persistent project vision; agents read but never write.
```

There is no `feedback.md` — feedback is captured on session records and threaded into the next Plan's system prompt.

`state.json` schema:

```json
{
  "completed": ["one-line summary per shipped iteration"],
  "immediate": {
    "plan": "markdown describing the single concrete plan Develop will implement next",
    "verify": "shell command run from repo root that exits 0 iff Develop succeeded",
    "verifyTimeoutMs": 600000,
    "estimatedDifficulty": "medium"
  },
  "midTerm": "markdown sketch of the next ~3-7 iterations",
  "longTerm": "markdown sketch of the strategic arc"
}
```

`immediate` may also be `null` when there is no concrete next step. `verifyTimeoutMs` and `estimatedDifficulty` are optional.

### Loop

1. If `drafts.md` is empty and `state.json`'s `immediate` is null, **idle** until a draft arrives (the runner watches `.compass/` for changes).
2. The runner snapshots `drafts.md` (atomic `rename`, race-free with new user input) and reads the previous session's feedback to thread into Plan's system prompt.
3. **Plan** runs: reviews drafts/feedback/lessons and hands back the next PlanState.
4. The runner persists the new state to `state.json`.
5. If `--require-approval` is set, the runner pauses for explicit UI approval before Develop runs.
6. **Develop** runs against `immediate.plan`: implements, runs `immediate.verify`, commits, and leaves feedback.
7. Runner runs the three post-checks (completion handoff, verify, clean tree). Re-prompts Develop on failure.
8. Back to step 1.

There is no separate "done" signal. Idle is the universal exit case: empty drafts and `immediate == null` send the runner back to step 1. Same path the bootstrap (fresh repo) takes.

## UI

Tabs:

- **Activity** — live stream of agent output and tool calls.
- **State** — Completed list, current `Next` (with verify command), and `Follow-up`.
- **Sessions** — per-iteration record: plan, verify, commits, status.
- **Vision** — the project's north star (`.compass/COMPASS.md`). Edit it here or directly on disk; external edits are picked up live. Plan and Develop both read it; only you can write it.
- **Drafts** — submit a draft plan; see what's pending.
- **Feedback** — the most recent feedback Develop handed to the runner.
- **Lessons** — long-term memory shared across iterations; written by either agent.

Header controls let you pause the loop (`Pause Now` at the next gate, or `Pause After Iteration`), resume, cancel the iteration in flight, and — when `--require-approval` is on — approve the pending plan before Develop runs.

## Technology

- **Runtime**: Claude Agent SDK or Codex SDK (TypeScript)
- **Tools**: in-process MCP tools for Claude; structured final JSON handoffs for Codex
- **VCS**: Git (Develop creates commits via standard git CLI)
- **UI**: Plain HTML + WebSocket stream of agent activity

## Non-Goals

- Multi-repo orchestration (one impl repo per Compass instance)
- Audit trail beyond what git already provides
- Auto-revert of bad commits (use `git` directly if needed)
