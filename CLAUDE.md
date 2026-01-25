# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Compass is a recursive iteration tool for project development that wraps Claude Code CLI. It follows a "plan, document, build, repeat" workflow where complex plans are broken down into smaller atomic plans in a tree structure.

## Core Concepts

- **NORTH.md**: Source of truth for project description, theme, and goals
- **SOUTH.md**: Tracks legacy, obsolete, or abandoned parts of the system (vestigial code to be removed)
- **plans/**: Hierarchical directory of implementation plans, nested when plans need decomposition
- **docs/**: Project documentation including architecture.md

## Compass Workflow Loop

1. Read SOUTH.md to identify vestigial code for removal
2. Read NORTH.md for project goals and direction
3. Reconcile North/South against docs/architecture.md; create migration plans if architecture is outdated
4. Execute plans in priority order, updating docs and creating/modifying plans as needed
5. Verify changes against NORTH.md and SOUTH.md to ensure alignment

## Project Structure

```
.compass/
├── NORTH.md          # Project goals and direction
├── SOUTH.md          # Deprecated/legacy tracking
├── plans/            # Implementation plans (can nest)
│   ├── plan-1.md
│   ├── plan-2.md
│   └── plan-2/       # Sub-plans for plan-2
│       └── plan-1.md
└── docs/
    └── architecture.md
```
