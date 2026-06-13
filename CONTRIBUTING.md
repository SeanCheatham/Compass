# Contributing to Compass

Compass is a SwiftPM macOS app with a small Rust engine bridge:

- Swift owns the macOS shell: SwiftUI views, app lifecycle, Keychain,
  local MLX/Foundation Models access, project state, prompt assembly, agent
  tools, and `Virtualization.framework` orchestration.
- Rust owns the portable Tessera engine bridge exposed through the
  `rust/compass-engine` C ABI.
- Legacy TypeScript project support remains for imported workspaces, but new
  Compass-generated projects target Tessera.

Prefer Swift for UI, Apple-only frameworks, signed-app lifecycle hooks, and
CompassCore orchestration. Prefer Rust when behavior belongs inside the portable
Tessera engine bridge or benefits from Cargo-level tests around the FFI boundary.

Migration feature flags are centralized in `CompassRuntimeFeatureFlags` and are
included in runtime diagnostics. Add new flags there first, then route shell
decisions through the typed property instead of reading environment variables at
call sites.

Before opening a change:

```bash
./scripts/test-local.sh
./scripts/test-rust-engine.sh
```

Use `./scripts/format.sh` for intentional Swift formatting sweeps; the Rust
engine script runs `cargo fmt --check` for the bridge.

Live LLM, Foundation Models, and VM provisioning tests remain opt-in/manual
unless a CI job explicitly provides credentials and a signed macOS runner.
