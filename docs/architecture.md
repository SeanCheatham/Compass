# Compass Architecture

Compass is a native macOS host around a local software factory loop.

## Host

The Swift/macOS app owns projects, workspace state, Activity/Live UI, prompt assembly, tool execution, and Shared VM lifecycle.

## Model Backend

Native Swift MLX is the only model backend. Runtime settings are limited to local model availability and the context budget used when shaping prompts. The blessed v1 model is `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit`.

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

Compass-generated projects use a TypeScript pnpm workspace with `packages/core`, `packages/cli`, and `packages/web`.

## Shared VM

The Shared VM provides a deterministic execution surface for generated TypeScript work. Default provisioning installs Command Line Tools, Homebrew, ripgrep, Node.js, npm, Corepack/pnpm, and TypeScript.
