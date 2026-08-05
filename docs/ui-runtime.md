# Generated-app UI runtime

Compass-generated macOS (and future iOS) products keep **domain logic in `crates/core`**, **UI policy in `crates/ui`**, and platform shells as **dumb binders** over UniFFI.

This is not a custom pixel renderer. SwiftUI (macOS today; iOS later) only maps `ViewState` → views and user events → `Action`.

## Layout

```text
crates/core/     # domain
crates/ui/       # ViewState, Action, Effect, update, semantic tree, simulation, guardrails
crates/ffi/      # UniFFI exports (snapshot + dispatch) over ui (+ core as needed)
apps/macos/      # SwiftUI binder only
```

CLI products do not require `crates/ui`.

## Contract

### `ViewState`

Serializable, versioned presentation state (`schema_version`). The scaffold greeting screen carries `label` and `caption` strings derived from `crates/core` via `update` / `initial_state` — not computed in Swift.

### `Action`

Closed vocabulary of user intents (scaffold: `Refresh`). Binders never invent domain rules; they dispatch actions.

### `Effect`

I/O requests returned from `update` (save, open URL, call async core, …). The greeting scaffold is pure (empty effects). Simulation stubs effects so UI tests stay deterministic.

### `SemanticNode`

Compass-owned accessibility-inspired tree: `{ id, role, value, actions, children }`. Stable ids (e.g. `greeting.label`, `greeting.caption`) are the contract for:

- headless simulation asserts
- headed AX asserts when fidelity mode is on
- SwiftUI `.accessibilityIdentifier`

### Simulator

Applies actions through `update`, records a **trace** (action + state + semantic snapshot), and supports queries by semantic id. Required UI proof lives in `crates/ui` `#[cfg(test)]` / integration tests and runs under `cargo test`.

### Guardrails

Deterministic predicates over state/semantic trees, for example:

- every interactive node has a non-empty stable id
- required ids for the current screen are present
- no empty labels on text nodes that declare a value

Failures fail `cargo test` like any other assertion.

## Verify modes

| Mode | Trigger | Role |
|------|---------|------|
| **Simulation (required)** | `cargo test --workspace` (standard Rust verify) | Primary UI acceptance |
| **macOS adapter verify** | `bash scripts/verify-macos.sh` | UniFFI bindings + `swift build` / `swift test` |
| **Headed fidelity (opt-in)** | `COMPASS_MACOS_UI_FIDELITY=1` | Bundle, Aqua launch, AX assert, screenshot → `apps/macos/dist/ui-smoke.png` |

Unset / `0` / `false` means fidelity is **off**. Default verify does **not** require an Aqua session.

Set the env var on the Compass host (or prefix the guest command) for an occasional full-fidelity iteration. Compass forwards `COMPASS_MACOS_UI_FIDELITY=1` into the guest macOS verify command when the host env enables it, and only then repairs guest auto-login for Desktop.

Future work (not required yet): Plan/acceptance-gate scheduling of periodic fidelity runs.

## Agent rules

- Put UI policy, navigation, and copy selection in `crates/ui`.
- Put domain rules in `crates/core`.
- Change `apps/macos` only when adding binder widgets or wiring new semantic ids.
- Prefer simulation tests over headed AX for proving behavior.

## iOS adapter (reserved)

A future `ios` product should share `crates/ui` + UniFFI and add `apps/ios` as another dumb SwiftUI binder. Do not fork ViewState per platform.

## Host dogfood (deferred)

Compass host remains Swift-owned (see `CONTRIBUTING.md`). After generated projects prove this contract, a later pilot may adopt the same conceptual runtime for **one** low-risk host surface. Full host rewrite is out of scope until Phase 1 is proven on generated apps.
