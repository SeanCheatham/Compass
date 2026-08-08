# Compass Architecture

Compass is a native macOS host around a local software factory loop and an adversarial test chamber.

## Module layout

| Target | Role |
|--------|------|
| `Compass` | SwiftUI app / Activity / Results / Studio / workspace UX |
| `CompassCore` | Shared headless logic (agent loop, VM, tools, prompts, models) |
| `CompassCLI` | Thin CLI entry that calls Core |
| `CompassAgentRPC` / `CompassGuestAgent` | Host↔guest vsock JSON RPC |

`CompassCore` domains live in folders: `AgentTools/`, `AgentExecutor/`, `SharedVM/`, `Plan/`, `Live/`, `Verify/`, `Chamber/`, `Guides/`, `Runtime/`, `Factory/`, `Studio/`, `Prompts/`, `RepoMap/`, `Sandbox/`, `Scaffold/`, `Session/`, `Models/`, `Util/`, plus `Resources/` (prompt schemas, tree-sitter queries) and the root-level `Workspace.swift` (`.compass` storage). Wire models are split under `Models/` (`PlanModels`, `SessionModels`, `LiveModels`, `FlexibleModelDecoder`). Post-verify quality gates and snapshot collection are shared (`SuccessfulVerifyGates`, `QualitySnapshotCollector`, `AcceptanceGateEvaluator`, `FactoryPostChecks`). Shared pass policy lives in `FactoryPassRunner` / `FactoryPassOptions` (Critic defaults on for UI and headless; headed macOS fidelity cadence; macOS gate helper). Chamber policy lives in `ChamberPassRunner` (recon → hunt → triage → snapshot). UI (`CompassProject`) and headless (`HeadlessCompassRunner`) adapters own agent execution, sessions, and progress mapping.

## Host

The Swift/macOS app owns projects, workspace state, Activity/Live UI, prompt assembly, tool execution, and macOS VM lifecycle.

## Project kinds

`PlanState.projectKind` is `factory` (default) or `chamber` (also on `KnownProjectRecord`):

- **Factory** — Plan → Develop → Verify → Critic → Chamber (fail-open Plan pressure) → Requirements Audit.
- **Chamber** — pure hunt: recon + confined `write_generated_test` + VM `cargo test` + triage. No brief/requirements completion gates.

Chamber writes only `tests/compass_gen_*.rs`. Snapshots: `.compass/chamber-snapshot.json`, `.compass/findings.json` (also shown in the Results tab). CLI: `compass-cli chamber run|eval`.

## Model Backends

Text generation goes through `LocalModelGenerating`:

- **OpenAI-compatible cloud** (`OpenAICompatibleModelRuntime`) — primary for Plan / Develop / Critic / Requirements Audit / Chamber.
- **MLX local** (`MLXLocalModelRuntime`) — preferred for cheap assist (`AssistTextRuntime`, e.g. Studio thinking narration) when the blessed model is downloaded.
- **`RoutedModelRuntime`** selects between them using `ModelRoutingHint` (`.cloudPrimary` vs `.localPreferred`). Transcript compaction uses `.cloudPrimary`.

Runtime settings store provider choice, base URL, model id, context window, and (separately) the API key under Application Support secrets.

There is no Cursor model provider in this build. Cursor’s SDK is an agent harness, not a chat-completions endpoint.

## Factory State

`.compass/state.json` stores `PlanState` (docs historically called this factory state):

- `schemaVersion`
- `projectKind` (`factory` | `chamber`)
- `brief` (Plan-owned strategic context)
- `queue`
- `immediate`
- `completed`
- `openQuestions`
- `products` (enabled generated-project products: `cli`, `macos`, and/or `server`)
- `acceptanceGates` (optional deterministic quality thresholds)
- `successfulShipCount` / optional `macosFidelityCadence` (headed macOS UI fidelity every N ships; default interval 5)

Chamber hunt budgets (`maxIterations` / `wallClockSecs`) are runtime-only: UI Activity controls or `compass-cli chamber run --max-iterations` / `--wall-clock-secs`. They are not part of `PlanState`.

User product intent is stored separately in `.compass/brief.json` (`audience`, `problem`, `productRequirements` with `kind` / `proofLevel`) and injected into agent prompts as project context. The Brief tab **Random idea** action fills fields from `ProjectBriefIdeaGenerator` (curated starters; Save persists).

Requirement verification is factory-owned in `.compass/requirements.json` (`RequirementLedger`: criteria, scenarios, owned paths, ship traces, status, satisfied-at / last-revalidated). Statuses are `unverified` / `satisfied` / `unsatisfied` / `stale`. Plan must set `immediate.targetedRequirementIDs` while requirements remain incomplete. After Critic approves, Compass records a ship trace, marks other satisfied requirements stale when owned paths changed, and runs an incremental audit. A full audit gates loop completion when Plan returns no immediate work. Auto-play uses `PlanPassOutcome` so a successful Develop (which clears Immediate Work) continues into the next Plan instead of treating Develop success as requirements-complete. Proof levels (`deterministic` / `hybrid` / `judgment`) control how host-run criteria interact with auditor judgment. Chamber findings feed Plan prompts only (not the requirements ledger).

Legacy state files from older projects are ignored in-place.

## Generated Output

Compass-generated projects require Rust `crates/core` plus at least one product (`cli`, `macos`, and/or `server`, default `cli+macos`):

- `crates/core` — shared domain logic
- `crates/cli` — optional CLI product (golden-output binary tests)
- `crates/server` — optional HTTP server product (axum + in-process endpoint tests)
- `crates/ui` + `crates/ffi` + `apps/macos` — optional macOS product (UI state/simulation + UniFFI + dumb SwiftUI binder)

Scaffold templates live under `Sources/CompassCore/Scaffold/Templates/` (`Core`, `CLI`, `Server`, `MacOS`), composed by `RustProjectScaffold`.

See `docs/ui-runtime.md` for the ViewState / simulation / guardrails contract and headed fidelity mode.

Quality conventions live in `GeneratedProjectQuality`:

- `standardVerifyCommand` — fmt + clippy + test (Rust / macOS VM; includes `crates/ui` simulation)
- `macosVerifyCommand` — `bash scripts/verify-macos.sh` (embedded macOS VM only; headed screenshot via `COMPASS_MACOS_UI_FIDELITY=1` or ship cadence)
- `coverageCollectCommand` — `cargo llvm-cov --workspace --summary-only`
- `mutationTestCommand` — `cargo mutants --no-shuffle -j 1`, run post-verify scoped to the iteration's changed Rust files

Coverage snapshots are persisted via `CoverageSnapshotStore` after verify; mutation results via `MutationSnapshotStore` (`MutationReportParser` extracts kill-rate and surviving mutants from `cargo mutants` output). Chamber snapshots via `ChamberSnapshotStore` after every successful ship (and pure chamber runs). Coverage, mutation, and chamber snapshots all feed the next Plan prompt. Plan handoff validation uses `GeneratedVerifyValidator` for coverage-ready verify commands.

`AcceptanceGates` (in `PlanState.acceptanceGates`, falling back to `COMPASS_GATE_*` env vars) define deterministic thresholds — minimum line coverage, minimum mutation score, maximum surviving mutants. After a green verify, both the app loop (`runPostChecks`) and the headless loop collect coverage + mutation evidence and evaluate the gates; violations become structured retry issues (`acceptance_gate`), so iterations are accepted by evidence, not review. When `products` includes `macos`, a macOS verify gate also runs inside the embedded macOS VM via `FactoryPassRunner` (see `Sources/CompassCore/SharedVM`), with headed fidelity on a configurable ship cadence.

## Embedded macOS VM

The macOS VM (`Sources/CompassCore/SharedVM`) is a Virtualization.framework macOS guest and Compass's only sandboxed runtime: every agent bash call, verify, coverage, mutation, and chamber test run executes inside it, as does the generated-product macOS gate (`bash scripts/verify-macos.sh`, i.e. UniFFI bindings + `swift build` / `swift run FFIChecks`, with headed launch + Accessibility assert + screenshot when `COMPASS_MACOS_UI_FIDELITY=1` or on ship cadence). Primary UI proof is `crates/ui` simulation under `cargo test`. There is no host-shell escape hatch — Plan/Develop refuse to start until `AgentMacOSVMBashRunner.ensureReady()` succeeds. Provisioning downloads an IPSW restore image, installs macOS into a bundle under `~/Library/Application Support/Compass/SharedVM`, plants a headless first-boot payload (compass user, SSH key, guest agent LaunchDaemon), then installs Xcode CLT/Homebrew/ripgrep/OpenSSL+pkgconf/Rust/cargo-llvm-cov/cargo-mutants over vsock. Host↔guest commands use length-prefixed JSON RPC (`CompassAgentRPC`) over virtio-vsock to the in-guest `CompassGuestAgent`. Repos reach the guest over content-addressed vsock sync (`SharedCompassVMCASSync`): the host builds a gitignore-aware path→hash manifest, transfers only missing file blobs into a per-repo guest object store, and materializes the worktree **in place** so gitignored build state (`target/`, `.build/`) survives for incremental compiles. The guest worktree has no `.git` — project Git remains on the host (preflight commit, post-checks, `--commit`). If CAS fails (or `forceRefresh` is set), the runner falls back to the wipe-style tar push (`SharedCompassVMRepoWorkspaceSync`) and logs the underlying error (`WorkspaceSync` OSLog category). Guest→host pull after agent bash (`pullAfterRun: true`) always uses the **same** transport as the inbound sync — CAS pull or tar `pullAndRecord` — so transports are never mixed. Verify/coverage/mutation keep `pullAfterRun` off to avoid syncing build noise. Agent file tools still operate on the host worktree through the virtual root `/workspace` (symlink-resolved path jail); the bash runner rewrites `/workspace/...` paths in commands to the guest worktree. Design notes: `docs/host-guest-cas-sync.md`. Guest file/bash RPC paths are jails under `/Users/compass/Compass/Repos`. Per-repo guest dirt can be discarded with `SharedCompassVMGuestWorkspaceReset` / `compass-cli vm reset-workspace` without reprovisioning the VM; mutation collection auto-runs a dirt cleanup. `COMPASS_MACOS_VM_AUTO_PROVISION=0` disables first-run auto-provisioning. `compass-cli vm smoke --repo <path>` exercises the full path end to end (readiness → CAS sync → guest bash) without running a factory session. Note that first-time provisioning requires one GUI admin auth prompt (the headless first-boot plant uses `osascript ... with administrator privileges`), so initial provisioning must run from a logged-in console session.


## Agent discovery tools

`ls`, `glob`, and `list_files` are intentionally distinct (session telemetry was empty at wave-1 review, so none were collapsed):

- `ls` — one directory's immediate entries
- `glob` — filesystem pattern search across the tree
- `list_files` — codemap source inventory with language tags

Native Develop uses string-replace `edit_file` (`AgentEditFileTextTool`). Line-range `AgentEditFileTool` remains envelope/local-model quarantine only.
