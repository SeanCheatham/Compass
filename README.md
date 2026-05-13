# Compass

Compass is a recursive iteration tool for autonomous project development. It wraps the Claude Agent SDK to run a tight **Plan -> Develop** loop, driven by draft plans you submit through a local web UI.

## Vision

Drop a one-line idea -- a feature, a fix, a direction -- into the Compass UI. The Plan agent refines it into one concrete implementation plan, the Develop agent implements and commits it, and the loop repeats while Compass keeps a short-term queue and long-term direction in `.compass/state.json`.

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
4. Start the web UI on a local port, open it in your browser, and print the URL as a fallback.
5. Idle until you submit a draft from the UI, or until `state.json` already contains a non-null `immediate` plan.
6. From there: Reflect occasionally reviews direction, Plan chooses the next `immediate`, Develop implements it, then the loop repeats.

Flags:

- `--auto-stash` -- stash uncommitted changes on startup as `compass-auto-stash` instead of refusing to start.
- `--require-approval` -- pause after each Plan run and wait for explicit UI approval before Develop runs. Default is auto-accept.
- `--codex-sidecar auto|verify-failures|diff-review|off` -- optionally use Codex SDK as a read-only sidecar for narrow diagnostics/review. Default is `auto`; can also be set with `COMPASS_CODEX_SIDECAR`.
- `--no-open` -- do not automatically open the Compass UI in a browser.

Useful environment variables:

- `COMPASS_VERIFY_TIMEOUT_MS` -- default Develop verify timeout in milliseconds. Defaults to 10 minutes.
- `COMPASS_REFLECT_EVERY` -- run Reflect every N iterations. Defaults to 5; set to `0` to disable.
- `COMPASS_CODEX_BIN` -- override the Codex CLI binary used by `@openai/codex-sdk`.
- `COMPASS_CODEX_SIDECAR_TIMEOUT_MS` -- override Codex sidecar timeouts. Verify-failure diagnosis defaults to 2 minutes; diff review defaults to 15 minutes.

Codex is not a primary Compass runtime. Claude remains responsible for Plan, Develop, Compass MCP tools, state updates, commits, and completion handoffs. In `auto` mode, Compass asks Codex for concise verify-failure diagnosis and read-only review of accepted diffs when available.

Press Ctrl+C to stop. Run `compass status` at any time to print the current state, drafts, and lessons.

## Architecture

### Three agents

**Reflect** -- read-only over the codebase, run every `COMPASS_REFLECT_EVERY` iterations.
- Reviews recent session records for directional drift.
- May call `set_state(...)` to rewrite `midTerm` and/or `longTerm`, while preserving the current `completed` and `immediate`.
- May call `append_lesson(text)` for durable guidance.

**Plan** -- read-only over the codebase. Mutates state via MCP tool calls only.
- Reads the current state, drafts, previous feedback, lessons, project vision, and a cached symbol map of the repo.
- Calls `set_state(...)` with the updated `completed`, `immediate`, `midTerm`, and `longTerm`.
- Can call `escalate({ message })` before `set_state` to restart the planning pass on Opus.
- Optionally calls `append_lesson(text)` or `set_lessons(text)` to record durable guidance.
- Sets `immediate` to `null` only when there is no useful next increment. The runner idles and waits for drafts.

**Develop** -- full read/write over the codebase, plus shell, web fetch/search, sub-agents, and skills.
- Implements the current `immediate.plan`.
- Runs `immediate.verify` until it exits 0. `immediate.verifyTimeoutMs` can override the default verify timeout for one plan.
- Selects the Develop model from `immediate.estimatedDifficulty`: `low` -> Haiku, `medium` or omitted -> Sonnet, `high` -> Opus.
- Runs in a disposable Git worktree/branch when the repo already has a HEAD. Compass promotes the branch to the main worktree only after post-checks pass.
- Commits changes with standard git CLI commands.
- Calls `set_feedback({ text })` with the handoff note for Plan.
- Calls `signal_complete({ bypassVerify? })` as the final action. Setting `bypassVerify: true` skips the verify post-check for this iteration, but the clean-tree check still applies.

After Develop's `signal_complete` call, the runner enforces:

1. `signal_complete` was actually called. If the stream is cut off by budget, turn limit, or no completion signal, the runner starts one dedicated Cleanup pass.
2. The `immediate.verify` command exits 0, unless Develop set `bypassVerify: true`.
3. `git status --porcelain` is empty.
4. If enabled, Codex sidecar diff review reports no concrete blocking issues.

If post-checks fail, the runner re-prompts Develop with the failure context, up to 3 attempts. A Cleanup pass runs at most once after a cut-off attempt; it must either finish and commit the in-flight work or revert partial edits so Plan gets a clean handoff.

### MCP tools

Compass exposes a small in-process MCP server to the agents.

| Tool              | Plan | Develop | Purpose |
|-------------------|------|---------|---------|
| `set_state`       | yes  |         | Replace the full PlanState. Runner persists to `state.json` after Plan or Reflect ends. |
| `escalate`        | yes  |         | Restart the current Plan pass on Opus with a summary message. |
| `set_feedback`    |      | yes     | Set the feedback string handed to the next Plan run. Last call wins. |
| `signal_complete` |      | yes     | Signal Develop iteration done and move to runner post-checks. |
| `read_lessons`    | yes  | yes     | Read `lessons.md` (already injected into prompts; rare). |
| `set_lessons`     | yes  | yes     | Replace `lessons.md` (use for compaction). |
| `append_lesson`   | yes  | yes     | Append a single bullet to `lessons.md`. Preferred for the common case. |
| `search_docs`     | yes  | yes     | Search Compass's built-in Markdown guidance docs. |
| `read_doc`        | yes  | yes     | Read one built-in guidance doc by id. |
| `codemap` tools   | yes  | yes     | Search, outline, and navigate the cached repo map. |

### Codex sidecar

Compass can optionally consult Codex through `@openai/codex-sdk`, but only as a narrow read-only reviewer. The sidecar does not receive Compass MCP tools and does not own Plan or Develop. It is used for verify-failure diagnosis and post-Develop diff review: Claude sees the failing command/output as before, plus Codex's concise diagnosis when available; after a successful Develop pass, Codex can review the committed diff and block acceptance with concrete issues.

### State

Everything lives in `.compass/` inside your repo (gitignored, per-repo):

```text
{repo}/.compass/
├── state.json        # Plan/Reflect own. Mutated only via set_state.
├── state.json.bak    # Best-effort backup before each iteration.
├── drafts.md         # User owns via UI. Snapshotted and cleared before Plan runs.
├── lessons.md        # Plan + Develop long-term memory.
├── sessions.json     # Per-iteration session index and latest feedback.
├── sessions/         # Activity/session artifacts.
└── COMPASS.md        # User-owned project vision; agents read but never write.
```

There is no `feedback.md`; feedback is stored on the prior session record after Develop calls `set_feedback`.

`state.json` schema:

```json
{
  "completed": ["one-line summary per shipped iteration"],
  "immediate": {
    "plan": "markdown describing the single concrete plan Develop will implement this iteration",
    "verify": "shell command run from repo root that exits 0 iff Develop succeeded",
    "verifyTimeoutMs": 600000,
    "estimatedDifficulty": "medium"
  },
  "midTerm": "markdown sketch of the next ~3-7 iterations",
  "longTerm": "markdown sketch of the strategic arc ~10+ iterations out"
}
```

`immediate` may also be `null` when there is no useful next increment and the runner should idle. `verifyTimeoutMs` and `estimatedDifficulty` are optional when `immediate` is non-null.

### Loop

1. If `drafts.md` is empty and `state.json`'s `immediate` is null, Compass idles until a draft arrives.
2. The runner snapshots `drafts.md` atomically and loads feedback from the previous session record.
3. Every Nth iteration, **Reflect** may refresh `midTerm` and/or `longTerm`.
4. **Plan** runs: reviews drafts/feedback/lessons/vision, then calls `set_state`.
5. The runner persists the new state to `state.json`.
6. If `--require-approval` is set, the runner waits for explicit UI approval before Develop runs.
7. **Develop** runs against `immediate.plan`: implements, runs `immediate.verify`, commits, calls `set_feedback`, then calls `signal_complete`.
8. Runner runs post-checks: completion signal, verify, clean tree, and optional Codex diff review. It re-prompts Develop on failure.
9. Back to step 1.

There is no separate "done" signal. Idle is the universal exit case: empty drafts and `immediate == null` send the runner back to step 1.

## UI

Tabs:

- **Activity** -- live stream of agent output and tool calls.
- **State** -- Completed list, current Immediate plan, Mid-term queue, and Long-term arc.
- **Vision** -- the project's north star (`.compass/COMPASS.md`). Edit it here or directly on disk; external edits are picked up live. Plan and Develop both read it; only you can write it.
- **Sessions** -- per-iteration record: plan, verify, commits, status, notes, and feedback.
- **Drafts** -- submit a draft plan; see what's pending.
- **Feedback** -- the most recent feedback Develop passed to `set_feedback()`. Cleared once Plan picks it up next iteration.
- **Lessons** -- long-term memory shared across iterations; written by either agent.

Header controls let you pause the loop (`Pause Now` at the next gate, or `Pause After Iteration`), resume, cancel the iteration in flight, toggle approval requirements, and -- when approval is required -- approve the pending plan before Develop runs.

## Development

```bash
npm run build       # build frontend assets and TypeScript
npm run lint        # typecheck with strict unused-code checks
npm test            # run node:test suite through tsx
npm run dev         # watch TypeScript compilation
```

## Technology

- **Runtime**: Claude Agent SDK (TypeScript)
- **Sidecar**: optional `@openai/codex-sdk` read-only diagnostics/review
- **Tools**: in-process MCP server exposing state, feedback, lessons, and codemap tools
- **VCS**: Git (Develop creates commits via standard git CLI)
- **UI**: Plain HTML + WebSocket stream of agent activity

## Non-Goals

- Multi-repo orchestration (one implementation repo per Compass instance)
- Audit trail beyond session records and git history
- Auto-revert of bad commits (use `git` directly if needed)
