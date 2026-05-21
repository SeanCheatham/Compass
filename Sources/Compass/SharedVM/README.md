# SharedVM module

Native macOS guest VM that Compass uses to isolate Develop iterations from
the host. Built directly on `Virtualization.framework`; no external tooling
(Tart, Docker, etc.) is required.

## Lifecycle

```
warmup ──▶ notProvisioned ──▶ downloadingIPSW ──▶ installing
                                                       │
                                          (host mounts disk, plants
                                           LaunchDaemon + bootstrap
                                           script + sudoers fragment +
                                           AppleSetupDone marker — one
                                           admin auth prompt)
                                                       │
                                                       ▼
                                                guestPrepping
                                                       │
                                          (VM boots; planted LaunchDaemon
                                           creates compass user, plants
                                           SSH key, enables sshd; host
                                           polls SSH until reachable)
                                                       │
                                                       ▼
                                                    ready
```

`unavailable(reason:)` and `error(detail:)` are absorbing states reached from
any other point on detection of the Apple 2-guest cap, missing hardware
support, installer failure, or a cancelled host admin prompt.

## Threading invariants

- All `VZVirtualMachine` and `VZVirtualMachineConfiguration` access happens on
  the main actor. `SharedCompassVM` is `@MainActor final class`, not a
  `nonisolated actor`, because the underlying framework asserts on main-queue
  use.
- Long-running work (IPSW download, install) runs via `Task.detached` and
  reports progress back to main via `AsyncStream<Double>` or
  `@Published` properties.
- `NSWorkspace.willSleepNotification` / `didWakeNotification` observers call
  `pause()` / `resume()` to prevent guest clock skew from breaking SSH
  sessions and git timestamps across host sleep cycles.

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
Files` symlink, so the agent sees the worktree at
`/opt/compass/workspaces/dev-<UUID>/worktree`.

## Agent transport — vsock, not SSH

Compass talks to the in-guest world via two separate transports, each
with a specific TCC-imposed constraint:

- **SSH** is used only for low-level setup probes (readiness ping,
  known_hosts seeding, first-boot diagnostics dump). sshd-spawned
  processes on macOS guests are TCC-blocked from reading VirtioFS-mounted
  shares regardless of UID — every `ls`/`cat` through ssh returns EPERM
  on `/opt/compass/workspaces/...`. So ssh never touches worktree files.
- **vsock** is used for every agent tool call (read_file / write_file /
  edit_file / ls / glob / grep / bash) and for any future RPC into the
  guest. The host calls `VZVirtioSocketDevice.connect(toPort:)` to open
  a fresh connection per request; the in-guest `CompassGuestAgent` binary
  listens on `AF_VSOCK` at port `0x4007ACE5`. Wire format is length-prefixed
  JSON (see `Sources/CompassAgentRPC/`).

The guest agent is a separate SwiftPM target (`CompassGuestAgent`) shipped
alongside the host binary and planted at `/usr/local/libexec/compass-guest-agent`
during first-boot. It runs as a `LaunchAgent` (`/Library/LaunchAgents/com.seancheatham.Compass.guest-agent.plist`),
which is the key TCC distinction: LaunchAgents load inside the GUI user
session and inherit that session's TCC profile — the one VirtioFS shares
*are* accessible to. LaunchDaemons (or sshd children) inherit the system
context, where they are not.

For the LaunchAgent to actually load, a GUI user session has to exist.
First-boot writes `/etc/kcpassword` (Apple's XOR-obfuscated auto-login
format) and sets `autoLoginUser=compass` so the guest reaches a desktop
session unattended. The agent comes up moments later.

## Failure modes and recovery

- **Bundle not provisioned**: readiness is `.notProvisioned`. The Sandbox view
  shows a "Provision Shared VM" button; clicking it kicks off
  `provisionIfNeeded()`.
- **IPSW download fails**: download is resumable; on retry the partial file
  is reused.
- **Installer fails**: readiness moves to `.error(detail:)`. The Sandbox view
  surfaces destructive recovery: reset installed artifacts, or rebuild from a
  local IPSW. Reset removes the VM disk, auxiliary storage, hardware identity,
  stale known-hosts entry, and the guest password's Keychain entry while
  preserving the IPSW cache and Compass SSH keypair.
- **Headless planter prompt cancelled**: readiness moves to `.error(detail:)`
  with a message about the dismissed administrator prompt. The user clicks
  Reset + Provision to retry; the install will re-run from scratch because
  the on-disk image is wiped during reset. (Future optimisation: skip the
  install step when the disk is already populated and only the plant
  failed.)
- **Boot loops**: `state.json.bootAttemptCounter` is incremented on every
  start attempt. After 3 consecutive failures from a previously-ready bundle,
  the Sandbox view surfaces a "Rebuild VM" affordance (also future).
- **Apple 2-guest cap reached**: detected at `start()` via
  `VZError.virtualMachineLimitExceeded`; the per-project picker disables
  `.sharedVM` and the launch planner falls back to `.host` with a clear
  `fallbackReason`.
## Decision log

- **Why direct Virtualization.framework instead of Tart?** Compass is a
  native macOS app that already targets a single architecture; bundling a
  CLI dependency for image management would inflate the install surface.
  The only meaningful thing Tart adds over native VZ is the OCI-registry
  image distribution mechanism — Compass replaces that with first-run IPSW
  fetch from Apple's CDN (~14 GB, no auth required), plus a local IPSW picker
  for hosts where Apple's catalog fetch fails.
- **Why headless first-boot via planted LaunchDaemon instead of interactive
  Setup Assistant?** Earlier Compass shipped an interactive flow that
  required the user to click through Setup Assistant and invent a guest
  password. Both were UX taxes for a per-host one-time setup, and the
  password was a security smell because nothing in Compass needed the user
  to remember it. The headless replacement mounts the just-installed Data
  volume on the host, plants `/var/db/.AppleSetupDone` + a one-shot
  LaunchDaemon + a bootstrap script + the sudoers fragment, then unmounts.
  The guest's first boot runs the LaunchDaemon, which creates the `compass`
  admin user with a random Keychain-stored password, authorises the
  Compass SSH key, and enables Remote Login — all without any user
  interaction. Per-major macOS profiles live in
  [SharedCompassVMHeadlessFirstBoot.swift](SharedCompassVMHeadlessFirstBoot.swift)
  so future Apple changes to Setup Assistant internals are a one-line
  override rather than a refactor. The cost is one admin authentication
  prompt during provisioning (NSAppleScript `do shell script ... with
  administrator privileges`) so the host can write root-owned files into
  the mounted Data volume.
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

## How Develop reaches the guest today

The Codex surface that originally drove this module was removed in the
phase 7 cleanup. The current entry point is `AgentBashTool` (Develop's
`bash` tool); the `AgentSharedVMBashRunner` in `AgentTools/` builds the
SSH argv via `SharedCompassVMGuestBridge` and runs `/bin/zsh -lc <command>`
in the guest's mirror of the host worktree. Plan/Reflect remain
host-native (read-only file tools only).
