# 07 - UI Promotion And Rollout

## Objective

Make pain-driven productization visible and operable in the Compass UI, then add
the promotion/archive workflows that turn experiment results into product
direction.

This plan ties the epic together.

## Scope

Implement UI surfaces, promotion/merge actions, archive actions, migration
behavior, documentation, and end-to-end smoke tests.

## UI Surfaces

Add or reshape UI around:

- Pain Map: active pain hypotheses, user segments, current workflows, and
  alternatives.
- Solution Board: solution hypotheses grouped by status.
- Experiment Board: branch, worktree, latest commit, latest Verify, latest
  evidence, and current decision.
- Evidence View: scenario runs, verdict distribution, repeated objections,
  missing capabilities, current-alternative comparison, and trace artifacts.
- Decision Timeline: continue, narrow, pivot, kill, promote, and why.

Avoid turning this into a marketing dashboard. The UI should feel like a dense
desktop product workbench.

## Promotion Workflow

Promotion should be explicit:

```text
1. User or Reflect marks an experiment as promotion-ready.
2. Compass verifies the experiment branch.
3. Compass shows evidence summary, branch diff, and risk notes.
4. User confirms promotion.
5. Compass merges or fast-forwards into the accepted product branch.
6. Compass records a ProductDecision with commit ids and evidence ids.
```

Start with fast-forward or normal merge. Add squash only if Explore and session
history can still explain the product lineage.

## Archive Workflow

Killing or parking an experiment should:

- mark the solution or experiment as rejected or parked
- keep evidence available
- stop automatic simulation runs
- optionally move the branch to `compass/archive/<solution-slug>`
- preserve the worktree until the user deletes it

Do not delete branches automatically.

## Rollout And Migration

Breaking changes are allowed, and legacy PMF compatibility is intentionally
removed:

- New projects seed `productization.json`.
- Old PMF config, evidence stores, prompt schemas, and UI surfaces are removed
  rather than maintained in parallel.
- Old PMF evidence is not injected into prompts.
- The plan docs should state that productization evidence replaces PMF.

## End-To-End Smoke

Create a smoke path:

```text
1. Start from raw pain.
2. Run Discover.
3. Create two solution hypotheses.
4. Create two experiment branches.
5. Build one generated Rust prototype.
6. Run verify and productization-smoke.
7. Run one evidence simulation.
8. Reflect updates experiment decision.
9. Promote or archive through the UI.
```

## Likely Files

- `Sources/Compass/Views/`
- `Sources/Compass/ProjectIntakeGuide.swift`
- `Sources/Compass/PlanWorkflowOverview.swift`
- `Sources/Compass/PlanSessionHistoryGuide.swift`
- `Sources/Compass/NativeFeedbackService.swift`
- `Sources/Compass/CompassProject+RunControl.swift`
- `Sources/Compass/Workspace.swift`
- `Sources/Compass/SharedVM/Workspace/`
- `README.md`
- `docs/plans/`

## Acceptance Criteria

- Users can enter pain and inspect the resulting pain/productization model.
- Users can see active solution hypotheses and experiment branches.
- Users can run or inspect simulations per experiment commit.
- Users can promote or archive experiments with an evidence-backed decision.
- Legacy PMF-specific UI language, code paths, prompt schemas, and generated
  command aliases are removed or replaced with productization evidence.
- The end-to-end smoke can be performed without hidden manual file edits.

## Verification

- Run Swift test suite or focused UI/model tests.
- Run Rust engine tests after scaffold changes.
- Run a generated Rust workspace smoke:

```bash
cargo run -p xtask -- verify
cargo run -p xtask -- productization-smoke
cargo run -p xtask -- visual-verify
```

- Manually inspect one full productization flow in the app.
- Confirm no prompt injects raw transcripts by default.

## Status

Complete on 2026-06-04.

Implementation notes:

- Added project-level productization evidence loading helpers for the rollout
  workbench.
- Added a Productization workbench tab with Pain Map, Solution Board,
  Experiment Board, Evidence View, promotion/archive controls, scenario run
  detail, copyable evidence summaries, and Decision Timeline.
- Added promotion/archive rollout state transitions that record branch names,
  before/after commit ids, evidence run ids, solution status changes, and
  product decisions.
- User clarified that backwards compatibility is not required, so this plan now
  removes legacy PMF code instead of reframing it.
- Removed legacy PMF models, evidence store, runner, prompt schemas, prompt
  injection, generated `pmf-smoke`/`pmf_experience` aliases, and the PMF tab.
- Updated README and plan docs so productization evidence replaces the old PMF
  vocabulary.
- Added `docs/plans/08-git-backed-promotion-and-archive.md` as the next
  increment for actual branch merge/archive-ref operations. Plan 07 records and
  exposes evidence-backed rollout decisions; Plan 08 will make those decisions
  mutate git history deliberately.

Verification completed and passed:

```bash
./scripts/test-local.sh --filter ProductizationEvidenceStoreTests
./scripts/test-local.sh --filter ProductizationLoopTests
./scripts/test-local.sh --filter ProductizationConfigTests
./scripts/test-local.sh --filter ProductizationSimulationRunnerTests
./scripts/test-local.sh --filter PromptSchemaLoadingTests
./scripts/test-local.sh --filter RustProjectScaffoldTests
./scripts/test-local.sh --filter CompassWorkspaceStorageMigrationTests
./scripts/test-local.sh --filter RustVerifyCommandsTests
./scripts/test-rust-engine.sh
```
