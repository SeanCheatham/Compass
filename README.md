# Compass

Compass is a macOS-native local software factory for Git repositories.

The current direction:

- Factory turns (Plan / Develop / Critic) use a user-configured **OpenAI-compatible** cloud endpoint (`base URL` + `API key` + `model`).
- Optional **MLX** local assist handles cheap/small work (narration, compaction, Explore helpers) when the blessed local model is downloaded.
- Compass does deterministic work through local tools and the embedded macOS VM.
- Generated projects require Rust `crates/core` plus at least one product: `cli` and/or `macos` (default both). Domain logic stays in Rust; UI policy in `crates/ui`; macOS uses UniFFI + a dumb SwiftUI binder.

## Factory Loop

Compass keeps a small persisted factory state in `.compass/state.json`:

- `brief`: summary, target users, desired outcomes, constraints, and acceptance signals.
- `queue`: decomposed work items.
- `immediate`: the selected implementation packet for the next Develop pass.
- `completed`: completed iteration notes.
- `openQuestions`: unresolved questions that affect scope.
- `products`: enabled generated-project products (`cli` and/or `macos`).

The v1 loop is:

1. Brief
2. Decompose queue
3. Select immediate work
4. Develop
5. Verify
6. Critic

Activity/Live is the primary project surface.

## Generated Projects

Compass-generated output requires a Rust `crates/core` library plus at least one product:

- `cli` — `crates/cli` Cargo binary and integration tests
- `macos` — `crates/ui` (ViewState / simulation / guardrails) + `crates/ffi` (UniFFI) + `apps/macos` (dumb SwiftUI binder)

New projects default to **cli + macos**. Domain logic belongs only in `crates/core`. UI policy belongs in `crates/ui`. See [`docs/ui-runtime.md`](docs/ui-runtime.md).

Standard Rust verification (includes UI simulation tests when macOS is enabled):

```bash
cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace
```

When the `macos` product is enabled, Compass also runs the macOS product gate inside the embedded macOS VM (Apple Virtualization.framework) — UniFFI bindings + `swift build` / `swift test`. Headed launch + Accessibility assert + screenshot is **opt-in** via `COMPASS_MACOS_UI_FIDELITY=1` (default off; primary UI proof is `crates/ui` simulation):

```bash
bash scripts/verify-macos.sh
COMPASS_MACOS_UI_FIDELITY=1 bash scripts/verify-macos.sh
```

Coverage is collected after verify with:

```bash
cargo llvm-cov --workspace --summary-only
```

Mutation testing runs post-verify scoped to the Rust files changed in the iteration (`cargo mutants --no-shuffle -j 1`), persisted to `.compass/mutation-snapshot.json` and fed into the next Plan pass. After mutation, Compass dirt-cleans the guest worktree (`target/`, `mutants.out*`, etc.) so build junk does not accumulate.

Acceptance gates (optional) live under `acceptanceGates` in `.compass/state.json` or via environment (`COMPASS_GATE_MIN_COVERAGE`, `COMPASS_GATE_MIN_MUTATION_SCORE`, `COMPASS_GATE_MAX_MISSED_MUTANTS`). When set, a green verify is not enough — the iteration is retried until the collected coverage/mutation evidence satisfies the gates.

## Runtime

### Cloud (primary)

Configure any OpenAI-compatible chat-completions endpoint in Settings or via environment:

- `COMPASS_AGENT_TEXT_PROVIDER=openAICompatible` (default)
- `COMPASS_AGENT_BASE_URL` (example empty-state: `https://api.moonshot.ai/v1`)
- `COMPASS_AGENT_API_KEY`
- `COMPASS_AGENT_MODEL`
- `COMPASS_AGENT_CONTEXT_WINDOW_TOKENS`

Kimi/Moonshot, OpenAI, OpenRouter, and local proxies all work the same way as long as they speak `/v1/chat/completions`. For CLI use, copy `.env.example` to `.env` in the repo root — `compass-cli` loads it automatically (real environment variables win; `.env` is gitignored).

### Local assist (optional)

MLX can run `mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit` after user-approved download into Compass Application Support. It is used for cheap assist tasks when available; cloud-only installs remain supported.

### Embedded macOS VM

Factory bash/verify run inside an embedded macOS VM (Apple Virtualization.framework):

- Guest toolchain: Xcode CLT (swift, clang, XCTest via `swift test`), Rust via rustup (cargo, rustc, rustfmt, clippy), cargo-llvm-cov, cargo-mutants, ripgrep. Project Git stays on the host; the guest worktree has no `.git`.
- Repo sync: host worktree → guest worktree over a CAS (content-addressed store) channel on vsock (tar fallback); `/workspace` paths in commands map to the guest worktree
- Workspace reset: `compass-cli vm reset-workspace --repo <path> [--dirt|--full]` discards per-repo guest dirt without reprovisioning

File/search tools still operate on the host worktree, addressed through the same `/workspace` path space.

Compass requires the embedded macOS VM for all factory bash, verify, coverage, and mutation. There is no host-shell escape hatch.

## Development

Build and test the macOS host with SwiftPM:

```bash
swift test
```

Headless CLI modes: `auto` (cloud when configured, else MLX), `cloud`, `mlx`, `fixture`.

Each `compass-cli run` executes one factory session (Plan → Develop → Verify → optional Critic). Useful `run` flags:

- `--sessions <n>` — run `n` factory sessions back-to-back in one invocation (stops on the first failed session; prompt logs are scoped per iteration).
- `--max-iterations <n>` — agent tool-turn budget per phase (Plan / Develop / Critic), not the number of factory sessions. Default 24.
- `--max-develop-attempts <n>` / `--max-verify-repairs <n>` — retry budgets when Develop post-checks or verify fail.
- `--commit` — after each successful session, commit the iteration's changes to Git (`Compass iteration <n>: <summary>`), giving you per-iteration history and easy rollback.

Legacy project files in existing user workspaces are ignored rather than deleted.
