# 02 - Generated Experience Contract

## Objective

Extend the blessed Rust generated-app scaffold so apps expose a deterministic
semantic experience contract that PMF personas can interact with.

The contract should be useful before any desktop UI exists.

## Scope

Implement generated-project contract changes and scaffold validation. Do not
call LLMs in this plan.

## Contract

Add these concepts to the generated Rust app:

- `ExperienceScenario`
- `ExperienceState`
- `ExperienceAction`
- `ExperienceAllowedAction`
- `ExperienceTurn`
- `ExperienceTrace`
- `run_experience(input: ExperienceInput) -> ExperienceTrace`

Suggested `ExperienceInput` shape:

```json
{
  "schemaVersion": 1,
  "scenario": {
    "seed": "demo",
    "personaSummary": "Operations lead evaluating a workflow tool",
    "task": "Find whether this app can reduce weekly reporting work"
  },
  "actions": [
    {
      "id": "inspect_value_prop",
      "params": {}
    }
  ]
}
```

The app should deterministically replay the supplied action prefix from the
initial scenario and return:

- initial state
- each action
- each resulting state
- allowed next actions
- terminal status
- stable event log

## CLI

Add an app CLI command:

```bash
cargo run -p app-cli -- experience --input '<json>'
```

It should print stable pretty JSON. A missing `--input` may use a demo scenario.

Also add:

```bash
cargo run -p app-cli -- experience-schema
```

This should print a JSON schema for the experience input or a combined contract
schema if that is simpler.

## Allowed Actions

The generated app must own the action list. Persona agents can choose only from
allowed actions surfaced in the latest semantic state.

Example starter actions:

- inspect value proposition
- start core workflow
- provide requested input
- ask for help
- compare with current alternative
- abandon task

Keep action labels product-neutral in the scaffold, but make them easy for
Develop to specialize per generated app.

## Xtask

Add:

```bash
cargo run -p xtask -- pmf-smoke
```

The smoke should:

- run the experience CLI with a demo scenario
- assert valid JSON
- assert at least one allowed action exists initially
- replay at least two actions
- assert the trace is stable across two identical invocations

Include `pmf-smoke` in `factory-smoke` only if runtime cost is low. Otherwise
document it as a separate optional PMF tier.

## Scaffold Metadata

Extend `compass-scaffold.toml` capabilities:

```toml
[capabilities]
pmf_experience = true
```

Update `compass-engine scaffold-check` so it verifies:

- capability marker exists
- app-core has experience model markers
- app-cli has `experience` and `experience-schema`
- xtask has `pmf-smoke`
- schemas include the PMF/experience contract

## Likely Files

- `Sources/Compass/RustProjectScaffold.swift`
- `crates/compass-engine/src/scaffold.rs`
- `crates/compass-engine/tests/scaffold_check.rs`
- `crates/compass-engine/tests/fixtures/blessed-workspace/`
- `Sources/Compass/Rust/RustVerifyCommands.swift`
- `Sources/Compass/ForgeProfile.swift`

## Acceptance Criteria

- Newly generated Rust apps include the PMF experience contract.
- `cargo run -p app-cli -- experience --input '<json>'` works.
- `cargo run -p xtask -- pmf-smoke` works.
- `cargo run -p xtask -- verify` still works.
- `compass-engine scaffold-check` reports PMF contract drift.
- Existing scaffold tests are updated and pass.

## Verification

Run:

```bash
./scripts/test-rust-engine.sh
./scripts/test-local.sh
```

Also create or regenerate a temporary scaffold and run:

```bash
cargo run -p xtask -- verify
cargo run -p xtask -- pmf-smoke
```

## Completion

Status: Complete.

Completed on 2026-06-04. Extended the generated Rust scaffold with a
Compass-only PMF semantic experience contract:

- `ExperienceScenario`
- `ExperienceInput`
- `ExperienceState`
- `ExperienceAction`
- `ExperienceAllowedAction`
- `ExperienceTurn`
- `ExperienceTrace`
- `run_experience(input: ExperienceInput) -> ExperienceTrace`

The generated `app-cli` now supports:

```bash
cargo run -p app-cli -- experience --input '<json>'
cargo run -p app-cli -- experience-schema
```

The generated `xtask` now supports:

```bash
cargo run -p xtask -- pmf-smoke
```

`pmf-smoke` runs the experience CLI, validates JSON, confirms initial allowed
actions, replays two actions, and verifies stable output across identical
invocations. `factory-smoke` also invokes `pmf-smoke` before visual verification.

Updated scaffold metadata with `pmf_experience = true`, added
`schemas/experience-input.schema.json` and
`schemas/experience-trace.schema.json`, and taught `compass-engine
scaffold-check` to report PMF contract drift across app-core, app-cli, xtask,
and schema files. Compass's Swift scaffold capability decoder and tool
formatting now include `pmf_experience`.

Verification completed and passed:

```bash
./scripts/test-local.sh --filter RustProjectScaffoldTests
./scripts/test-local.sh --filter AgentRustVerifyToolsTests
./scripts/test-local.sh --filter RustVerifyCommandsTests
cargo test -p compass-engine scaffold_check
COMPASS_RUN_GENERATED_RUST_SMOKE=1 ./scripts/test-local.sh --filter RustProjectScaffoldTests/generatedRustScaffoldCargoSmokeWhenRequested
./scripts/test-local.sh
./scripts/test-rust-engine.sh
```

Generated `cargo run -p xtask -- pmf-smoke` was exercised by the opt-in generated
Rust scaffold smoke test. Generated `cargo run -p xtask -- verify` was not run on
this host because the existing verify tier requires `cargo-llvm-cov`, and
`cargo llvm-cov --version` reports `error: no such command: llvm-cov`.
