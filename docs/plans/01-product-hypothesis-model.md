# 01 - Pain And Productization State Model

## Objective

Replace the product-first PMF model with a pain-driven productization model.

The new state should preserve the durable pain, track multiple solution bets,
bind experiments to branches, and store decisions without assuming that the
first generated app is the right product.

## Scope

Implement the Swift models, storage, seeding, prompt digest, and basic tests for
productization state.

This plan may make breaking changes to `.compass/pmf.json`. Prefer renaming the
storage file to `.compass/productization.json` over keeping a misleading PMF
name.

## Data Model

Introduce `ProductizationConfig` with schema version 1:

```text
schemaVersion
rawPain
painHypotheses
userSegments
currentWorkflows
alternatives
solutionHypotheses
experiments
scenarioCohorts
decisions
```

### PainHypothesis

Fields:

- `id`
- `title`
- `rawPain`
- `targetSituation`
- `painFrequency`
- `painSeverity`
- `costOfInaction`
- `successSignals`
- `unknowns`
- `status`
- `createdAt`
- `updatedAt`

`status` values:

- `draft`
- `active`
- `reframed`
- `resolved`
- `parked`

### UserSegment

Fields:

- `id`
- `painID`
- `name`
- `role`
- `context`
- `goals`
- `constraints`
- `currentWorkflowIDs`
- `alternativeIDs`
- `decisionCriteria`
- `skepticism`

### CurrentWorkflow

Fields:

- `id`
- `painID`
- `title`
- `steps`
- `tools`
- `handoffs`
- `failureModes`
- `workarounds`
- `estimatedCost`

### Alternative

Fields:

- `id`
- `painID`
- `title`
- `kind`
- `strengths`
- `weaknesses`
- `switchingCost`

`kind` values:

- `manual`
- `spreadsheet`
- `existing_tool`
- `internal_workaround`
- `outsourced`
- `do_nothing`

### SolutionHypothesis

Fields:

- `id`
- `painID`
- `title`
- `promise`
- `workflowBet`
- `targetSegmentIDs`
- `differentiator`
- `whyThisCouldWin`
- `whyThisMightFail`
- `requiredProof`
- `status`

`status` values:

- `candidate`
- `active`
- `promoted`
- `rejected`
- `parked`

### ProductExperiment

Fields:

- `id`
- `solutionID`
- `title`
- `branchName`
- `worktreeID`
- `baseSha`
- `currentSha`
- `prototypeScope`
- `scenarioCohortIDs`
- `evidenceSummary`
- `decision`
- `createdAt`
- `updatedAt`

`decision` values:

- `not_run`
- `continue`
- `narrow`
- `pivot`
- `kill`
- `promote`

### ProductDecision

Fields:

- `id`
- `experimentID`
- `decision`
- `summary`
- `evidenceRunIDs`
- `decidedAt`
- `decidedBy`

## Storage

Preferred layout:

```text
.compass/
  productization.json
  productization/
    evidence-index.json
    runs/
    decisions/
```

Breaking replacement behavior:

- If `productization.json` exists, read it.
- If only `pmf.json` exists, do not silently map it to the new model.
- Treat old PMF state as superseded and seed fresh productization state from
  current project pain instead of keeping a compatibility layer.
- Seed a new pain model from `COMPASS.md`, drafts, or direct user intake.

## Prompt Digest

Expose a bounded prompt digest that includes:

- active pain hypotheses
- active solution hypotheses
- active experiments and branches
- latest decision per experiment
- unresolved unknowns
- top evidence signals and objections

Do not inject raw transcripts into Plan or Reflect.

## Likely Files

- `Sources/Compass/ProductizationModels.swift`
- `Sources/Compass/ProductizationPlanningDigest.swift`
- `Sources/Compass/ProductizationEvidence.swift`
- `Sources/Compass/Workspace.swift`
- `Sources/Compass/CompassProject+Workspace.swift`
- `Sources/Compass/Resources/Schemas/`
- tests for model decoding, cleaning, seeding, and prompt digest

## Acceptance Criteria

- Compass can seed productization state from a raw pain statement.
- Multiple solution hypotheses can point at one pain hypothesis.
- Experiments can reference branch/worktree identities before those branches are
  created.
- Old PMF state no longer defines the product model.
- Prompt digests are bounded and omit raw transcripts.

## Verification

- Run focused Swift tests for productization model decoding and seeding.
- Confirm `.compass/productization.json` round-trips through JSON encoding.
- Confirm empty or missing state seeds from the project pain without crashing.
- Confirm old `pmf.json` does not get silently treated as current state.

## Status

Complete.

Completed on 2026-06-04. Implemented productization-native Swift state in
`Sources/Compass/ProductizationModels.swift`, including `ProductizationConfig`,
pain hypotheses, user segments, current workflows, alternatives, solution
hypotheses, product experiments, scenario cohorts, and product decisions.

Added `.compass/productization.json` read/write support and
`.compass/productization/` directory initialization through `CompassWorkspace`.
Project refresh now seeds productization state from project pain/vision/drafts
and does not silently treat superseded `.compass/pmf.json` state as the current
product model.

Plan and Reflect prompts now receive a bounded productization digest covering
active pain, active/candidate solutions, experiment branches/worktrees,
decisions, unknowns, and summarized evidence signals/objections without raw
transcripts. Later rollout work removed the superseded PMF configuration,
evidence store, prompt schemas, simulation runner, and UI surface.

Focused tests in `Tests/CompassTests/ProductizationConfigTests.swift` cover
round trip storage, missing file, malformed file, unsupported schema version,
seed defaults, unique seeded ids, project refresh seeding, project save/reload,
and old PMF state not being silently treated as current productization state.

Verification completed and passed:

```bash
./scripts/test-local.sh --filter ProductizationConfigTests
./scripts/test-local.sh --filter ProductizationEvidenceStoreTests
```
