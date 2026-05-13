# Testing Strategy

Tests should pin behavior at the cheapest level that catches realistic regressions. Unit tests are excellent for pure parsing, persistence normalization, prompt rendering, and utility functions. Integration tests should cover contracts between agents, runner state, Git, and the local workspace.

## What To Test

- Pure functions: edge cases, invalid inputs, ordering, and truncation behavior.
- Persistence: corrupt files, missing files, older schema shapes, atomic write expectations, and flush behavior.
- Runner contracts: Plan setting state, Develop setting feedback, completion signaling, verify failures, clean-tree enforcement, cancellation, and approval gates.
- Git behavior: use real temporary repositories for worktree, merge, commit, and status checks.

## Test Shape

- Prefer deterministic fake agents over live model calls.
- Keep fake agents narrow: return explicit states, feedback, and success/failure outcomes.
- Use `node:test` with `node:assert/strict`.
- Use `spawnSync` or `execFile`-style APIs for setup commands; avoid shell interpolation.
- Add timeouts around subprocess tests so failures do not strand child processes.
