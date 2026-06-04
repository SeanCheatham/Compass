# 07 - Verification And Rollout

## Objective

Harden the Compass-only PMF simulation feature so it can run repeatedly inside a
Codex goal loop without creating noisy, flaky, or misleading product evidence.

## Scope

This is the final integration and quality pass across models, scaffold,
runner, prompts, storage, UI, and Plan/Reflect integration.

## End-To-End Smoke

Create a local end-to-end smoke path:

1. Create or use a blessed generated Rust app.
2. Ensure it exposes the PMF experience contract.
3. Seed a product hypothesis, persona, task, and scenario.
4. Run the PMF simulation with a fake deterministic persona model in tests.
5. Persist evidence.
6. Load evidence in the project view.
7. Generate Plan context containing the PMF summary.

This smoke should not require a live model.

## Live Model Manual Check

Add a manual checklist for a real model-backed run:

- Scenario starts.
- Persona chooses only allowed actions.
- Invalid output repair works if forced.
- Feedback is skeptical and structured.
- Evidence appears in UI.
- Plan receives a bounded summary.

Do not make live model calls part of normal automated tests.

## Flake Controls

Add safeguards:

- max turns per scenario
- timeout per model call
- timeout per app CLI invocation
- evidence record for failed runs
- disabled-by-default automatic PMF execution if runtime is too high
- clear user-facing reason when PMF simulation cannot run

## Privacy And Safety

PMF prompts may include product ideas and generated app text. Keep them within
the same model/provider settings the project already uses. Do not add new
network destinations.

Avoid storing secrets in evidence:

- redact environment variables from command output
- avoid raw shell logs unless needed
- store app semantic traces, not full filesystem snapshots

## Documentation

Update Compass docs with:

- what PMF simulation is
- what it is not
- how deterministic app experience contracts work
- how subjective feedback should be interpreted
- how to run PMF simulation manually
- how Plan uses PMF evidence

Likely docs:

- `README.md`
- `Sources/Compass/RustProjectScaffold.swift` generated README text
- any in-app guide/narrator text if present

## Final Acceptance Criteria

- All plan acceptance criteria are complete.
- Swift tests pass.
- Rust engine tests pass.
- A generated scaffold can pass `verify` and `pmf-smoke`.
- PMF evidence is persisted and visible.
- Plan/Reflect consume PMF summaries.
- The feature remains Compass-only and does not require Murphy.

## Verification

Run:

```bash
./scripts/test-local.sh
./scripts/test-rust-engine.sh
./scripts/build-local.sh
```

For a generated Rust app fixture or temporary scaffold, run:

```bash
cargo run -p xtask -- verify
cargo run -p xtask -- pmf-smoke
```

If any command cannot run in the current environment, record the exact reason
in the final implementation summary.

## Implementation Progress

- Added a model-free PMF end-to-end smoke test that:
  - seeds a PMF hypothesis/persona/task/scenario,
  - runs `PMFSimulationRunner` with a deterministic fake app and persona,
  - persists evidence and artifacts,
  - reloads evidence through `CompassProject`,
  - instantiates the PMF evidence view surface, and
  - generates Plan context containing the PMF summary without raw transcript
    text.
- Updated the generated Rust scaffold smoke test so the gated generated-app
  check runs `cargo run -p xtask -- verify` and
  `cargo run -p xtask -- pmf-smoke`.
- Updated the Compass README with PMF simulation purpose, limits, manual
  commands, evidence storage, interpretation guidance, privacy/provider notes,
  and Plan/Reflect usage.
- Updated generated Rust project README text with manual PMF checklist and
  subjective-feedback interpretation guidance.
- Confirmed focused PMF smoke, PMF planning-context, and scaffold documentation
  tests pass.

## Completion

Status: complete on 2026-06-04.

Verification:

- `./scripts/test-local.sh --filter PMFEndToEndSmokeTests` passed with 1 test.
- `./scripts/test-local.sh --filter RustProjectScaffoldTests` passed with 11 tests.
- `./scripts/test-local.sh --filter PMFPlanningEvidenceFormatterTests` passed
  with 5 tests.
- `COMPASS_RUN_GENERATED_RUST_SMOKE=1 ./scripts/test-local.sh --filter
  RustProjectScaffoldTests.generatedRustScaffoldCargoSmokeWhenRequested` passed
  with 1 generated-scaffold smoke test. The generated `cargo run -p xtask --
  verify` path requires `cargo llvm-cov`, which is not installed in this
  environment, so the gated smoke recorded that reason and ran the fallback
  generated-app checks plus `cargo run -p xtask -- pmf-smoke`.
- `./scripts/test-local.sh` passed with 1832 tests in 186 suites.
- `./scripts/test-rust-engine.sh` passed the Rust engine test suite.
- `./scripts/build-local.sh` succeeded and installed
  `/Applications/CompassLocal.app`.
