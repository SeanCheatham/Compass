# Shared VM

Compass uses a macOS Virtualization.framework VM as an isolated execution surface for building and verifying generated projects on a real macOS toolchain.

The guest is provisioned with:

- Xcode Command Line Tools
- Homebrew
- ripgrep
- Rust (rustup stable: cargo, rustc, rustfmt, clippy)

Agents and quality gates reach the guest through the Compass-owned vsock RPC (`CompassAgentRPC` + the in-guest `CompassGuestAgent`): filesystem ops and bash run against the per-repo guest worktree (paths jails under the guest repos root). Repos reach the guest primarily over git-over-SSH (`SharedCompassVMGitSSHSync` — the host pushes a temporary-index snapshot commit to a bare exchange repo in the guest, and the guest worktree hard-resets to it, preserving gitignored build state like `target/` and `.build/`); the tar push (`SharedCompassVMWorktreeSync`) remains as fallback. Guest-side agent changes are pulled back via the sync-back ref (`pullAfterRun`). After SSH is up the host re-applies graphical auto-login (`SharedCompassVMAutoLoginRepair`) so the headed Desktop skips the password prompt; Settings → macOS VM exposes Desktop (framebuffer), Console (readiness + guest log tail), Repair Auto-Login, and Reset Guest Workspace (full wipe of that project's `Repos/<id>` + force sync). Generated projects are Rust Cargo workspaces with an optional SwiftUI macOS app, so `cargo fmt/clippy/test`, `swift build`, `swift test`, and `bash scripts/verify-macos.sh` are the primary commands the VM must support; the macOS product gate runs through `AgentMacOSVMBashRunner` via `MacOSVerifyGate` (VM only — no host fallback).

## Product-runtime verify

When a project includes the `macos` product, `scripts/verify-macos.sh` still runs bindings + `swift build` + `swift test`, then calls `scripts/macos-ui-smoke.sh`: bundle `GeneratedApp.app`, launch it in the guest Aqua session via `launchctl asuser`, Accessibility-assert `greeting.label` / `greeting.caption`, and write `apps/macos/dist/ui-smoke.png`. Compass best-effort repairs auto-login before the gate and copies the PNG into the session audit manifest. Set `COMPASS_MACOS_UI_SMOKE=0` to skip the UI smoke (build/test still run).

## Workspace blast radius

One shared guest OS/toolchain serves every project. Per-repo isolation lives under `/Users/compass/Compass/Repos/<uuid>/`. Use `compass-cli vm reset-workspace --repo <path> [--dirt|--full]` (default `--full`) or Settings → Reset Guest Workspace to discard Develop mess without reprovisioning:

- `--dirt` — remove `target/`, `.build/`, `apps/macos/dist`, `mutants.out*`, etc. inside the existing worktree
- `--full` — delete `Repos/<id>`, rotate `.compass/guest-workspace.json`, force-sync a fresh tree

Mutation collection automatically runs a `--dirt` cleanup afterward so mutant trees do not accumulate across iterations.
