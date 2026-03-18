# Compass

Compass is a recursive iteration tool for autonomous end-to-end project development. It wraps the Claude Agent SDK to orchestrate a Product Manager (PM) agent and Developer agent that collaborate to build complete projects from a high-level specification.

## Vision

Enable "vibe coding" at the project level. A human provides a vision in COMPASS.md, and Compass iteratively builds the entire project — planning, implementing, committing, and adapting — until the vision is realized.

## Architecture

### Two-Agent Model

**PM Agent** — Orchestration and planning

- Receives COMPASS.md (human's vision) and plan.json (current state) via system prompt
- Maintains detailed near-term plans, coarse far-term plans
- Directs Developer via streaming I/O: exploration or implementation
- Answers Developer questions during sessions
- Decides session outcome: commit changes or replan
- Updates plans based on learnings
- **Tools**: Only Compass MCP tools — no Read/Write/Edit/Bash (must use Developer)

**Developer Agent** — Exploration and implementation

- Fresh context each session (no accumulated state)
- PM's "hands and eyes" in the codebase
- Explores codebase when PM needs context
- Implements tasks when PM directs
- Has full code tools (Read, Write, Edit, Bash, Glob, Grep)
- Streams questions to PM, receives guidance

### Compass CLI

The thin execution layer that:

- Launches PM + Developer agents together (always paired)
- Connects their streaming I/O for bidirectional communication
- Executes PM tool calls (git operations, plan updates)
- Runs the main iteration loop until project completion

## State Management

### Impl Repo (user's project)

```
~/code/my-app/
├── COMPASS.md      # human-owned vision and goals
├── README.md       # developer-maintained project docs
└── src/            # implementation
```

### Compass Workspace

```
~/.compass/{sanitized-repo-path}/
├── config.yaml     # compass configuration
├── plan.json       # structured plan (compass-managed)
├── notes.md        # PM scratchpad for cross-session learnings
└── sessions/       # session summaries
    └── {plan_id}-{timestamp}.md
```

## Plan Structure

Plans are stored as JSON with deterministic hash IDs (first 6 chars of SHA-256 of content):

```json
{
  "plans": [
    {
      "id": "f8a3c1",
      "content": "Set up TypeScript project with build configuration",
      "status": "completed",
      "commit": "a7b3c9d",
      "session": "f8a3c1-1706012400.md"
    },
    {
      "id": "b2d4e6",
      "content": "Implement user authentication with JWT",
      "status": "pending",
      "commit": null,
      "session": null
    }
  ]
}
```

Note: Plans completed via `replan` have a session but no commit.

Plans are managed via MCP tools, not direct file editing:

- `list_plans` — view current plans with IDs and status
- `insert_plan` / `insert_plans` — add plans after a given ID
- `remove_plan` — remove a plan by ID
- `set_plan_status` — update plan status

**Sequential execution**: Plans must be completed in order. The PM always works on the first pending plan. To skip ahead or reorder, PM must modify the plan list first (remove, insert, reorder). This keeps plan.json as the authoritative queue.

## PM MCP Tools

| Tool | Purpose |
|------|---------|
| `list_plans` | View current plan state |
| `insert_plan` | Add a new plan after a given ID |
| `insert_plans` | Batch insert for task decomposition |
| `remove_plan` | Remove a plan by ID |
| `set_plan_status` | Update plan status |
| `write_notes` | Update PM notes |
| `end_session` | End session with outcome (see below) |

**Completion**: Project is complete when no pending plans remain. Empty plan list on first launch triggers initial planning.

### `end_session` Tool

Ends the current session with one of three outcomes:

**Commit** — `end_session(outcome="commit", summary="...")`

- Spawns ephemeral "committer" agent to create commit with appropriate message
- Links commit SHA to the completed plan
- Writes session summary (from `summary` field)
- Disallows plan mutations (only current plan status is updated)

**Replanned** — `end_session(outcome="replanned", summary="...")`

- Resets working tree (discards any impl changes)
- Allows plan mutations made during session to persist
- Writes session summary
- Use when PM adjusted plans without implementing

**Revert** — `end_session(outcome="revert", revert_to="<plan_id or commit>", reason="...")`

- Reverts impl repo to the specified commit (or commit associated with plan ID)
- Resets all plans after that point to pending (clears session/commit fields)
- Resets session history to that point
- Stores reason as context for next iteration

## Session Flow

1. Compass launches PM + Developer together (streaming I/O connected)
2. PM receives system prompt with COMPASS.md, plan.json, notes.md, and recent session summaries
3. PM may direct Developer to explore codebase for context
4. PM decides: implement first pending plan, or adjust plans first
5. PM directs Developer as needed, ends session with `end_session`:
   - **commit** — impl changes committed, plan marked completed (no plan mutations)
   - **replanned** — plan mutations persist, impl changes discarded
   - **revert** — revert to checkpoint, reset plans/sessions since that point
6. Loop continues until no pending plans remain

## Session Summaries

Each session produces a summary capturing:

- Plan ID and task description
- Outcome type (commit, replanned, or revert)
- Commit SHA (new for commit, current for replanned, reverted-to for revert)
- Key decisions and learnings

Summaries are injected as context for future PM sessions, providing institutional memory without full conversation history.

On **replan**, the PM captures relevant learnings in the reason field before sessions are reset. This ensures knowledge from failed attempts persists even though code and plan state are rewound. Any session summaries since the revert commit will also be reset, so the PM should capture any relevant learnings in the reason field before calling `end_session`.

## Technology

- **Runtime**: Claude Agent SDK (TypeScript)
- **Tools**: MCP (Model Context Protocol) for custom tool definitions
- **VCS**: Git for checkpointing and rollback
- **Models**: Claude for both PM and Developer agents

## Installation

### Local Installation

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
echo "# My Project\n\nBuild a CLI tool that..." > COMPASS.md
compass
```

Compass will:

1. Create workspace at `~/.compass/home-user-code-my-project/`
2. Initialize plan.json from COMPASS.md
3. Begin iterative development loop
4. Continue until project matches the vision

## Non-Goals

- Real-time collaboration (single-user tool)
- IDE integration (CLI-first)
- Multi-repo orchestration (single impl repo per compass instance)
- Preserving conversation history (uses summaries instead)
