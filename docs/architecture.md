# Compass Architecture

Compass is a native macOS host around a local software factory loop.

## Host

The Swift/macOS app owns projects, workspace state, Activity/Live UI, prompt assembly, tool execution, and macOS VM lifecycle.

## Model Backends

Text generation goes through `LocalModelGenerating`:

- **OpenAI-compatible cloud** (`OpenAICompatibleModelRuntime`) — primary for Plan / Develop / Critic.
- **MLX local** (`MLXLocalModelRuntime`) — preferred for cheap assist (compaction and narrators) when the blessed model is downloaded.
- **`RoutedModelRuntime`** selects between them using `ModelRoutingHint` (`.cloudPrimary` vs `.localPreferred`).

Runtime settings store provider choice, base URL, model id, context window, and (separately) the API key under Application Support secrets.

There is no Cursor model provider in this build. Cursor’s SDK is an agent harness, not a chat-completions endpoint.

## Factory State

`.compass/state.json` stores `PlanState` (docs historically called this factory state):

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

- `standardVerifyCommand` — fmt + clippy + test (Rust / macOS VM)
- `macosVerifyCommand` — `bash scripts/verify-macos.sh` (embedded macOS VM, host fallback)
- `coverageCollectCommand` — `cargo llvm-cov --workspace --summary-only`
- `mutationTestCommand` — `cargo mutants`, run post-verify scoped to the iteration's changed Rust files

Coverage snapshots are persisted via `CoverageSnapshotStore` after verify; mutation results via `MutationSnapshotStore` (`MutationReportParser` extracts kill-rate and surviving mutants from `cargo mutants` output). Both snapshots feed the next Plan prompt. Plan handoff validation uses `GeneratedVerifyValidator` for coverage-ready verify commands.

`AcceptanceGates` (in `PlanState.acceptanceGates`, falling back to `COMPASS_GATE_*` env vars) define deterministic thresholds — minimum line coverage, minimum mutation score, maximum surviving mutants. After a green verify, both the app loop (`runPostChecks`) and the headless loop collect coverage + mutation evidence and evaluate the gates; violations become structured retry issues (`acceptance_gate`), so iterations are accepted by evidence, not review. When `products` includes `macos`, a macOS verify gate also runs — inside the embedded macOS VM (see `Sources/CompassCore/SharedVM`) when provisioned, with host-shell fallback.

## Embedded macOS VM

The macOS VM (`Sources/CompassCore/SharedVM`) is a Virtualization.framework macOS guest and Compass's only sandboxed runtime: every agent bash call, verify, coverage, and mutation run executes inside it, as does the generated-product macOS gate (`bash scripts/verify-macos.sh`, i.e. `swift build` / `swift test`). Provisioning downloads an IPSW restore image, installs macOS into a bundle under `~/Library/Application Support/Compass/SharedVM`, plants a headless first-boot payload (compass user, SSH key, guest agent LaunchDaemon), then installs Xcode CLT/Homebrew/ripgrep/Rust/cargo-llvm-cov/cargo-mutants over vsock. Host↔guest commands use length-prefixed JSON RPC (`CompassAgentRPC`) over virtio-vsock to the in-guest `CompassGuestAgent`. Repos reach the guest over git-over-SSH (`SharedCompassVMGitSSHSync`): the host snapshots the worktree as a temporary-index commit (uncommitted changes included, `.gitignore` respected), pushes it to a bare exchange repo in the guest, and the guest worktree `git reset --hard`s to it — deltas only, and gitignored build state (`target/`, `.build/`) survives for incremental compiles. Agent file tools still operate on the host worktree through the virtual root `/workspace`; the bash runner rewrites `/workspace/...` paths in commands to the guest worktree. Guest-side edits return via a sync-back ref (`pullAfterRun` on `AgentMacOSVMBashRunner`); the tar push remains as fallback transport. `MacOSVerifyGate` routes the macOS gate to the VM with host-shell fallback. The VM is the default everywhere; `COMPASS_BASH_RUNTIME=host` (headless) runs commands in a host shell instead, `COMPASS_MACOS_VERIFY_RUNTIME=host` forces the macOS gate onto the host, and `COMPASS_MACOS_VM_AUTO_PROVISION=0` disables first-run auto-provisioning. `compass-cli vm smoke --repo <path>` exercises the full path end to end (readiness → git sync → guest bash) without running a factory session. Note that first-time provisioning requires one GUI admin auth prompt (the headless first-boot plant uses `osascript ... with administrator privileges`), so initial provisioning must run from a logged-in console session.


## Agent discovery tools

`ls`, `glob`, and `list_files` are intentionally distinct (session telemetry was empty at wave-1 review, so none were collapsed):

- `ls` — one directory's immediate entries
- `glob` — filesystem pattern search across the tree
- `list_files` — codemap source inventory with language tags

Native Develop uses string-replace `edit_file` (`AgentEditFileTextTool`). Line-range `AgentEditFileTool` remains envelope/local-model quarantine only.
