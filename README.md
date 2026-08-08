# Compass

Compass is a macOS-native local software factory **and** repo health improver for Git repositories.

Two project kinds:

- **Factory** — Plan → Develop → Verify → Critic → **Health** (Plan pressure) → Requirements Audit.
- **Health** — import an arbitrary Rust repo and run recon → focused pass (bug hunt / tests / docs / cleanup) → triage; proposed patches land on a Compass-owned git branch.

The current direction:

- Factory / health agent turns use a user-configured **OpenAI-compatible** cloud endpoint (`base URL` + `API key` + `model`).
- Optional **MLX** local assist handles cheap/small work (e.g. Studio thinking narration) when the blessed local model is downloaded. Transcript compaction uses the cloud endpoint.
- Compass does deterministic work through local tools and the embedded macOS VM (including health `cargo test`).
- Factory-generated projects require Rust `crates/core` plus at least one product: `cli`, `macos`, and/or `server` (default `cli+macos`). Domain logic stays in Rust; UI policy in `crates/ui`; macOS uses UniFFI + a dumb SwiftUI binder; server is an axum HTTP adapter.

## Factory Loop

Compass keeps a small persisted factory state in `.compass/state.json`:

- `projectKind`: `factory` (default) or `health`.
- `brief`: Plan-owned strategic context (summary, target users, desired outcomes, constraints, acceptance signals).
- `queue`: decomposed work items.
- `immediate`: the selected implementation packet for the next Develop pass.
- `completed`: completed iteration notes.
- `openQuestions`: unresolved questions that affect scope.
- `products`: enabled generated-project products (`cli`, `macos`, and/or `server`).
- `successfulShipCount` / optional `macosFidelityCadence`: drive headed macOS UI fidelity every N ships (default 5).

User product intent lives in `.compass/brief.json` (audience, problem, product requirements) and is edited in the Brief tab or passed to `compass-cli run` via `--audience`, `--problem`, and `--requirement`. New projects can use **Random idea** on the Brief tab to fill a curated starter brief.

Factory-owned requirement verification lives in `.compass/requirements.json` (criteria, Given/When/Then scenarios, owned paths, ship traces, audit verdicts). Each product requirement has a `kind` and `proofLevel`. Plan must link slices via `immediate.targetedRequirementIDs` while requirements remain incomplete. After Critic approves a slice, Compass records a ship trace, may mark other requirements stale when owned paths changed, and runs an incremental audit. When Plan returns no immediate work, a full audit must find every requirement satisfied before the loop declares done; otherwise findings are fed back into Plan. Auto-play continues after a successful Develop (which retires Immediate Work) so the next Plan can address still-open requirements — Develop success alone is not “all requirements verified.”

After every successful Critic/ship, Compass runs a **health pass** (fail-open, bug-hunt focus, in-tree). Findings persist to `.compass/health-snapshot.json` / `.compass/findings.json`, show in the **Results** tab, and feed the next Plan prompt as pressure (same idea as coverage/mutation snapshots). Health does not auto-open requirements ledger entries.

The v1 factory loop is:

1. Brief
2. Decompose queue
3. Select immediate work (optionally targeting product requirements)
4. Develop
5. Verify
6. Critic
7. Health (Plan pressure)
8. Requirements audit (incremental after ship; full audit before loop completion)

## Health projects

**Open Health** (sidebar / menu) or `compass-cli health run --repo <path>` imports a Rust Git root as `projectKind: health`. Each pass samples a focus (`bugHunt`, `test`, `docs`, `cleanup`) with focus-scoped writes; proposed patches commit on `compass/health/<projectId>` then the user’s previous branch is restored. Health turn/time budgets are in-memory (Activity **Turns** / **Min** controls) or CLI `--max-iterations` / `--wall-clock-secs` — not stored in `.compass/state.json`. Defaults are 128 turns / 2 hours. Optional `--focus` pins the dimension. Eval scoring against a fixture `bugs.toml` is available via `compass-cli health eval --repo <path> --bugs <bugs.toml>` (see `Fixtures/Health/`).

Activity/Live is the primary run surface; **Results** shows the latest health snapshot (findings, focus, branch commits).

## Generated Projects

Compass-generated output requires a Rust `crates/core` library plus at least one product:

- `cli` — `crates/cli` Cargo binary and golden-output integration tests
- `macos` — `crates/ui` (ViewState / simulation / guardrails) + `crates/ffi` (UniFFI) + `apps/macos` (dumb SwiftUI binder)
- `server` — `crates/server` axum HTTP adapter with in-process endpoint integration tests

New projects default to **cli + macos** (picker also offers `server`). Domain logic belongs only in `crates/core`. UI policy belongs in `crates/ui`. See [`docs/ui-runtime.md`](docs/ui-runtime.md).

Standard Rust verification (includes UI simulation tests when macOS is enabled, and server HTTP tests when server is enabled):

```bash
cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace
```

When the `macos` product is enabled, Compass also runs the macOS product gate inside the embedded macOS VM (Apple Virtualization.framework) — UniFFI bindings + `swift build` / `swift run FFIChecks` (not XCTest). Headed launch + Accessibility assert + screenshot is available via `COMPASS_MACOS_UI_FIDELITY=1`, and also runs automatically every N successful ships (default 5; override with `macosFidelityCadence` in `.compass/state.json`):

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

- Guest toolchain: Xcode CLT (swift, clang, XCTest via `swift test`), Rust via rustup (cargo, rustc, rustfmt, clippy), cargo-llvm-cov, cargo-mutants, ripgrep, OpenSSL + pkgconf. Project Git stays on the host; the guest worktree has no `.git`.
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
