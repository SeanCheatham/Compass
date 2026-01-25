# Compass

Compass is a recursive iteration tool for project development that wraps Claude Code CLI. It follows a "plan, document, build, repeat" workflow where complex plans are broken down into smaller atomic plans in a tree structure.

## Installation

```bash
npm install
npm run build
npm link  # Makes 'compass' available globally
```

## Quick Start

```bash
# Initialize Compass in your project
compass init

# Edit NORTH.md with your project goals
# Edit SOUTH.md with anti-patterns to avoid
# Create plans in .compass/plans/

# Start autonomous execution
compass run

# Check current status
compass status
```

## Project Structure

```
your-project/
├── NORTH.md              # Project goals and direction (source of truth)
├── SOUTH.md              # Anti-patterns, legacy code to remove
└── .compass/
    ├── plans/            # Implementation plans (can nest)
    │   ├── plan-1.md
    │   ├── plan-2.md
    │   └── plan-2/       # Sub-plans for plan-2
    │       └── plan-1.md
    ├── docs/
    │   └── architecture.md
    ├── state.json        # Execution state (auto-generated)
    └── compass.log       # Execution log
```

## Core Concepts

### NORTH.md
The source of truth for your project. Define:
- Project description and goals
- Theme and guiding principles
- Success criteria

### SOUTH.md
Track what to avoid or remove:
- Anti-patterns
- Legacy code marked for removal
- Technical debt

### Plans
Markdown files in `.compass/plans/` that describe work to be done:

```markdown
# Plan: Feature Name

## Status
pending | in_progress | completed | blocked

## Priority
high | medium | low

## Dependencies
- ./other-plan.md

## Description
What this plan aims to accomplish.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
```

Plans can be nested in directories for decomposition. A plan `plan-2.md` with sub-plans would have a `plan-2/` directory containing its child plans.

## Compass Loop

1. **Check Direction** - Compare NORTH.md and SOUTH.md against shadow copies to detect developer intent changes
2. **Reconcile** - If direction changed, reconcile architecture.md with the new direction
3. **Build Tree** - Parse all plans into a prioritized tree structure
4. **Select Plan** - Use Claude to select the next leaf plan to execute
5. **Execute** - Run the plan via Claude Code CLI
6. **Commit** - Auto-commit code and doc changes together
7. **Repeat** - Go back to step 1

## CLI Commands

### `compass init`
Initialize Compass in the current directory. Creates:
- `NORTH.md` - Project direction template
- `SOUTH.md` - Anti-patterns template
- `.compass/` - Compass working directory

Options:
- `--force` - Overwrite existing .compass directory

### `compass run`
Start the autonomous execution loop.

Options:
- `-n, --max-iterations <number>` - Limit iterations
- `--dry-run` - Show status without executing

### `compass status`
Display current plan tree, statistics, and execution history.

## Requirements

- Node.js 18+
- Claude Code CLI installed and authenticated
- Git (for auto-commit functionality)

## Design Decisions

- **Clean workspace required**: `compass run` fails if git has uncommitted changes
- **Auto-commit**: Each plan execution commits changes together
- **Failure stops loop**: Failed plans stop execution for investigation
- **Separation of concerns**: Claude Code only modifies project code, never `.compass/`
- **Decomposition**: Complex plans can signal the need to be broken down into sub-plans

## Development

```bash
# Install dependencies
npm install

# Build
npm run build

# Watch mode
npm run dev

# Run locally
node dist/index.js
```
