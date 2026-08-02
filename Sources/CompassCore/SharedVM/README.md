# Shared VM

Compass uses a macOS Virtualization.framework VM as an isolated execution surface for building and verifying generated projects on a real macOS toolchain.

The guest is provisioned with:

- Xcode Command Line Tools
- Homebrew
- ripgrep
- Node.js
- npm
- Corepack/pnpm

Agents and quality gates reach the guest through the Compass-owned vsock RPC (`CompassAgentRPC` + the in-guest `CompassGuestAgent`): filesystem ops and bash run against the per-repo guest worktree synced by `SharedCompassVMRepoWorkspaceSync`. Generated projects are Rust Cargo workspaces with an optional SwiftUI macOS app, so `swift build`, `swift test`, and `bash scripts/verify-macos.sh` are the primary commands the VM must support; the macOS product gate runs through `AgentMacOSVMBashRunner` via `MacOSVerifyGate` with host-shell fallback.
