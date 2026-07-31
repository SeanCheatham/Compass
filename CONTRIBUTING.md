# Contributing to Compass

Compass is a Swift/macOS software factory:

- Swift owns the macOS shell: SwiftUI views, app lifecycle, secret storage, Shared VM orchestration, and the agent loop.
- Model text comes from a user-configured OpenAI-compatible cloud endpoint, with optional MLX local assist for cheap tasks.
- Deterministic work (files, shell, verify, state) stays in local tools / the Shared VM.

Prefer keeping new product behavior in Swift (`CompassCore` for headless/shared logic, `Compass` for UI). Do not reintroduce removed Rust daemon, tournament/market, or vendor-specific media tool paths unless that is an explicit product decision.

Before opening a change:

```bash
swift test
```

Live cloud, MLX download, and VM provisioning tests remain opt-in/manual unless a CI job explicitly provides credentials and a signed macOS runner.
