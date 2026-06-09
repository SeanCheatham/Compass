# Compass

Compass is a macOS-native local software factory for Git repositories.

The current direction is intentionally narrow:

- MLX is the only model backend.
- Compass does deterministic work through local tools and the Shared VM.
- Model calls are reserved for decomposition, implementation text, and review.
- Generated projects are TypeScript pnpm workspaces.

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

Compass-generated output is TypeScript only. New projects use:

- `pnpm-workspace.yaml`
- root `package.json`
- `tsconfig.base.json`
- `packages/core`
- `packages/cli`
- `packages/web`

The generated stack is strict TypeScript, Vite + React for web, Vitest coverage, and `tsx` for CLI/dev scripts.

Standard root scripts:

```bash
pnpm verify
pnpm test -- --coverage
pnpm build
pnpm typecheck
```

## Runtime

Compass runs model work locally through native Swift MLX with `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit`. The model is downloaded only after user approval into Compass Application Support. There are no API keys, remote text providers, media providers, or provider routing settings in this build.

The Shared VM provisions the default generated-project toolchain:

- Xcode Command Line Tools
- Homebrew
- ripgrep
- Node.js
- npm
- Corepack/pnpm
- TypeScript

## Development

Build and test the macOS host with SwiftPM:

```bash
swift test
```

Legacy project files in existing user workspaces are ignored rather than deleted. The repository code for the previous product-factory, market, provider, and non-TypeScript generated-output systems has been removed for this pivot.
