# Compass Architecture

Compass is a native macOS host around a local software factory loop.

## Host

The Swift/macOS app owns projects, workspace state, Activity/Live UI, prompt assembly, tool execution, and containerized Linux lifecycle.

## Model Backends

Text generation goes through `LocalModelGenerating`:

- **OpenAI-compatible cloud** (`OpenAICompatibleModelRuntime`) — primary for Plan / Develop / Critic.
- **MLX local** (`MLXLocalModelRuntime`) — preferred for cheap assist (compaction and narrators) when the blessed model is downloaded.
- **`RoutedModelRuntime`** selects between them using `ModelRoutingHint` (`.cloudPrimary` vs `.localPreferred`).

Runtime settings store provider choice, base URL, model id, context window, and (separately) the API key under Application Support secrets.

There is no Cursor model provider in this build. Cursor’s SDK is an agent harness, not a chat-completions endpoint.

## Factory State

`.compass/state.json` stores `FactoryState`:

- `schemaVersion`
- `brief`
- `queue`
- `immediate`
- `completed`
- `openQuestions`
- `acceptanceGates` (optional deterministic quality thresholds)

Legacy state files from older projects are ignored in-place.

## Generated Output

Compass-generated projects require Rust `crates/core` plus at least one product (`cli` and/or `macos`, default both):

- `crates/core` — shared domain logic
- `crates/cli` — optional CLI product
- `crates/ffi` + `apps/macos` — optional macOS product (UniFFI + thin SwiftUI shell)

Quality conventions live in `GeneratedProjectQuality`:

- `standardVerifyCommand` — fmt + clippy + test (Rust / Linux container)
- `macosVerifyCommand` — `bash scripts/verify-macos.sh` (host today; macOS VM later)
- `coverageCollectCommand` — `cargo llvm-cov --workspace --summary-only`
- `mutationTestCommand` — `cargo mutants`, run post-verify scoped to the iteration's changed Rust files

Coverage snapshots are persisted via `CoverageSnapshotStore` after verify; mutation results via `MutationSnapshotStore` (`MutationReportParser` extracts kill-rate and surviving mutants from `cargo mutants` output). Both snapshots feed the next Plan prompt. Plan handoff validation uses `GeneratedVerifyValidator` for coverage-ready verify commands.

`AcceptanceGates` (in `FactoryState.acceptanceGates`, falling back to `COMPASS_GATE_*` env vars) define deterministic thresholds — minimum line coverage, minimum mutation score, maximum surviving mutants. After a green verify, both the app loop (`runPostChecks`) and the headless loop collect coverage + mutation evidence and evaluate the gates; violations become structured retry issues (`acceptance_gate`), so iterations are accepted by evidence, not review. When `products` includes `macos`, a host-side macOS verify gate also runs (temporary stand-in for restoring macOS VMs).

## Containerized Linux

The containerized Linux runtime provides a deterministic execution surface for generated Rust work. Default provisioning uses the `rust:1-bookworm` image with the Rust toolchain on PATH. File tools operate on the host worktree through the virtual root `/workspace`; bash/verify run inside ephemeral Linux containers with that worktree mounted at `/workspace`.
