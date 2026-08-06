# Contributing to Compass

Compass is a Swift/macOS software factory:

- Swift owns the macOS shell: SwiftUI views, app lifecycle, secret storage, embedded macOS VM orchestration, and the agent loop.
- Model text comes from a user-configured OpenAI-compatible cloud endpoint, with optional MLX local assist for cheap tasks such as Studio thinking narration.
- Deterministic work (files, shell, verify, state) stays in local tools / the embedded macOS VM runtime.
- Factory bash/verify/coverage/mutation require the embedded macOS VM; there is no host-shell escape hatch.

Prefer keeping new product behavior in Swift (`CompassCore` for headless/shared logic, `Compass` for UI). Do not reintroduce the removed Rust **host** daemon, tournament/market, or vendor-specific media tool paths unless that is an explicit product decision.

Rust as **generated factory output** (`RustProjectScaffold`: required `crates/core` plus `cli` and/or `macos` products; macOS includes `crates/ui` UI state/simulation + UniFFI + SwiftUI binder) is intentional and is the supported scaffold path — do not confuse it with the old host-side Rust daemon. See `docs/ui-runtime.md`.

Before opening a change:

```bash
swift test
```

Live cloud, MLX download, and VM provisioning tests remain opt-in/manual unless a CI job explicitly provides credentials and a signed macOS runner.
