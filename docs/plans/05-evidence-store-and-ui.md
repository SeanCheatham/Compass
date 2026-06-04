# 05 - Evidence Store And UI

## Objective

Persist PMF simulation results as first-class product evidence and show enough
of that evidence in Compass for users and future agent phases to inspect it.

## Scope

Add storage, summaries, and a modest UI. Do not yet wire evidence into Plan;
that is the next plan.

## Evidence Model

Add Codable evidence records for:

- `PMFEvidenceRecord`
- `PMFRunTranscript`
- `PMFActionTurnRecord`
- `PMFFeedbackRecord`
- `PMFRunArtifact`
- `PMFEvidenceSummary`

Suggested top-level fields:

- `id`
- `schemaVersion`
- `projectID`
- `commitSHA`
- `hypothesisID`
- `personaID`
- `taskID`
- `scenarioID`
- `startedAt`
- `endedAt`
- `status`
- `route`
- `model`
- `promptVersions`
- `experienceTraceHash`
- `actionTranscript`
- `feedback`
- `artifacts`
- `failure`

## Storage Layout

Use project-local `.compass/` storage.

Suggested layout:

```text
.compass/pmf/
  evidence-index.json
  runs/
    <run-id>.json
    <run-id>-trace.json
    <run-id>-raw-transcript.json
```

Keep large raw payloads out of the primary state file. The index should be quick
to load in the sidebar or project view.

## Evidence Summary

Compute a compact summary per run:

- persona
- task
- verdict
- value score
- clarity score
- trust score
- switch likelihood
- pay likelihood
- top objection
- task outcome
- status

Also compute aggregate summaries:

- repeated objections
- average scores by persona/task
- verdict counts
- latest run per scenario
- failures by kind

Keep aggregation deterministic and local. Do not ask an LLM to summarize until
the raw evidence store is reliable.

## UI

Add a PMF evidence view that can show:

- hypothesis/persona/task context
- list of runs
- selected run trace summary
- feedback scores
- top objection and missing capability
- raw transcript disclosure
- artifact paths

This can be a new tab or a section in an existing project view. Favor clear
inspection over elaborate visuals.

## Export

Add a way to copy or save a compact Markdown summary for a selected run or
cohort. This is useful for handoff and product review.

## Likely Files

- `Sources/Compass/Models.swift`
- `Sources/Compass/CompassProject+Storage.swift`
- `Sources/Compass/Views/`
- `Sources/Compass/PlanSessionHistory.swift`
- `Sources/Compass/SessionRecordStore.swift`
- `Tests/CompassTests/`

## Acceptance Criteria

- PMF run evidence writes to disk.
- Evidence index loads without reading every raw transcript.
- Missing or malformed individual evidence records do not break the whole
  project view.
- UI can inspect at least one completed run.
- Unit tests cover write/read, index rebuild, malformed record handling, and
  aggregate summary behavior.

## Verification

Run:

```bash
./scripts/test-local.sh
```

If UI changes are substantial, build the local app:

```bash
./scripts/build-local.sh
```

## Implementation Progress

- Added first-class PMF evidence models:
  - `PMFEvidenceRecord`
  - `PMFRunTranscript`
  - `PMFActionTurnRecord`
  - `PMFFeedbackRecord`
  - `PMFRunArtifact`
  - `PMFEvidenceSummary`
- Added `PMFEvidenceIndex` and deterministic aggregate summaries for repeated
  objections, average scores by persona/task, verdict counts, latest run per
  scenario, and failures by kind.
- Added repo-local `.compass/pmf/` storage through `PMFEvidenceStore`, including
  `evidence-index.json`, primary run records, separate trace artifacts, and
  separate raw transcript artifacts.
- Added index rebuild behavior that skips malformed individual run records and
  records the malformed count without breaking the project view.
- Added `PMFEvidenceMarkdownExporter` for compact copyable run summaries.
- Wired PMF evidence index loading into `CompassWorkspace` and
  `CompassProject.refreshFromWorkspace`.
- Added a PMF workspace tab that lists runs, inspects selected run context,
  feedback scores, top objections, missing capability, trace summary, raw
  transcript, artifact paths, and copyable Markdown summary.
- Added focused storage tests for write/read, artifact writing, index rebuild,
  malformed record handling, aggregate summaries, and Markdown export.

## Completion

Status: complete on 2026-06-04.

Verification:

- `./scripts/test-local.sh --filter PMFEvidenceStoreTests` passed with 4 tests.
- `./scripts/test-local.sh --filter CompassWorkspaceStorageMigrationTests`
  passed with 8 tests.
- `./scripts/test-local.sh` passed with 1826 tests in 184 suites.
- `./scripts/build-local.sh` succeeded and installed `/Applications/CompassLocal.app`.
