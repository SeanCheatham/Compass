# Compass

Compass is a recursive iteration tool for autonomous project development. It wraps the Claude Agent SDK to run a tight **Plan → Develop** loop, driven by draft plans you submit through a local web UI.

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
- `--codex-sidecar auto|verify-failures|off` — optionally use an installed Codex CLI as a read-only sidecar for narrow diagnostics. Default is `auto`; can also be set with `COMPASS_CODEX_SIDECAR`.

Codex is not a primary Compass runtime. Claude remains responsible for Plan,
Develop, Compass MCP tools, state updates, commits, and completion handoffs. In
`auto` mode, Compass only asks Codex for concise verify-failure diagnosis when
the `codex` CLI is installed and available. Override the binary with
`COMPASS_CODEX_BIN` and the sidecar timeout with
`COMPASS_CODEX_SIDECAR_TIMEOUT_MS`.

Press Ctrl+C to stop. Run `compass status` at any time to print the current `state.json` and `drafts.md`.

## Architecture

### Two agents

**Plan** — read-only over the codebase. Mutates state via MCP tool calls only.
- Reads the current state, drafts, last feedback, lessons, and a cached symbol map of the repo (all injected into its system prompt).
- Calls `set_state(...)` exactly once with the new `completed` / `next` / `followUp`.
- Optionally calls `append_lesson(text)` or `set_lessons(text)` to record durable guidance.
- Sets `next` to `null` when there is no concrete next step. The runner idles and waits for drafts.

**Develop** — full read/write over the codebase, plus shell, web fetch/search, sub-agents, and skills.
- Implements the current `next.plan`.
- Iterates until `next.verify` exits 0 (default 10-minute timeout, override via `COMPASS_VERIFY_TIMEOUT_MS`).
- Commits changes (`git add` + `git commit`).
- Calls `complete({ feedback, bypassVerify? })` to signal end-of-iteration. The feedback string is threaded into the next Plan run. Setting `bypassVerify: true` tells the runner to skip the verify post-check this iteration — Develop uses this when it determines mid-implementation that the verify command can't pass without Plan revisiting the plan, avoiding two doomed retry attempts.

After Develop's `complete` call, the runner enforces three post-checks:
1. `complete` was actually called (skipping it is treated as a failed iteration).
2. The `verify` command from `next` must exit 0 (skipped when Develop sets `bypassVerify: true`).
3. `git status --porcelain` must be empty (everything committed or gitignored).

If any fail, the runner re-prompts Develop with the failure (up to 3 attempts) before yielding to Plan. If an attempt is cut off mid-task (budget exhausted, max turns hit, or stream ends without `complete`), the runner skips further retries and spins up a single dedicated **Cleanup pass** with a fresh budget — its job is to either finish the in-flight work or revert it to a clean state so Plan gets a clean handoff.

### MCP tools

Compass exposes a small in-process MCP server to the agents.

| Tool             | Plan | Develop | Purpose                                                                      |
|------------------|------|---------|------------------------------------------------------------------------------|
| `set_state`      | ✓    |         | Replace the full PlanState. Runner persists to `state.json` after Plan ends. |
| `complete`       |      | ✓       | Signal iteration done; ship `feedback` to the next Plan run.                 |
| `read_lessons`   | ✓    | ✓       | Read `lessons.md` (already injected into system prompts; rare).              |
| `set_lessons`    | ✓    | ✓       | Replace `lessons.md` (use for compaction).                                   |
| `append_lesson`  | ✓    | ✓       | Append a single bullet to `lessons.md`. Preferred for the common case.       |

### Codex sidecar

Compass can optionally consult an installed Codex CLI, but only as a narrow
read-only reviewer. The sidecar does not receive Compass MCP tools and does not
own Plan or Develop. Today it is used for verify-failure diagnosis: Claude sees
the failing command and output as before, plus Codex's concise diagnosis in the
retry prompt when Codex is available.

### State

Everything lives in `.compass/` inside your repo (gitignored, per-repo):

```
{repo}/.compass/
├── state.json    # Plan owns. Mutated only via the set_state MCP tool.
├── drafts.md     # User owns (via UI). Runner snapshots+clears before Plan runs.
├── lessons.md    # Plan + Develop. Long-term memory; persists across iterations.
└── COMPASS.md    # User owns (via UI or disk). Persistent project vision; agents read but never write.
```

There is no `feedback.md` — feedback now flows in-memory through the runner, captured from Develop's `complete` call and threaded into the next Plan's system prompt.

`state.json` schema:

```json
{
  "completed": ["one-line summary per shipped iteration"],
  "next": {
    "plan": "markdown describing the single concrete plan Develop will implement next",
    "verify": "shell command run from repo root that exits 0 iff Develop succeeded"
  },
  "followUp": "markdown sketch of what should come after Next"
}
```

`next` may also be `null` when there is no concrete next step.

### Loop

1. If `drafts.md` is empty and `state.json`'s `next` is null, **idle** until a draft arrives (the runner watches `.compass/` for changes).
2. The runner snapshots `drafts.md` (atomic `rename`, race-free with new user input) and clears the in-memory feedback bus, holding the previous Develop's feedback to thread into Plan's system prompt.
3. **Plan** runs: reviews drafts/feedback/lessons, calls `set_state` (and optionally `append_lesson`).
4. The runner persists the new state to `state.json`.
5. If `--require-approval` is set, the runner pauses for explicit UI approval before Develop runs.
6. **Develop** runs against `next.plan`: implements, runs `next.verify`, commits, calls `complete({ feedback })`.
7. Runner runs the three post-checks (complete called, verify, clean tree). Re-prompts Develop on failure.
8. Back to step 1.

There is no separate "done" signal. Idle is the universal exit case: empty drafts and `next == null` send the runner back to step 1. Same path the bootstrap (fresh repo) takes.

## UI

Tabs:

- **Activity** — live stream of agent output and tool calls.
- **State** — Completed list, current `Next` (with verify command), and `Follow-up`.
- **Sessions** — per-iteration record: plan, verify, commits, status.
- **Vision** — the project's north star (`.compass/COMPASS.md`). Edit it here or directly on disk; external edits are picked up live. Plan and Develop both read it; only you can write it.
- **Drafts** — submit a draft plan; see what's pending.
- **Feedback** — the most recent feedback Develop passed to `complete()`. Cleared once Plan picks it up next iteration.
- **Lessons** — long-term memory shared across iterations; written by either agent.

Header controls let you pause the loop (`Pause Now` at the next gate, or `Pause After Iteration`), resume, cancel the iteration in flight, and — when `--require-approval` is on — approve the pending plan before Develop runs.

## Technology

- **Runtime**: Claude Agent SDK (TypeScript)
- **Tools**: in-process MCP server exposing `set_state` (Plan), `complete` (Develop), and `read_lessons` / `set_lessons` / `append_lesson` (both)
- **VCS**: Git (Develop creates commits via standard git CLI)
- **UI**: Plain HTML + WebSocket stream of agent activity

## Non-Goals

- Multi-repo orchestration (one impl repo per Compass instance)
- Audit trail beyond what git already provides
- Auto-revert of bad commits (use `git` directly if needed)
