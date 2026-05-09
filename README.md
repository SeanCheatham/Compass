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
2. Create `.compass/` next to your code (and add it to `.gitignore`).
3. Start the web UI on a local port and print the URL.
4. Idle until you submit a draft plan from the UI.
5. From there: Plan refines → Develop implements → repeat.

Press Ctrl+C to stop. Run `compass status` at any time to print the current `state.md` and `drafts.md`.

## Architecture

### Two agents

**Plan** — read-only over the codebase, plus edit access to three files in `.compass/`.
- Reads `state.md`, `drafts.md`, `feedback.md` and the codebase.
- Refines drafts, integrates them into `state.md`, picks the next concrete plan.
- Clears `drafts.md` and `feedback.md` after consuming them.
- Calls `signal_done` when there's nothing left to do.

**Develop** — full read/write over the codebase.
- Implements the `Next` block from `state.md`.
- Commits changes (creates new commits with `git add` + `git commit`).
- Writes notes for the next Plan run into `feedback.md`.

### State

Everything lives in `.compass/` inside your repo (gitignored, per-repo):

```
{repo}/.compass/
├── state.md      # Plan owns. Single source of truth.
├── drafts.md     # User owns (via UI). Plan consumes and clears.
└── feedback.md   # Develop owns. Plan reads and clears.
```

`state.md` always has exactly this structure:

```
## Completed
- One-line summary per shipped iteration

## Next
The single concrete plan Develop will implement next.

## Follow-up
A short sketch of what should come after Next.
```

### Loop

1. If `drafts.md` and `state.md`'s `Next` are both empty, **idle** until a draft arrives.
2. **Plan** runs: refines drafts, updates `state.md`, clears drafts/feedback. May call `signal_done`.
3. **Develop** runs against `Next`: implements, commits, writes `feedback.md`.
4. Back to step 1.

When `signal_done` fires, the loop drops back into idle. Adding a new draft from the UI wakes it up.

## UI

- **Activity** — live stream of agent output and tool calls.
- **State** — current `state.md` (Completed / Next / Follow-up).
- **Drafts** — submit a draft plan; see what's pending.
- **Feedback** — what Develop wrote at the end of the last iteration.

## Technology

- **Runtime**: Claude Agent SDK (TypeScript)
- **Tools**: MCP for the single `signal_done` tool exposed to Plan
- **VCS**: Git (Develop creates commits via standard git CLI)
- **UI**: Plain HTML + WebSocket stream of agent activity

## Non-Goals

- Multi-repo orchestration (one impl repo per Compass instance)
- Audit trail beyond what git already provides
- Auto-revert of bad commits (use `git` directly if needed)
- Persistent vision document (drafts are how you steer)
