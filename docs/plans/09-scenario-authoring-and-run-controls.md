# 09 - Scenario Authoring And Run Controls

## Objective

Let users create productization scenarios and trigger evidence runs from the
Productization workbench without hand-editing productization state or relying on
lower-level test setup.

Plans 05-08 established the runner, evidence store, workbench, and rollout
branch mechanics. The next product loop improvement is making scenario cohorts
operable: define the user situation, choose the target experiment commit, run a
model-free smoke, and inspect the resulting evidence in one place.

## Scope

Add workbench controls and supporting state helpers for scenario authoring,
cohort management, and run triggering.

This plan should keep live persona-model runs explicitly manual. Start with
deterministic/model-free runs and bounded status reporting.

## Scenario Authoring

Users should be able to:

- create a scenario for an active experiment
- choose the target segment, current workflow, and current alternative
- write the task and success signal in plain language
- group scenarios into an enabled cohort
- see which commit the scenario targets before running evidence

## Run Controls

The workbench should support:

- model-free run against the selected experiment commit
- clear disabled states when the generated app contract is missing
- timeout and max-turn display
- progress/error logging tied to the experiment id
- immediate evidence index refresh after a successful run

Do not start persona-model runs automatically in this plan.

## Acceptance Criteria

- Users can create and edit at least one scenario cohort from the workbench.
- A model-free evidence run can be triggered for the selected experiment commit
  without hidden file edits.
- The run result writes productization evidence and refreshes the selected
  experiment's Scenario Runs list.
- Missing generated app contract, stale commit, timeout, and app-command
  failures produce user-visible messages.
- Focused tests cover scenario creation, cohort persistence, model-free run
  request construction, successful evidence write, and contract-missing error
  reporting.

## Verification

- Run focused Swift tests for scenario/cohort persistence and run request
  construction.
- Run ProductizationSimulationRunnerTests for model-free runner behavior.
- Run ProductizationEvidenceStoreTests to confirm prompt context stays bounded
  and transcript-free.
- Run a generated workspace `productization-smoke` when the local toolchain
  supports it.

## Status

Complete on 2026-06-04.

Completed scenario and cohort authoring in the Productization workbench, added
model-free run controls tied to generated app contract availability, and wired
run outcomes back into productization evidence and experiment summaries.

Verification:

- `./scripts/test-local.sh --filter ProductizationScenarioRunTests`
- `./scripts/test-local.sh --filter ProductizationConfigTests`
- `./scripts/test-local.sh --filter ProductizationSimulationRunnerTests`
- `./scripts/test-local.sh --filter ProductizationEvidenceStoreTests`
- `./scripts/test-local.sh --filter DiscoverPromptContractTests`
- `./scripts/test-local.sh --filter PromptSchemaLoadingTests`
- `COMPASS_RUN_GENERATED_RUST_SMOKE=1 ./scripts/test-local.sh --filter generatedRustScaffoldCargoSmokeWhenRequested`
  passed; `xtask verify` was skipped inside the test because `cargo llvm-cov`
  is not installed, and the generated `productization-smoke` path ran.
