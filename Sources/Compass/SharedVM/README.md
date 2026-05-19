# SharedVM module

Native macOS guest VM that Compass uses to isolate Develop iterations from
the host. Built directly on `Virtualization.framework`; no external tooling
(Tart, Docker, etc.) is required.

## Lifecycle

```
warmup ──▶ notProvisioned ──▶ downloadingIPSW ──▶ installing ──▶ firstBootPending
                                                                       │
                                                                       ▼
                                                            (user clicks "Mark
                                                             setup complete")
                                                                       │
                                                                       ▼
                                                                guestPrepping
                                                                       │
                                                            (CLT install + SSH
                                                             keypair injection
                                                             + codex auth check
                                                             /copy)
                                                                       │
                                                                       ▼
                                                              codexLoginPending
                                                                  (if needed)
                                                                       │
                                                                       ▼
                                                                    ready
```

`unavailable(reason:)` and `error(detail:)` are absorbing states reached from
any other point on detection of the Apple 2-guest cap, missing hardware
support, or installer failure.

## Threading invariants

- All `VZVirtualMachine` and `VZVirtualMachineConfiguration` access happens on
  the main actor. `SharedCompassVM` is `@MainActor final class`, not a
  `nonisolated actor`, because the underlying framework asserts on main-queue
  use.
- Long-running work (IPSW download, install) runs via `Task.detached` and
  reports progress back to main via `AsyncStream<Double>` or
  `@Published` properties.
- `NSWorkspace.willSleepNotification` / `didWakeNotification` observers call
  `pause()` / `resume()` to prevent guest clock skew from breaking codex
  tokens and git timestamps across host sleep cycles.

## On-disk layout

```
~/Library/Application Support/Compass/SharedVM/
└── bundle.vmbundle/
    ├── Disk.img                       # sparse 64 GiB, grows with use
    ├── AuxiliaryStorage
    ├── HardwareModel
    ├── MachineIdentifier
    ├── state.json                     # Compass-owned: provisionStep,
    │                                  # lastKnownGoodIP, guestUserName,
    │                                  # codexLoginCompleted,
    │                                  # bootAttemptCounter, lastBundleSize
    ├── known_hosts                    # Compass-owned ssh trust store
    ├── id_ed25519                     # Compass-owned SSH private key
    ├── id_ed25519.pub
    └── cache/
        └── RestoreImage-<version>.ipsw   # resumable; survives across launches
```

Per-project Develop worktrees live separately, under
`~/Library/Caches/Compass/Worktrees/dev-<UUID>/worktree`. The single
permanent VirtioFS share at tag `compass-workspaces` exposes the
`~/Library/Caches/Compass/Worktrees/` parent directory to the guest. Inside
the guest the share is reached via the `/opt/compass → /Volumes/My Shared
Files` symlink, so codex sees the worktree at
`/opt/compass/workspaces/dev-<UUID>/worktree`.

## Failure modes and recovery

- **Bundle not provisioned**: readiness is `.notProvisioned`. The Sandbox view
  shows a "Provision Shared VM" button; clicking it kicks off
  `provisionIfNeeded()`.
- **IPSW download fails**: download is resumable; on retry the partial file
  is reused.
- **Installer fails**: readiness moves to `.error(detail:)`. Partial bundle
  is left on disk for inspection; a future "Rebuild VM" action will
  surface destructive recovery (Phase 8 — not yet implemented).
- **Boot loops**: `state.json.bootAttemptCounter` is incremented on every
  start attempt. After 3 consecutive failures from a previously-ready bundle,
  the Sandbox view surfaces a "Rebuild VM" affordance (also future).
- **Apple 2-guest cap reached**: detected at `start()` via
  `VZError.virtualMachineLimitExceeded`; the per-project picker disables
  `.sharedVM` and the launch planner falls back to `.host` with a clear
  `fallbackReason`.
- **Codex token expiry**: guest's `~/.codex` carries its own writable copy
  (initially seeded from host via SSH on provision). If the guest token
  expires, the auth bridge surfaces `.codexLoginPending`; the user can
  re-run `codex login` inside the embedded VM view, or trigger a re-copy
  from host.

## Decision log

- **Why direct Virtualization.framework instead of Tart?** Compass is a
  native macOS app that already targets a single architecture; bundling a
  CLI dependency for image management would inflate the install surface.
  The only meaningful thing Tart adds over native VZ is the OCI-registry
  image distribution mechanism — Compass replaces that with first-run IPSW
  fetch from Apple's CDN (~14 GB, no auth required).
- **Why interactive Setup Assistant instead of a headless first-boot
  injection?** The alternatives (`/var/db/.AppleSetupDone` writes, first-boot
  LaunchDaemons that pre-create users) are fragile across macOS releases
  and Apple typically ships yearly. A one-time ~2-minute click-through in
  the embedded VM view is acceptable friction for a per-host one-time
  setup.
- **Why Command Line Tools instead of full Xcode?** Compass's `Package.swift`
  is a SwiftPM macOS package — CLT supplies the Swift toolchain, macOS SDK,
  and `git`. Full Xcode (~30 GB extra, requires Apple ID) is unnecessary
  and not used by Compass's verify path.
- **Why always-on (with sleep/wake observers) instead of lazy?** First
  Develop iteration latency dominates user perception. Always-on keeps
  the cache warm and the VM responsive at the cost of ~4 GB idle RAM,
  which is acceptable on the Apple Silicon Macs Compass targets. The
  required sleep/wake observers prevent clock-skew corruption across
  host hibernation.
- **Why a single permanent VirtioFS parent share instead of per-project
  attach/detach?** `VZVirtualMachine.attachDevice` / `detachDevice` for
  VirtioFS is not reliably hot-pluggable across macOS releases; a single
  parent share with host-created subdirectories is more robust.

## Phase 2-7 commits

- `b4e7312` Phase 2 — initial module construction.
- `4970fff` Phase 3 — wired into CodexExecutionLaunchPlan + CodexExecutor;
  added SharedCompassVMCodexAuthBridge; introduced
  `replaceConsoleAttachment` + `ensureSSHKeypair`.
- `be4cd56` Phase 4 — SwiftUI surface (`SandboxView` + sidebar integration).
- `ef8051c` Phase 5 — picker persistence.
- `43c5bf6` Phase 6 — unit tests for bundle / readiness / file-share / SSH
  argv assembly / availability check / migration semantics.
