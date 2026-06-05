# 05 - Productization Simulation And Evidence

## Objective

Run deterministic and model-backed simulations against experiment commits, then
store evidence that explains whether a prototype relieved the original pain.

This plan replaces the superseded app-fit evidence path with productization
evidence.

## Scope

Implement the runner, action validation, trace validation, evidence model,
storage layout, summarization, and bounded prompt summaries.

The UI can remain minimal in this plan. Full UI treatment comes later.

## Runner Modes

Support two runner modes:

```text
model_free
  uses fixture actions and deterministic app traces
  required for smoke tests

persona_model
  asks a persona model to choose allowed actions
  stores transcripts and structured subjective feedback
  manual or explicitly triggered at first
```

Both modes must target a specific immutable app version:

```text
experimentID
branchName
commitSha
scenarioID
```

## Persona Action Rules

Persona agents receive:

- pain summary
- persona and segment context
- current workflow
- alternatives
- solution promise
- current semantic app state
- allowed actions
- previous turns

The model must choose exactly one allowed action or stop with a structured
reason. The host rejects invented action ids.

## Feedback Rules

After a trace, the feedback prompt should ask whether the prototype:

- recognized the pain
- improved the current workflow
- beat or failed to beat alternatives
- reduced switching objections
- exposed missing capabilities
- created pull for continued use

Feedback remains subjective evidence. It must include model id, prompt version,
scenario id, persona id, experiment id, branch, commit, timestamp, trace hash,
and transcript artifact path.

## Evidence Record

Store records with:

```text
id
experimentID
solutionID
painID
branchName
commitSha
scenarioID
personaID
mode
status
startedAt
endedAt
traceHash
traceArtifactPath
feedbackArtifactPath
promptVersions
model
scores
objections
missingCapabilities
currentAlternativeComparison
verdict
summary
```

`verdict` values:

- `strong_pull`
- `promising`
- `unclear`
- `weak`
- `rejected`

## Storage Layout

```text
.compass/productization/
  evidence-index.json
  runs/
    <run-id>/
      trace.json
      feedback.json
      transcript.jsonl
      summary.md
```

The index should be quick to load and suitable for Plan/Reflect prompt
summaries.

## Aggregation

Provide summary helpers for:

- latest evidence by experiment
- repeated objections
- low-score clusters
- missing capability frequency
- verdict distribution
- comparison against current alternatives
- evidence gaps by active solution

## Parallel Execution

CLI-only model-free simulations may run in parallel across experiment commits.

Persona-model runs should use bounded concurrency and preserve transcript order.
Visual verification should use a separate tighter semaphore.

## Likely Files

- `Sources/Compass/ProductizationSimulationRunner.swift`
- `Sources/Compass/ProductizationEvidence.swift`
- `Sources/Compass/ProductizationPlanningDigest.swift`
- `Sources/Compass/Workspace.swift`
- `Sources/Compass/Rust/RustVerifyCommands.swift`
- `Sources/Compass/Resources/Schemas/`
- tests for runner, evidence, summaries, and prompt schemas

## Acceptance Criteria

- Model-free simulation runs against a productization experience contract.
- Persona-model simulation rejects invented actions.
- Evidence records include experiment branch and commit identity.
- Evidence summaries compare prototypes to current alternatives.
- Plan/Reflect can consume bounded summaries without raw transcripts.

## Verification

- Run focused tests for simulation runner and evidence storage.
- Run `productization-smoke` against a generated workspace.
- Run one manual persona-model simulation and inspect stored provenance.
- Confirm repeated runs against the same input produce stable deterministic
  traces before persona feedback is considered.

## Completion

Status: complete.

Completed on 2026-06-04 after adding productization-specific simulation and
evidence infrastructure. Compass now has a model-free/persona-model
productization runner that targets `productization-experience`, validates action
ids against `allowedNextActions`, rejects invented persona actions, verifies
deterministic trace hashes, and records experiment branch/commit provenance.

Evidence now stores under `.compass/productization/` with a quick
`evidence-index.json` and run directories containing `record.json`,
`trace.json`, `feedback.json`, `transcript.jsonl`, and `summary.md` artifacts
when provided. Aggregates cover latest evidence by experiment, repeated
objections, missing capability frequency, low-score clusters, verdict
distribution, failures, and current-alternative comparisons. Plan/Reflect
productization context now consumes bounded productization evidence summaries
without raw transcripts.

Verification passed:

- `./scripts/test-local.sh --filter ProductizationSimulationRunnerTests`
- `COMPASS_RUN_GENERATED_RUST_PRODUCTIZATION_RUNNER=1 ./scripts/test-local.sh --filter ProductizationSimulationRunnerTests`
- `./scripts/test-local.sh --filter ProductizationEvidenceStoreTests`
- `./scripts/test-local.sh --filter DiscoverPromptContractTests`
- `./scripts/test-local.sh --filter PlanPromptTests`
- `./scripts/test-local.sh --filter ProductizationEvidenceStoreTests`
- `COMPASS_RUN_GENERATED_RUST_SMOKE=1 ./scripts/test-local.sh --filter RustProjectScaffoldTests`

Notes:

- The generated scaffold smoke skipped `xtask verify` coverage because
  `cargo llvm-cov` is not installed locally, then ran generated
  `productization-smoke` and built `app-desktop` successfully.
- A contract mismatch found during generated-runner verification was fixed:
  generated Rust now serializes `missingCapabilityIDs` to match the schema, and
  the Swift trace decoder tolerates the previous `missingCapabilityIds` spelling
  while encoding the canonical `missingCapabilityIDs` key.
