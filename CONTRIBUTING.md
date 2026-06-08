# Contributing to Compass

Compass is becoming a hybrid system:

- Swift owns the macOS shell: SwiftUI views, app lifecycle, Keychain,
  Foundation Models access, and `Virtualization.framework` orchestration.
- Rust owns portable product logic: daemon IPC, tournament state and
  transitions, agent execution, host/guest tools, schemas, and replay tests.
- The guest boundary remains AgentRPC-compatible while the guest agent migrates.

Prefer Rust for new deterministic product behavior. Prefer Swift only when the
code needs an Apple-only framework, UI binding, or signed-app lifecycle hook.

Migration feature flags are centralized in `CompassRuntimeFeatureFlags` and are
included in runtime diagnostics. Add new flags there first, then route shell
decisions through the typed property instead of reading environment variables at
call sites.

Before opening a change:

```bash
cargo test --workspace
swift test
./scripts/test-rust-engine.sh
```

Live LLM, Foundation Models, and VM provisioning tests remain opt-in/manual
unless a CI job explicitly provides credentials and a signed macOS runner.
