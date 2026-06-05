# 00 - Pain Driven Productization Architecture

## Objective

Reframe Compass around user pain rather than product ideas.

Compass should take a rough pain statement, discover possible product directions,
build isolated Rust desktop prototypes, collect pain-relief evidence, and decide
which direction deserves more investment.

This plan establishes the epic boundary and vocabulary. Later plans implement
the state model, discovery prompts, experiment branches, generated Rust
contracts, evidence runner, planning loop, UI, and rollout.

## Product Bet

Users often know the pain before they know the product. Asking for a product
idea pushes Compass to implement the user's first guess. Asking for user pain
lets Compass act more like a product partner:

- clarify who hurts and when
- model the current workflow and alternatives
- generate multiple solution hypotheses
- build small executable probes
- pressure-test those probes with skeptical scenarios
- promote only the direction with evidence

Productization evidence replaces the old app-fit simulation framing. Evidence
becomes one input inside a larger productization loop rather than the whole
product model.

## Target Architecture

Compass should introduce these concepts:

- Pain hypothesis: the durable problem statement and its operating context.
- User segment: a group that experiences the pain in a specific way.
- Current workflow: what users do today, including tools, handoffs, and coping
  mechanisms.
- Alternative: a direct tool, spreadsheet, manual process, internal workaround,
  or decision to do nothing.
- Solution hypothesis: a product bet that might relieve the pain.
- Product experiment: a branch, worktree, prototype scope, and evidence trail for
  one solution hypothesis.
- Evidence run: deterministic or model-backed simulation output tied to a
  branch and commit.
- Product decision: continue, narrow, pivot, kill, or promote.

## Loop Shape

```text
Discover
  Input: raw user pain, repository state, previous evidence
  Output: pain model, solution hypotheses, experiment candidates

Plan
  Input: productization state and evidence
  Output: one commit-sized implementation or experiment-management slice

Develop
  Input: one experiment branch/worktree and immediate handoff
  Output: verified Rust prototype commits

Simulate
  Input: verified experiment commit and scenario cohort
  Output: deterministic traces, persona feedback, evidence summaries

Reflect
  Input: session history, evidence, branch state
  Output: continue, narrow, pivot, kill, promote, or plan next increment
```

## Compass Boundary

Generated apps remain Rust-only. Compass itself remains a native Swift/macOS app
with a Rust engine sidecar.

The first epic should not introduce external product analytics, live SaaS
integrations, hosted deployments, or real customer interviews. It should produce
local executable product experiments with auditable evidence.

## Non-Goals

- Do not preserve the old product-first simulation schema when it blocks a
  cleaner pain model.
- Do not run multiple mutating agents on the same branch.
- Do not promote an experiment just because Verify passed.
- Do not make subjective persona feedback a hard test failure.
- Do not require a final production-ready app before evidence can be collected.
- Do not add external collaboration or cloud sync in this epic.

## Likely Files

- `Sources/Compass/ProductizationModels.swift`
- `Sources/Compass/ProductizationEvidence.swift`
- `Sources/Compass/ProductizationSimulationRunner.swift`
- `Sources/Compass/Workspace.swift`
- `Sources/Compass/CompassProject+RunPasses.swift`
- `Sources/Compass/Prompts/`
- `Sources/Compass/RustProjectScaffold.swift`
- `Sources/Compass/SharedVM/Workspace/`
- `Sources/Compass/Views/`
- `Sources/Compass/Resources/Schemas/`
- `crates/compass-engine/src/scaffold.rs`

## Acceptance Criteria

- The epic has a clear pain-driven vocabulary.
- The implementation plans are ordered and independently executable.
- Productization simulation is explicitly scoped as evidence, not the whole
  product model.
- Experiment branches and worktrees are treated as first-class architecture.
- The generated Rust contract remains deterministic and serializable.

## Verification

- Read every file in `docs/plans/`.
- Confirm the plan set starts from pain and ends with promotion or archive.
- Confirm every plan includes acceptance criteria and verification guidance.

## Status

Complete on 2026-06-04.

The architecture vocabulary and plan sequence are established. Plans 01-07
implemented the pain-driven productization state, discovery contract,
experiment worktrees, generated Rust productization contract, evidence storage,
Plan/Reflect feedback loop, and rollout workbench. Plan 08 is the next
follow-up for git-backed promotion/archive operations.
