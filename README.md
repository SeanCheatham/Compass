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

Press Ctrl+C to stop. Run `compass status` at any time to print the current `state.json` and `drafts.md`.

## Architecture

### Two agents

**Plan** — read-only over the codebase, plus edit access to one file: `.compass/state.json`.
- Reads `state.json` and snapshots of `drafts.md` / `feedback.md` provided by the runner.
- Refines drafts, picks the next concrete plan, picks a `verify` command for it.
- Sets `next` to `null` when there is no concrete next step. The runner idles and waits for drafts.

**Develop** — full read/write over the codebase.
- Implements `state.json`'s `next.plan`.
- Iterates until `next.verify` exits 0.
- Commits changes (creates new commits with `git add` + `git commit`).
- Writes notes for the next Plan run into `feedback.md`.

After Develop finishes, the runner enforces two post-checks:
1. The `verify` command from `next` must exit 0.
2. `git status --porcelain` must be empty (everything committed or gitignored).

If either fails, the runner re-prompts Develop with the failure (up to 3 attempts) before
yielding to Plan.

### State

Everything lives in `.compass/` inside your repo (gitignored, per-repo):

```
{repo}/.compass/
├── state.json    # Plan owns. Structured single source of truth.
├── drafts.md     # User owns (via UI). Runner snapshots+clears before Plan runs.
└── feedback.md   # Develop owns. Runner snapshots+clears before Plan runs.
```

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

1. If `drafts.md` is empty and `state.json`'s `next` is null, **idle** until a draft arrives
   (the runner watches `.compass/` for changes).
2. The runner snapshots `drafts.md` and `feedback.md` (atomic `rename`, race-free with new
   user input).
3. **Plan** runs against the snapshots; updates `state.json`. May call `signal_done`.
4. **Develop** runs against `next.plan`: implements, runs `next.verify`, commits, writes
   `feedback.md`.
5. Runner runs verify + `git status --porcelain` post-checks. Re-prompts Develop on failure.
6. Back to step 1.

There is no separate "done" signal. Idle is the universal exit case: empty drafts and `next == null` send the runner back to step 1. Same path the bootstrap (fresh repo) takes.

## UI

- **Activity** — live stream of agent output and tool calls.
- **State** — Completed list, current `Next` (with verify command), and `Follow-up`.
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
