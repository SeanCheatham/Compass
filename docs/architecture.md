# Compass Architecture

Compass is a native macOS host around a local software factory loop.

## Host

The Swift/macOS app owns projects, workspace state, Activity/Live UI, prompt assembly, agent tools, local model orchestration, and Shared VM lifecycle. `CompassCore` carries the reusable factory state, prompt policy, forge profiles, generated-project scaffolds, repository exploration, and CLI behavior.

## Model Backend

Native Swift MLX is the only model backend. Runtime settings are limited to local model availability and the context budget used when shaping prompts. The blessed v1 model is `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit`.

## Rust Engine Bridge

`rust/compass-engine` exposes a narrow C ABI for Tessera verification and entrypoint execution. Swift loads the development dylib lazily during tests and local runs, or uses a bundled `libcompass_engine.dylib` when present. The FFI contract is JSON in, JSON envelope out, with panics caught before crossing back into Swift.

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

Compass-generated projects are Tessera app workspaces by default:

- `tessera.json`
- `src/*.tes`
- `contexts/*.json`
- `tests/*.json`
- `cli` and `web-json` manifest entrypoints

The legacy TypeScript pnpm workspace profile remains available for imported or older generated workspaces.

## Shared VM

The Shared VM provides a deterministic execution surface for local tools. Default provisioning covers Xcode Command Line Tools, Homebrew, ripgrep, Node.js/Corepack/pnpm for legacy TypeScript work, and the Tessera CLI for generated Tessera verification until Tessera is packaged directly into Compass.
