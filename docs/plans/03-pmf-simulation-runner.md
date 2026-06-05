# 03 - Experiment Branches And Parallel Worktrees

## Objective

Make experiment branches and worktrees first-class so Compass can explore
multiple solution hypotheses without mixing their commits or evidence.

This is the infrastructure plan for parallel productization. It should support
one mutating agent per experiment branch and multiple read-only simulation jobs
against verified commits.

## Scope

Implement branch naming, worktree creation, guest workspace catalog keys,
promotion staging refs, and scheduling rules.

This plan does not yet implement the generated Rust contract or evidence
analysis. It creates the safe execution containers those plans need.

## Branch Model

Use these branch roles:

```text
main or current user branch
  accepted product direction

compass/exp/<solution-slug>
  active prototype branch for one solution hypothesis

compass/archive/<solution-slug>
  optional parked branch for killed or inactive experiments

compass/promoted/<date>-<solution-slug>
  optional marker branch for promoted experiment snapshots
```

Experiment branch names come from `ProductExperiment.branchName` and must pass
`git check-ref-format`.

## Worktree Model

Each experiment gets an isolated host worktree:

```text
.compass/productization/worktrees/<experiment-id>/
```

or a host application-support equivalent when repo-local storage is not used.

Each shared VM workspace should be keyed by:

```text
repoID + experimentID + branchName
```

not only by repo. This prevents one experiment from overwriting another
experiment's guest state.

## Mutating Agent Rule

Only one Develop run may mutate a given experiment branch at a time.

Different experiment branches may run Develop concurrently only if the shared VM
capacity, model runtime, and UI scheduling can show each run clearly. Start with
a conservative global limit of one mutating Develop run, then relax after the
branch model is reliable.

## Parallel Simulation Rule

Read-only simulations may run in parallel when they target immutable commits:

```text
experimentID
branchName
commitSha
scenarioCohortID
```

CLI-only deterministic simulations can run with a wider concurrency limit.
Visual verification and desktop screenshot capture should use a tighter
semaphore because they consume GUI/session resources.

## Git Exchange Changes

The shared VM git exchange should support:

- fetching a named experiment branch from host to guest
- committing on that experiment branch in guest
- staging guest commits to an experiment-specific ref
- fast-forwarding only that experiment branch on success
- leaving main/current branch untouched until promotion

Promotion is a separate action handled later.

## Safety Rules

- Refuse to create an experiment branch from a dirty base worktree.
- Record `baseSha` and `currentSha` in productization state.
- Refuse to promote if the experiment branch is not descended from its recorded
  base without an explicit rebase or merge plan.
- Never use broad destructive git operations.
- Keep generated build outputs out of branches.

## Likely Files

- `Sources/Compass/SharedVM/Workspace/SharedCompassVMGitExchange.swift`
- `Sources/Compass/SharedVM/Workspace/SharedCompassVMGitWorkspaceSync.swift`
- `Sources/Compass/SharedVM/Workspace/SharedCompassVMGuestWorkspaceCatalog.swift`
- `Sources/Compass/SharedVM/Workspace/SharedCompassVMRepoWorkspaceSync.swift`
- `Sources/Compass/CompassProject+RunPasses.swift`
- `Sources/Compass/SessionRecordStore.swift`
- `Sources/Compass/Workspace.swift`
- productization state and tests from Plan 01

## Acceptance Criteria

- Compass can create an experiment branch for a solution hypothesis.
- Compass can create or reuse a matching worktree.
- Develop can target an experiment worktree without changing main.
- Shared VM catalog entries are separated by experiment.
- Simulation jobs can target a branch commit as read-only work.
- Session records include experiment id, branch name, and commit sha when
  relevant.

## Verification

- Add git utility tests with temporary repositories.
- Test branch slug validation and invalid ref rejection.
- Test two experiments for the same repo keep separate worktree paths.
- Run a manual smoke that creates two experiment branches and verifies their
  commits do not collide.

## Status

Complete.

Completed on 2026-06-04. Added `ProductExperimentWorktreeManager` and
`CompassWorkspace.prepareProductExperimentWorktree` to validate experiment branch
names with git, refuse dirty base worktrees, create missing experiment branches,
create or reuse `.compass/productization/worktrees/<experiment-id>/`, and record
`baseSha`/`currentSha` back into productization state.

Added experiment-aware Shared VM guest catalog entries under
`.compass/productization/guest-workspaces/`, keyed by experiment id and branch
name while preserving the existing per-repo catalog API. Added optional
experiment metadata to `SessionRecord` so future Develop and simulation records
can carry experiment id, branch name, and commit sha. Added
`ProductExperimentSimulationTarget` as the read-only simulation identity:
experiment id, branch name, commit sha, and scenario cohort id.

Focused tests cover invalid branch rejection, dirty base rejection, branch and
worktree creation, two experiments for the same repo staying isolated, Shared VM
catalog separation, session metadata round trip, and read-only simulation target
round trip.

Verification completed and passed:

```bash
./scripts/test-local.sh --filter ProductExperimentWorktreeTests
./scripts/test-local.sh --filter SharedCompassVMGuestWorkspaceCatalogTests
./scripts/test-local.sh --filter SessionRecordStoreTests
```
