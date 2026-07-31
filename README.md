# Compass

Compass is a macOS-native local software factory for Git repositories.

The current direction:

- Factory turns (Plan / Develop / Critic) use a user-configured **OpenAI-compatible** cloud endpoint (`base URL` + `API key` + `model`).
- Optional **MLX** local assist handles cheap/small work (narration, compaction, Explore helpers) when the blessed local model is downloaded.
- Compass does deterministic work through local tools and the containerized Linux runtime.
- Generated projects are Rust Cargo workspaces (backend/CLI only — no web UI).

## Factory Loop

Compass keeps a small persisted factory state in `.compass/state.json`:

- `brief`: summary, target users, desired outcomes, constraints, and acceptance signals.
- `queue`: decomposed work items.
- `immediate`: the selected implementation packet for the next Develop pass.
- `completed`: completed iteration notes.
- `openQuestions`: unresolved questions that affect scope.

The v1 loop is:

1. Brief
2. Decompose queue
3. Select immediate work
4. Develop
5. Verify
6. Critic

Activity/Live is the primary project surface.

## Generated Projects

Compass-generated output is Rust only. New projects use a Cargo workspace:

- root `Cargo.toml` workspace manifest
- `rust-toolchain.toml` (stable + rustfmt + clippy)
- `crates/app-core` — shared library and domain logic
- `crates/app-cli` — CLI entry point and integration tests

There is no web or desktop UI package in generated output.

Standard verification:

```bash
cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace
```

Coverage is collected after verify with:

```bash
cargo llvm-cov --workspace --summary-only
```

Mutation testing is planned (`cargo mutants`) but not wired into the factory loop yet.

## Runtime

### Cloud (primary)

Configure any OpenAI-compatible chat-completions endpoint in Settings or via environment:

- `COMPASS_AGENT_TEXT_PROVIDER=openAICompatible` (default)
- `COMPASS_AGENT_BASE_URL` (example empty-state: `https://api.moonshot.ai/v1`)
- `COMPASS_AGENT_API_KEY`
- `COMPASS_AGENT_MODEL`
- `COMPASS_AGENT_CONTEXT_WINDOW_TOKENS`

Kimi/Moonshot, OpenAI, OpenRouter, and local proxies all work the same way as long as they speak `/v1/chat/completions`.

### Local assist (optional)

MLX can run `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit` after user-approved download into Compass Application Support. It is used for cheap assist tasks when available; cloud-only installs remain supported.

### Containerized Linux

Factory bash/verify run in ephemeral Apple Containerization Linux VMs:

- Image: `docker.io/library/rust:1-bookworm`
- Repo mount: host worktree → `/workspace`
- Bootstrap: Rust toolchain (cargo, rustc, rustfmt, clippy)

File/search tools still operate on the host worktree, addressed through the same `/workspace` path space.

## Development

Build and test the macOS host with SwiftPM:

```bash
swift test
```

Headless CLI modes: `auto` (cloud when configured, else MLX), `cloud`, `mlx`, `fixture`.

Legacy project files in existing user workspaces are ignored rather than deleted.
