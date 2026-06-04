# 01 - Product Hypothesis Model

## Objective

Create Compass-owned data models and storage for product hypotheses, personas,
and PMF tasks. This gives persona simulations a concrete product context instead
of generic "try this app" prompts.

## Scope

Add model types and persistence only. Do not build the simulation runner yet.

## Data Model

Add Codable, Equatable, Sendable models for:

- `ProductHypothesis`
- `PMFPersona`
- `PMFTask`
- `PMFScenario`
- `PMFScenarioCohort`

Suggested `ProductHypothesis` fields:

- `id`
- `title`
- `targetUser`
- `jobToBeDone`
- `pain`
- `promise`
- `currentAlternatives`
- `successCriteria`
- `pricingAssumptions`
- `switchingAssumptions`
- `knownRisks`
- `createdAt`
- `updatedAt`

Suggested `PMFPersona` fields:

- `id`
- `name`
- `role`
- `context`
- `goals`
- `constraints`
- `currentWorkflow`
- `skepticism`
- `decisionCriteria`
- `technicalComfort`

Suggested `PMFTask` fields:

- `id`
- `title`
- `situation`
- `desiredOutcome`
- `startingContext`
- `successSignals`
- `failureSignals`
- `maxTurns`

Suggested `PMFScenario` fields:

- `id`
- `title`
- `hypothesisID`
- `personaID`
- `taskID`
- `seed`
- `enabled`
- `tags`

## Storage

Persist project-local PMF configuration under `.compass/` with the same care as
existing Compass state.

Suggested file:

```text
.compass/pmf.json
```

Suggested shape:

```json
{
  "schemaVersion": 1,
  "hypotheses": [],
  "personas": [],
  "tasks": [],
  "scenarios": []
}
```

Use atomic writes where existing Compass storage helpers do. Preserve unknown
future fields only if the surrounding storage layer already has a pattern for
that; otherwise keep schema versioning explicit and simple.

## UI Entry Point

Add a minimal project-facing affordance only if it can be done cheaply:

- A "PMF" or "Product" document/tab entry.
- Read-only summaries are enough for this plan.
- Full editing can be basic text fields or deferred if the runner can use
  seeded defaults.

Do not overbuild UI before the runner proves useful.

## Seed Defaults

When a project has no PMF config, Compass should be able to create starter
content from existing project vision/intake information:

- one product hypothesis
- three personas
- two PMF tasks
- a small scenario cohort

Make defaults editable and project-specific. Avoid generic praise-friendly
personas.

## Likely Files

- `Sources/Compass/Models.swift`
- `Sources/Compass/CompassProject+Storage.swift`
- `Sources/Compass/ProjectVisionGuide.swift`
- `Sources/Compass/Views/`
- `Tests/CompassTests/`

## Acceptance Criteria

- PMF config can be loaded for a project.
- Missing config produces a valid empty or seeded config.
- Config can be saved and reloaded without data loss.
- Model decoding rejects or handles unsupported schema versions clearly.
- Unit tests cover round trip, missing file, malformed file, and seed defaults.

## Verification

Run:

```bash
./scripts/test-local.sh
```

If SwiftPM tests are enough for the touched files, also run:

```bash
swift test
```

Record any intentionally skipped UI work in the plan file before moving on.

## Completion

Status: Complete.

Completed on 2026-06-04. Implemented Compass-owned PMF configuration models in
`Sources/Compass/PMFModels.swift`, including `ProductHypothesis`, `PMFPersona`,
`PMFTask`, `PMFScenario`, `PMFScenarioCohort`, and schema-versioned `PMFConfig`.
Added project-local `.compass/pmf.json` read/write support through
`CompassWorkspace`, plus `CompassProject.pmfConfig` refresh/save plumbing.

Seed defaults now create one hypothesis, three skeptical personas, two PMF
tasks, six starter scenarios, and a starter cohort from project title and
vision text when no PMF config exists. Missing config still decodes to an empty
config through the direct workspace API.

Focused tests in `Tests/CompassTests/PMFConfigTests.swift` cover round trip,
missing file, malformed file, unsupported schema version, seed defaults, project
refresh seeding, and project save/reload.

Intentionally skipped UI work: no PMF document/tab entry was added in this
slice. The UI entry point remains deferred until the runner or evidence view can
make the tab useful instead of a read-only placeholder.

Verification completed and passed:

```bash
./scripts/test-local.sh --filter PMFConfigTests
./scripts/test-local.sh
```
