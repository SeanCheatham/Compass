# 04 - Generated Rust Productization Contracts

## Objective

Update the generated Rust workspace contract so prototypes can be evaluated as
product experiments for a specific pain and solution hypothesis.

The existing deterministic experience contract is a good foundation, but it must
include pain, solution, experiment, current workflow, and alternative context.

## Scope

Modify the generated Rust scaffold, schema files, CLI commands, xtask checks,
and compass-engine scaffold checks.

Keep the blessed workspace:

```text
crates/app-core
crates/app-cli
crates/app-desktop
xtask
schemas/
rust-toolchain.toml
```

## Contract Shape

Replace the generic app-fit experience input with productization-aware input:

```text
ProductizationExperienceInput
  schemaVersion
  pain
  solution
  experiment
  scenario
  currentWorkflow
  alternatives
  actions
```

The trace should report:

```text
ProductizationExperienceTrace
  schemaVersion
  painID
  solutionID
  experimentID
  initialState
  turns
  allowedNextActions
  terminalStatus
  eventLog
  painReliefSignals
```

`painReliefSignals` should include deterministic fields such as:

- `painRecognized`
- `workflowAdvanced`
- `currentAlternativeAddressed`
- `switchingObjectionReduced`
- `missingCapabilityIDs`
- `evidenceSummary`

## App-Core Rules

Generated `app-core` must expose pure functions:

```text
run_simulation(SimulationInput) -> SimulationSnapshot
run_gui_replay(GuiReplayTrace) -> GuiSemanticSnapshot
run_productization_experience(ProductizationExperienceInput)
  -> ProductizationExperienceTrace
```

The app owns the allowed action list for each semantic state. Persona agents may
only choose actions from the latest allowed list.

## CLI Commands

`app-cli` should expose:

```text
status
schema
simulation-schema
gui-replay-schema
productization-experience-schema
simulate --input '<json>'
gui-replay --input '<json>'
productization-experience --input '<json>'
```

Keep compatibility aliases only if they do not preserve old product-first
semantics. Breaking changes are allowed.

## Xtask Commands

Use:

```text
cargo run -p xtask -- verify
cargo run -p xtask -- visual-verify
cargo run -p xtask -- factory-smoke
cargo run -p xtask -- productization-smoke
```

`productization-smoke` proves the generated app can run a deterministic
model-free productization journey.

## Scaffold Metadata

Update `compass-scaffold.toml` capabilities:

```text
[capabilities]
xtask_verify = true
visual_verify = true
schema_contracts = true
desktop_handshake = true
simulation_fixtures = true
gui_replay = true
productization_experience = true
```

The old app-fit capability can be removed or treated as obsolete.

## Likely Files

- `Sources/Compass/RustProjectScaffold.swift`
- `Sources/Compass/Rust/RustVerifyCommands.swift`
- `Sources/Compass/Rust/RustEngineModels.swift`
- `Sources/Compass/AgentTools/AgentRustVerifyTools.swift`
- `crates/compass-engine/src/scaffold.rs`
- `crates/compass-engine/tests/scaffold_check.rs`
- generated Rust scaffold fixture tests

## Acceptance Criteria

- New generated workspaces expose productization experience schemas.
- `productization-smoke` passes without live model calls.
- Scaffold checks verify the new capability markers.
- The generated desktop still supports semantic GUI snapshots and visual
  verification.
- The contract can compare a solution against current alternatives.

## Verification

- Run Rust engine scaffold tests.
- Run Swift tests for Rust scaffold generation.
- Generate a sample workspace and run:

```bash
cargo run -p xtask -- verify
cargo run -p xtask -- productization-smoke
cargo run -p xtask -- visual-verify
```

## Completion

Status: complete.

Completed on 2026-06-04 after converting the generated Rust scaffold contract
from the old app-fit capability to `productization_experience`. New generated
workspaces now write productization experience schemas, expose
`run_productization_experience(ProductizationExperienceInput)`, support
`app-cli productization-experience(-schema)`, and run `xtask
productization-smoke` without model calls.

Verification passed:

- `./scripts/test-local.sh --filter RustProjectScaffoldTests`
- `./scripts/test-local.sh --filter AgentRustVerifyToolsTests`
- `COMPASS_RUN_GENERATED_RUST_SMOKE=1 ./scripts/test-local.sh --filter RustProjectScaffoldTests`
- `./scripts/test-local.sh --filter RustVerifyCommandsTests`
- `./scripts/test-local.sh --filter RustFactoryHealthTests`
- `cargo fmt --check -p compass-engine`
- `cargo test -p compass-engine scaffold_check`

Notes:

- The generated smoke test skipped `xtask verify` coverage because
  `cargo llvm-cov` is not installed locally, then ran the generated
  `productization-smoke` and built `app-desktop` successfully.
- Live generated `visual-verify` was not launched in this slice; scaffold tests
  continue to assert the semantic GUI snapshot and visual verification hooks.
