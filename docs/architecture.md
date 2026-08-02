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
- `macosVerifyCommand` — `bash scripts/verify-macos.sh` (embedded macOS VM, host fallback)
- `coverageCollectCommand` — `cargo llvm-cov --workspace --summary-only`
- `mutationTestCommand` — `cargo mutants`, run post-verify scoped to the iteration's changed Rust files

Coverage snapshots are persisted via `CoverageSnapshotStore` after verify; mutation results via `MutationSnapshotStore` (`MutationReportParser` extracts kill-rate and surviving mutants from `cargo mutants` output). Both snapshots feed the next Plan prompt. Plan handoff validation uses `GeneratedVerifyValidator` for coverage-ready verify commands.

`AcceptanceGates` (in `FactoryState.acceptanceGates`, falling back to `COMPASS_GATE_*` env vars) define deterministic thresholds — minimum line coverage, minimum mutation score, maximum surviving mutants. After a green verify, both the app loop (`runPostChecks`) and the headless loop collect coverage + mutation evidence and evaluate the gates; violations become structured retry issues (`acceptance_gate`), so iterations are accepted by evidence, not review. When `products` includes `macos`, a macOS verify gate also runs — inside the embedded macOS VM (see `Sources/CompassCore/SharedVM`) when provisioned, with host-shell fallback.

## Containerized Linux

The containerized Linux runtime provides a deterministic execution surface for generated Rust work. Default provisioning uses the `rust:1-bookworm` image with the Rust toolchain on PATH. File tools operate on the host worktree through the virtual root `/workspace`; bash/verify run inside ephemeral Linux containers with that worktree mounted at `/workspace`.

## Embedded macOS VM

The macOS VM (`Sources/CompassCore/SharedVM`) is a Virtualization.framework macOS guest used for work that needs a real macOS toolchain — primarily the generated-product macOS gate (`bash scripts/verify-macos.sh`, i.e. `swift build` / `swift test`). Provisioning downloads an IPSW restore image, installs macOS into a bundle under `~/Library/Application Support/Compass/SharedVM`, plants a headless first-boot payload (compass user, SSH key, guest agent LaunchDaemon), then installs Xcode CLT/Homebrew/ripgrep/Rust over vsock. Host↔guest commands use length-prefixed JSON RPC (`CompassAgentRPC`) over virtio-vsock to the in-guest `CompassGuestAgent`. Repos reach the guest over git-over-SSH (`SharedCompassVMGitSSHSync`): the host snapshots the worktree as a temporary-index commit (uncommitted changes included, `.gitignore` respected), pushes it to a bare exchange repo in the guest, and the guest worktree `git reset --hard`s to it — deltas only, and gitignored build state (`target/`, `.build/`) survives for incremental compiles. Guest-side edits return via a sync-back ref (`pullAfterRun` on `AgentMacOSVMBashRunner`); the tar push remains as fallback transport. `MacOSVerifyGate` routes the macOS gate to the VM with host-shell fallback. Select it with `COMPASS_BASH_RUNTIME=macos_vm` (headless) or the macOS VM tab in the app's Runtime pane; `COMPASS_MACOS_VERIFY_RUNTIME=host` forces the host shell, and `COMPASS_MACOS_VM_AUTO_PROVISION=0` disables first-run auto-provisioning.

