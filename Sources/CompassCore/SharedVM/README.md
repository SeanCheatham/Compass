# Shared VM

Compass uses a macOS Virtualization.framework VM as an isolated execution surface for building and verifying generated projects on a real macOS toolchain.

The guest is provisioned with:

- Xcode Command Line Tools
- Homebrew
- ripgrep
- Rust (rustup stable: cargo, rustc, rustfmt, clippy)

Agents and quality gates reach the guest through the Compass-owned vsock RPC (`CompassAgentRPC` + the in-guest `CompassGuestAgent`): filesystem ops and bash run against the per-repo guest worktree. Repos reach the guest primarily over git-over-SSH (`SharedCompassVMGitSSHSync` — the host pushes a temporary-index snapshot commit to a bare exchange repo in the guest, and the guest worktree hard-resets to it, preserving gitignored build state like `target/` and `.build/`); the tar push (`SharedCompassVMWorktreeSync`) remains as fallback. Guest-side changes can be pulled back via the sync-back ref. Generated projects are Rust Cargo workspaces with an optional SwiftUI macOS app, so `cargo fmt/clippy/test`, `swift build`, `swift test`, and `bash scripts/verify-macos.sh` are the primary commands the VM must support; the macOS product gate runs through `AgentMacOSVMBashRunner` via `MacOSVerifyGate` with host-shell fallback.

