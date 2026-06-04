# 03 - PMF Simulation Runner

## Objective

Add a Compass service that runs PMF scenarios by repeatedly asking a persona LLM
to choose from the generated app's allowed semantic actions, then replaying the
chosen action prefix through the deterministic app experience contract.

## Scope

Build the orchestration path. Keep UI minimal. Feedback survey prompts are
covered in the next plan, but the runner should leave hooks for them.

## Runner Shape

Suggested service:

```swift
PMFSimulationRunner
```

Inputs:

- project
- product hypothesis
- persona
- task
- generated app working directory
- execution route
- model/settings
- max turns

Outputs:

- `PMFRunResult`
- raw persona action transcript
- deterministic experience trace JSON
- run status
- failure details

## Execution Route

Use the same workspace route principles as Verify:

- If Shared VM is active for the project, run app CLI commands in the guest
  workspace through vsock bash.
- If route falls back to host, run locally using the existing process runner.

The runner must use the generated app's CLI as the state transition oracle:

```bash
cargo run -p app-cli -- experience --input '<json>'
```

The runner should maintain an action prefix. Each turn:

1. Invoke app CLI with current scenario plus action prefix.
2. Parse latest semantic state and allowed actions.
3. Ask persona agent to choose one allowed action.
4. Validate the chosen action id exists in allowed actions.
5. Append action and repeat until terminal or max turns.

## Action Validation

If the persona returns an invalid action:

- Do not pass it to the app.
- Give one repair prompt naming the allowed actions.
- If still invalid, mark the run as `invalidPersonaAction`.

Never silently map invalid actions to a nearby valid action.

## Deterministic Trace Validation

After the final action prefix is selected:

- Run the app CLI twice with the same scenario and action prefix.
- Hash both trace JSON payloads after stable normalization.
- If hashes differ, mark the run as `nondeterministicExperienceTrace`.

This protects the PMF loop from accidental time, randomness, or ordering drift.

## Failure Modes

Represent at least:

- app contract missing
- app command failed
- app output not JSON
- no allowed actions
- persona invalid action
- persona call failed
- max turns reached
- nondeterministic trace

Failures should be evidence too, but should not be treated as product feedback.

## Likely Files

- `Sources/Compass/PMF/` or equivalent new folder
- `Sources/Compass/AgentExecutor/`
- `Sources/Compass/AgentExecutionLaunchPlan.swift`
- `Sources/Compass/CompassProject+RunPasses.swift`
- `Sources/Compass/AgentTools/AgentBashRunner.swift`
- `Tests/CompassTests/`

## Acceptance Criteria

- Runner can execute a canned scenario against the blessed scaffold without UI.
- Runner validates action ids against allowed actions.
- Runner detects nondeterministic traces.
- Runner supports host and Shared VM command execution paths where existing
  route abstractions allow it.
- Unit tests cover the runner with mocked app CLI output and mocked LLM action
  responses.

## Verification

Run:

```bash
./scripts/test-local.sh
```

If a generated scaffold fixture is available, run the PMF runner against it with
a fake/mocked persona model before integrating real model calls.

## Implementation Progress

- Added `PMFSimulationRunner` with structured request/result models, persona
  action transcript entries, PMF run statuses, and failure details.
- Added PMF experience input/trace models that match the generated
  `app-cli experience` contract, including allowed actions, state, turns, and
  terminal status.
- Added `PMFExperienceCLIAppRunner` for
  `cargo run -p app-cli -- experience --input '<json>'`, passing through the
  existing `AgentExecutionLaunchPlan`/`ProcessRunner.runShell` route abstraction.
- The runner maintains an action prefix, validates persona action IDs against
  `allowedNextActions`, gives one repair opportunity, and never forwards invalid
  persona actions to the app contract.
- Final action prefixes are replayed twice, normalized as JSON, and hashed with
  SHA-256 to detect nondeterministic experience traces.
- Added mocked unit coverage for completion, invalid action repair, invalid
  action failure, nondeterminism, missing contract, command failure, invalid
  JSON, no allowed actions, persona failure, and launch-plan command behavior.
- Added an opt-in generated scaffold fixture test
  `COMPASS_RUN_GENERATED_RUST_PMF_RUNNER=1 ./scripts/test-local.sh --filter PMFSimulationRunnerTests/runnerExecutesGeneratedScaffoldWhenRequested`.

## Completion

Status: complete.

Completed on 2026-06-04 after implementing the PMF simulation runner, mocked
runner coverage, launch-plan command coverage, and opt-in generated scaffold
fixture coverage.

Verification passed:

- `./scripts/test-local.sh --filter PMFSimulationRunnerTests`
- `COMPASS_RUN_GENERATED_RUST_PMF_RUNNER=1 ./scripts/test-local.sh --filter PMFSimulationRunnerTests/runnerExecutesGeneratedScaffoldWhenRequested`
- `./scripts/test-local.sh` (1813 tests)
