# Compass Architecture

Compass is a native macOS host around a local software factory loop.

## Host

The Swift/macOS app owns projects, workspace state, Activity/Live UI, prompt assembly, tool execution, and Shared VM lifecycle.

## Model Backends

Text generation goes through `LocalModelGenerating`:

- **OpenAI-compatible cloud** (`OpenAICompatibleModelRuntime`) — primary for Plan / Develop / Critic.
- **MLX local** (`MLXLocalModelRuntime`) — preferred for cheap assist (compaction, narrators, Explore) when the blessed model is downloaded.
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

Legacy state files from older projects are ignored in-place.

## Generated Output

Compass-generated projects use a TypeScript pnpm workspace with `packages/core`, `packages/cli`, and `packages/web`.

## Shared VM

The Shared VM provides a deterministic execution surface for generated TypeScript work. Default provisioning installs Command Line Tools, Homebrew, ripgrep, Node.js, npm, Corepack/pnpm, and TypeScript.
