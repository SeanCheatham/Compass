# Shared VM

Compass uses a macOS Virtualization-based Shared VM as the isolated execution surface for generated project work.

The guest is provisioned with:

- Xcode Command Line Tools
- Homebrew
- ripgrep
- Node.js
- npm
- Corepack/pnpm
- TypeScript

Agents use the guest through Compass-owned filesystem, shell, and toolchain APIs. Generated projects are TypeScript pnpm workspaces, so `pnpm verify`, `pnpm test -- --coverage`, `pnpm build`, and `pnpm typecheck` are the primary commands the VM must support.
