# Rust Core Cutover Rollout

## Local Verification

```bash
./scripts/test-rust-core.sh
swift test --filter CompassDaemonClientTests --filter CompassRuntimeFeatureFlagsTests
./scripts/test-rust-engine.sh
```

## Feature Flag Order

1. `rustDaemonEnabled` on by default.
2. `COMPASS_RUST_TOURNAMENT_SHADOW=1` for parity dogfooding.
3. `COMPASS_RUST_TOURNAMENT_DRIVER=1` after replay fixtures agree.
4. `COMPASS_RUST_AGENT_EXECUTOR=1` after agent fixtures cover HTTP-provider runs.
5. `COMPASS_RUST_GUEST_AGENT=1` after signed VM smoke validates install.

## Rollback

Each migrated subsystem is flag-gated. To roll back a release, ship a patch with
the affected flag defaulting off. Keep Swift fallback code until the associated
dogfooding window and fixture suite are green.

## Fixture Helpers

```bash
./scripts/replay-tournament-rust.sh --scenario round1_basic
./scripts/run-agent-fixture.sh tests/agent_fixtures/develop_simple
./scripts/diff-compass-state.sh baseline/.compass actual/.compass
```

The replay and fixture scripts fail clearly when inputs are missing, which keeps
CI setup honest while the migration accumulates real replay data.
