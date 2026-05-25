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
                                            provisioningDevTools
                                                       │
                                          (host kicks off one-shot
                                           LaunchDaemons over vsock:
                                           first softwareupdate -i for
                                           Xcode Command Line Tools,
                                           then builds and installs Muter
                                           for Swift mutation testing;
                                           host polls sentinel files and
                                           surfaces phase progress)
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

Per-repo persistent guest workspaces live at
`/Users/compass/Compass/Repos/<UUID>/worktree` inside the guest. The
UUID is allocated on first use and persisted host-side in the
gitignored `<repo>/.compass/guest-workspace.json` so the same guest
directory survives across sessions, iterations, and app restarts.
This is the **source of truth** for the agent — every Plan, Reflect,
Develop, and Verify call against this repo operates on it.

There are no per-iteration host worktrees anymore. On Verify success
the guest workspace is packed and pulled directly into the main host
checkout via `AppModel.pullDevelopChangesIfNeeded`, and Compass runs
`git add -A` + `git commit` there on behalf of the agent (the guest
has no `.git`).

There is no VirtioFS share. We tried it; macOS guests TCC-block
`AppleVirtIOFS` reads from every process (sshd children, LaunchDaemons
running as root, *and* LaunchAgents in the GUI session). The
`SharedCompassVMFileShare` helpers and `SharedCompassVMConfiguration`'s
share-validation utilities still live in the source tree because the
tag-validation surface is reusable, but no `VZDirectorySharingDeviceConfiguration`
is attached to the running VM.

## Agent transport — vsock + worktree sync

Compass uses three host↔guest transports, each scoped to what it is
allowed to touch:

- **SSH** — setup probes only (readiness ping, known_hosts seeding,
  first-boot diagnostics dump). sshd children can't read AppleVirtIOFS
  anyway, and we no longer expect them to: SSH never touches worktree
  files.
- **vsock** — every agent tool call (read_file / write_file / edit_file
  / ls / glob / grep / bash) **for every phase** (Plan, Reflect,
  Develop, Verify) and the bulk worktree sync. The host calls
  `VZVirtioSocketDevice.connect(toPort:)` to open a fresh connection per
  request; the in-guest `CompassGuestAgent` binary listens on `AF_VSOCK`
  at port `0x4007ACE5`. Wire format is length-prefixed JSON
  (`Sources/CompassAgentRPC/`).
- **Worktree sync** (over vsock) — sync is lazy, asymmetric, and
  drift-checked:
    - **First time** a repo's persistent guest workspace is referenced
      (`SharedCompassVMRepoWorkspaceSync.ensurePopulated`), the host
      packages the repo as a gitignore-aware tar
      (`git ls-files --cached --others --exclude-standard | tar`),
      filtered to drop heavyweight build dirs (`.build`, `target`,
      `node_modules`, …) even when a repo's `.gitignore` omits them,
      streams it into the guest, and records a content fingerprint
      plus the matching file set in
      `<repo>/.compass/guest-workspace.json` + `guest-workspace-fileset.dat`.
    - **Subsequent sessions** recompute the host fingerprint
      ([SharedCompassVMHostFingerprint](SharedCompassVMHostFingerprint.swift) —
      SHA-256 over sorted `<path>\0<sha256(content)>\0` records) and
      compare it to the recorded value. On match the fast-path
      reuses the guest as-is, preserving accumulated agent state. On
      mismatch — typically because the user edited the repo while
      Compass was closed — Compass re-pushes so those edits show up
      in the session, surfacing the outcome as `.refreshedDueToHostDrift`
      in the log.
    - **After Verify passes** the guest packs its current worktree
      (excluding `.git`, `.build`, `target`, `node_modules`, `build`,
      `dist`, `.swiftpm`) into a tar that the host reads back over
      `readFile` and applies directly onto the main host repo.
      Deletions are scoped to the file set captured at the last
      push (intersected with files still present on host and absent
      from guest), so files the user added on the host between
      sessions survive even if the agent never saw them. After the
      pull, Compass re-stamps the fingerprint to reflect the new
      shared state. Compass then runs `git add -A` + `git commit -m "<agent summary>"`
      on the main repo so the iteration's commit lands where the
      rest of the toolchain expects it.
    - The guest never has `.git/`. The agent cannot commit there;
      committing is host-side only, gated on Verify success.
    - See [SharedCompassVMWorktreeSync.swift](SharedCompassVMWorktreeSync.swift)
      for the raw tar plumbing,
      [SharedCompassVMHostFingerprint.swift](SharedCompassVMHostFingerprint.swift)
      for the drift detector, and
      [SharedCompassVMRepoWorkspaceSync.swift](SharedCompassVMRepoWorkspaceSync.swift)
      for the session-level "fingerprint match? reuse. mismatch? re-push." policy.

The guest agent is a separate SwiftPM target (`CompassGuestAgent`)
shipped alongside the host binary and planted at
`/usr/local/libexec/compass-guest-agent` during first-boot. It runs as
a `LaunchAgent`
(`/Library/LaunchAgents/com.seancheatham.Compass.guest-agent.plist`)
under the auto-logged-in `compass` user, which means it operates on
guest-local files in `/Users/compass/Compass/Worktrees/...` — a
non-protected path on a non-VirtioFS filesystem, so TCC is irrelevant.

For the LaunchAgent to load, a GUI user session has to exist.
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
- **Why no VirtioFS share at all (phase 10)?** macOS 26 (and earlier
  majors per Apple's docs) TCC-block `AppleVirtIOFS` access from every
  process running in the guest — including LaunchAgents inside the GUI
  user session and root via LaunchDaemon. We verified this live: even
  Apple-signed `/bin/ls` returns "Operation not permitted" against the
  mount under both `launchctl asuser 501` and a proper `gui/501`-bootstrapped
  LaunchAgent. SIP is on; the TCC database is not writable from inside
  the guest. With no path that grants the agent read access, the share
  is just dead weight, so the VZ configuration no longer attaches one.
  Worktrees are vsock-synced instead (see [SharedCompassVMWorktreeSync.swift](SharedCompassVMWorktreeSync.swift)).
- **Why is the guest the source of truth, not the host?** Earlier
  Compass treated the host repo as primary and synced a snapshot of
  it into the guest per Develop iteration; Plan/Reflect stayed
  host-native because they "only read files." That left a sandbox
  leak: a Plan run on `/Users/<user>/git/<repo>` reads arbitrary host
  paths that resolve inside the working directory, including files
  with no business being visible to the agent (gitignored configs,
  `.env`, etc.). Inverting the polarity puts every phase inside the
  guest by default — Plan/Reflect/Develop/Verify all see only
  `/Users/compass/Compass/Repos/<UUID>/worktree`, never the host's
  home directory, and agent state accumulates across iterations and
  sessions instead of getting wiped per iteration. The host worktree
  still exists for git plumbing (commits, branches, promote), but the
  agent never reads or writes there directly. *Caveat:* between
  sessions the host re-asserts authority via the fingerprint check
  in `ensurePopulated` — if the user edited the repo while Compass
  was closed, those edits are pushed in before the agent runs, so
  the model is "guest is source of truth within a session, host
  re-anchors the guest at session start."
- **Why does the host commit the agent's changes instead of the agent?**
  The agent runs entirely inside the guest, where there is no `.git`
  (the bulk sync uses `git ls-files`, which doesn't include `.git/`).
  Syncing `.git` would bloat each push by tens of megabytes for no
  practical gain — the agent never needs to inspect history. So the
  agent edits files only and Compass commits host-side after Verify
  passes, using the agent's `summary` field as the commit message.
  This also gives Compass a natural gate: a failed Verify produces no
  commit, so a half-finished iteration cannot accidentally land on the
  branch.
- **Why gitignore-aware tar for sync instead of NFS / a host-side git
  daemon?** Both alternatives require running a network service on the
  host (port 2049 for NFS, port 9418 for `git daemon`) plus firewall
  rules and an exposure model the user has to reason about. The tar
  approach uses the existing vsock RPC with zero new ports, falls back
  cleanly when the VM isn't ready, and excludes the dominant on-disk
  cost (build artifacts in `.build`, `target`, `node_modules`) via
  `git ls-files --cached --others --exclude-standard` on the push side
  and a hard-coded prune list on the pull side. Worktrees under
  ~80 MiB sync end-to-end in well under a second.

## How agent phases reach the guest

Every phase Compass runs against a repo under the `.sharedVM` route
operates inside the same persistent guest workspace
(`/Users/compass/Compass/Repos/<UUID>/worktree`). The host never feeds
the agent its own filesystem paths.

Per-session flow:

1. **First reference** to a repo's guest workspace:
   `SharedCompassVMRepoWorkspaceSync.ensurePopulated` streams the host
   repo (gitignore-aware tar) into the guest path. Subsequent sessions
   skip this step — the guest workspace from the prior session is
   already there.
2. **Plan, Reflect, Develop** all run their agent loops in the guest.
   Every `AgentBashTool` / `read_file` / `write_file` / `edit_file` /
   `ls` / `glob` / `grep` call goes through vsock RPC against the
   persistent guest workspace.
3. **Verify** (when the iteration's `verify` command is set) runs
   inside the guest too, via the same vsock bash RPC. No host-side
   build toolchain is needed.
4. **On Verify success**, the host pulls the guest worktree tar
   directly onto the main host repo and commits there
   (`git add -A` + `git commit -m "<agent summary>"`). The agent does
   not commit — the guest has no `.git`.
5. **On Verify failure**, nothing pulls. Agent state stays in the
   guest workspace; the next attempt (within or across sessions) picks
   it up and continues.
