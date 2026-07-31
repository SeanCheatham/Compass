# Compass Architecture

Compass is a native macOS host around a local software factory loop.

## Host

The Swift/macOS app owns projects, workspace state, Activity/Live UI, prompt assembly, tool execution, and containerized Linux lifecycle.

## Model Backends

Text generation goes through `LocalModelGenerating`:

- **OpenAI-compatible cloud** (`OpenAICompatibleModelRuntime`) — primary for Plan / Develop / Critic.
- **MLX local** (`MLXLocalModelRuntime`) — preferred for cheap assist (compaction, narrators, Explore) when the blessed model is downloaded.
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

Legacy state files from older projects are ignored in-place.

## Generated Output

Compass-generated projects are Rust Cargo workspaces with `crates/app-core` and `crates/app-cli`. There is no web UI package.

Quality conventions live in `GeneratedProjectQuality`:

- `standardVerifyCommand` — fmt + clippy + test
- `coverageCollectCommand` — `cargo llvm-cov --workspace --summary-only`
- `mutationTestCommand` — `cargo mutants` (prepared for a future post-verify hook; not invoked by the factory loop yet)

Coverage snapshots are persisted via `CoverageSnapshotStore` after verify. Plan handoff validation uses `GeneratedVerifyValidator` for coverage-ready verify commands.

## Containerized Linux

The containerized Linux runtime provides a deterministic execution surface for generated Rust work. Default provisioning uses the `rust:1-bookworm` image with the Rust toolchain on PATH. File tools operate on the host worktree through the virtual root `/workspace`; bash/verify run inside ephemeral Linux containers with that worktree mounted at `/workspace`.
