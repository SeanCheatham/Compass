# Shared VM

Compass uses a macOS Virtualization.framework VM as an isolated execution surface for building and verifying generated projects on a real macOS toolchain.

The guest is provisioned with:

- Xcode Command Line Tools
- Homebrew
- ripgrep
- OpenSSL + pkgconf (for Rust `-sys` crates such as `openssl-sys`)
- Rust (rustup stable: cargo, rustc, rustfmt, clippy)

Agents and quality gates reach the guest through the Compass-owned vsock RPC (`CompassAgentRPC` + the in-guest `CompassGuestAgent`): filesystem ops and bash run against the per-repo guest worktree (paths jails under the guest repos root). Repos reach the guest primarily over content-addressed vsock sync (`SharedCompassVMCASSync` — path→hash manifest, missing blobs into `Repos/<id>/objects/`, in-place worktree materialize preserving gitignored build dirs like `target/` and `.build/`); wipe-style tar (`SharedCompassVMWorktreeSync`) remains as a logged fallback when CAS fails or on force refresh. The guest worktree has no `.git` — project Git remains on the host. Guest-side agent changes are pulled back with the **same** transport as the inbound sync (`pullAfterRun`: CAS pull, or tar `pullAndRecord`). After SSH is up the host re-applies graphical auto-login (`SharedCompassVMAutoLoginRepair`) so the headed Desktop skips the password prompt; Settings → macOS VM exposes Desktop (framebuffer), Console (readiness + guest log tail), Repair Auto-Login, Reset Guest Workspace (full wipe of that project's `Repos/<id>` + force sync), and a grow-only Disk capacity slider (stop the VM, choose 64–512 GiB, Apply). Generated projects are Rust Cargo workspaces with an optional SwiftUI macOS app, so `cargo fmt/clippy/test`, `swift build`, `swift test`, and `bash scripts/verify-macos.sh` are the primary commands the VM must support; the macOS product gate runs through `AgentMacOSVMBashRunner` via `MacOSVerifyGate` (VM only — no host fallback). See `docs/host-guest-cas-sync.md`.

## Disk capacity

The guest disk is a sparse host `Disk.img` (default **64 GiB**). Runtime → Apply Disk Size extends the image (grow-only; VM must be stopped), boots the guest, and runs `diskutil apfs resizeContainer … 0` so APFS claims the new free space. Preferred size is persisted in `state.json` (`lastBundleSize`) and reused after Reset + re-provision. Apply at the current size re-runs only the guest APFS resize (recovery if a prior grow enlarged the host image but failed inside the guest).
## Product-runtime verify

When a project includes the `macos` product, `scripts/verify-macos.sh` runs bindings + `swift build` + `swift test`. Primary UI proof is `crates/ui` simulation under `cargo test`. Headed fidelity is opt-in: set `COMPASS_MACOS_UI_FIDELITY=1` so `scripts/macos-ui-smoke.sh` bundles `GeneratedApp.app`, launches it in the guest Aqua session via `launchctl asuser`, Accessibility-asserts `greeting.label` / `greeting.caption`, and writes `apps/macos/dist/ui-smoke.png`. Compass best-effort repairs auto-login only when fidelity is enabled, and copies the PNG into the session audit manifest when present.

## Workspace blast radius

One shared guest OS/toolchain serves every project. Per-repo isolation lives under `/Users/compass/Compass/Repos/<uuid>/`. Use `compass-cli vm reset-workspace --repo <path> [--dirt|--full]` (default `--full`) or Settings → Reset Guest Workspace to discard Develop mess without reprovisioning:

- `--dirt` — remove `target/`, `.build/`, `apps/macos/dist`, `mutants.out*`, etc. inside the existing worktree
- `--full` — delete `Repos/<id>`, rotate `.compass/guest-workspace.json`, force-sync a fresh tree

Mutation collection automatically runs a `--dirt` cleanup afterward so mutant trees do not accumulate across iterations.
