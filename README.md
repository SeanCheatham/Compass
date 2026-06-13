# Compass

Compass is a macOS-native local software factory for Git repositories.

The current direction is intentionally narrow:

- MLX is the only model backend.
- Compass does deterministic work through local tools and the Shared VM.
- Model calls are reserved for decomposition, implementation text, and review.
- Generated projects are Tessera app workspaces.

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

Compass-generated output is Tessera by default. New projects use:

- `tessera.json`
- `src/*.tes`
- `contexts/*.json`
- `tests/*.json`
- `cli` and `web-json` manifest entrypoints

The generated stack is a small-model-friendly Tessera app contract. The current web replacement is an explicit `web-json` entrypoint until Tessera grows a full UI runtime.

Standard root scripts:

```bash
tessera verify . --json
tessera app cli --json
tessera app web --json
```

## Runtime

Compass runs model work locally through native Swift MLX with `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit`. The model is downloaded only after user approval into Compass Application Support. There are no API keys, remote text providers, media providers, or provider routing settings in this build.

The Shared VM/tooling path expects this generated-project toolchain:

- Xcode Command Line Tools
- Homebrew
- ripgrep
- Node.js and Corepack/pnpm for legacy TypeScript repositories
- `tessera` CLI on `PATH` for generated Tessera app verification

Until Compass packages Tessera into the runtime image directly, install or link the Tessera CLI
before running generated Tessera verification inside that environment.

## Development

Build and test the macOS host with SwiftPM:

```bash
./scripts/test-local.sh
```

Run the Rust engine bridge checks with Cargo:

```bash
./scripts/test-rust-engine.sh
```

Format Swift sources before larger changes:

```bash
./scripts/format.sh
```

Legacy project files in existing user workspaces are ignored rather than deleted. The repository code for the previous product-factory, market, provider, and non-TypeScript generated-output systems has been removed for this pivot.
