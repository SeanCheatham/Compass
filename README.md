# Compass

Compass is a macOS-native app for running recursive Codex project iterations.
It keeps per-repository state in `.compass/`, shells out to `codex exec` for
Plan, Reflect, and Develop passes, and lets multiple projects run side by side
from one desktop workspace.

Compass requires macOS 26 or newer on Apple Silicon. The Cinematic tab uses
RealityKit's SwiftUI `RealityView` renderer, and the optional Shared VM
sandbox is built directly on Apple's `Virtualization.framework`.

## Run

The Shared VM sandbox requires the `com.apple.security.virtualization`
entitlement, which only the signed Xcode-built app bundle has. For Shared VM
work, create a local signing override first:

```bash
cp App/LocalSigning.example.xcconfig App/LocalSigning.xcconfig
# Edit COMPASS_DEVELOPMENT_TEAM to your Apple development team id.
```

Debug builds copy to `/Applications/CompassLocal.app` by default. The shared
Xcode scheme waits for that app to be launched by Finder/launchd so
Virtualization.framework's install helper sees a signed app outside DerivedData
without overwriting a real `/Applications/Compass.app` install:

```bash
open Compass.xcodeproj
# Press Cmd-R, then launch /Applications/CompassLocal.app from Finder/Spotlight.
```

The equivalent command-line flow is:

```bash
xcodebuild -project Compass.xcodeproj -scheme Compass -configuration Debug \
  COMPASS_DEVELOPMENT_TEAM=ABCDE12345 \
  build
open "/Applications/CompassLocal.app"
```

The SwiftPM executable still builds (`swift run Compass`) and is fine for
non-VM work, but `VZVirtualMachine` APIs will fail without the entitlement,
so the Shared VM sandbox is disabled in that mode.

The Codex binary field defaults to `COMPASS_CODEX_BIN` when set, then common
macOS locations including `/Applications/Codex.app/Contents/Resources/codex`.

## Workflow

Add Git repositories from the sidebar project list. Each project keeps its own
`.compass/` data, Live log, and active Codex process, so multiple projects can
run in parallel. The main content header contains per-project play, pause, and
stop controls. Play is auto-play: it keeps running Plan -> Develop iterations
until paused, stopped, or Plan reports no immediate work.

- Plan runs `codex exec` in read-only sandbox mode and asks Codex for a
  structured state result plus optional `lessonEdits`. The app backs up
  `.compass/state.json` first, applies lesson edits with exact find/replace
  mechanics, then writes the decoded state after the run.
- Reflect runs on the default cadence (`COMPASS_REFLECT_EVERY`, default `5`)
  and can return either no state change or a full updated `PlanState`.
- The Codex binary and model can be overridden with the sidebar fields. If the
  model field is empty, the phase-specific env vars are honored:
  `COMPASS_CODEX_PLAN_MODEL`, `COMPASS_CODEX_DEV_MODEL`, and
  `COMPASS_CODEX_REFLECT_MODEL`.
- Develop runs `codex exec` in `danger-full-access` sandbox mode so Codex can
  edit, verify, and commit. When the repo has a HEAD, Develop runs in a
  disposable Git worktree and temporary branch; the app promotes it with a
  fast-forward merge only after post-checks pass. Develop must return
  `lessonEdits` instead of editing `.compass/lessons.md` directly, so durable
  lessons land in the main Compass workspace rather than the disposable
  worktree.
- Develop post-checks repeat the verify command, require
  `git status --porcelain` to be clean, and retry failed post-checks up to three
  attempts with failure context.
- History metadata is written to `.compass/sessions.json`.

## Compass Workspace

Everything lives in `.compass/` inside each selected repository:

```text
{repo}/.compass/
├── state.json        # Plan/Reflect own.
├── state.json.bak    # Best-effort backup before each iteration.
├── drafts.md         # User-owned draft queue.
├── lessons.md        # Durable guidance shared across iterations.
├── sessions.json     # Per-iteration session index and latest feedback.
├── sessions/         # Activity/session artifacts.
└── COMPASS.md        # User-owned project vision.
```

## Development

Two build flows coexist:

- `swift build` / `swift test` — fast, headless, no signing, no entitlements.
  Best for unit tests, type-checking, and CI.
- `xcodebuild -project Compass.xcodeproj -scheme Compass` — produces the
  signed `Compass.app` with the virtualization entitlement. Required for
  any Shared VM work.

Both reference the same sources under `Sources/Compass/`. New `.swift` files
dropped there are picked up automatically — Package.swift uses an executable
target, and the Xcode project uses synchronized folder groups (Xcode 15.3+),
so no manual project-file edits are needed for routine source additions.

App-bundle metadata lives under `App/`:

- `App/Info.plist` — bundle id, version, category, min macOS.
- `App/Compass.entitlements` — currently just `com.apple.security.virtualization`.
  Add more entitlements here if Compass ever needs sandboxed network, hardware
  access, etc. App Sandbox is intentionally **off** — Compass is distributed
  outside the App Store (via `.dmg`), so the sandbox's file-access restrictions
  and security-scoped-bookmark dance are not needed.

Codesigning uses `App/Signing.xcconfig` plus the git-ignored
`App/LocalSigning.xcconfig` for personal team ids. For `.dmg` distribution,
swap to a Developer ID Application cert via Xcode -> Signing & Capabilities,
then notarize the resulting `.app` before packaging.

## Sandbox: Shared macOS VM (optional)

Each project can opt its Develop iterations into a shared macOS guest VM via
the per-project **Develop sandbox** picker in the Runtime section of the
sidebar. With `.host` selected (default), Develop runs natively against a
disposable Git worktree under `~/Library/Caches/Compass/Worktrees/`. With
`.sharedVM` selected, Develop instead runs inside a Compass-managed macOS VM
via SSH, with the same worktree exposed to the guest over VirtioFS.

The VM is built from scratch on the user's machine using
`VZMacOSRestoreImage.fetchLatestSupported` (Apple CDN, ~14 GB IPSW, no auth)
and installed via `VZMacOSInstaller`. After install, the first boot lands at
Setup Assistant — the embedded VM view in the top-level **Sandbox** section
of the main window guides the user through a one-time ~2 minute click-through
(decline Apple ID, create `compass` user, enable Remote Login). Subsequent
iterations reuse the same persistent guest.

Requirements:

- Apple Silicon Mac, macOS 26 or newer.
- ~30 GB free disk under `~/Library/Application Support/Compass/SharedVM/`
  (sparse image — may drift larger over time).
- First-time setup takes ~30–50 minutes (IPSW download + install + CLT
  install + one-time Setup Assistant click-through).
- Apple's Virtualization.framework caps the host at 2 concurrent macOS
  guests. Conflicts with other VZ-based products (Parallels' VZ backend,
  Tart, etc.) surface as `Shared VM unavailable: 2-guest cap reached` and
  Develop transparently falls back to the host route.

When using Compass to develop Compass itself, treat the currently running
Compass process as infrastructure, not as the test subject. If a launch smoke
test is needed, start `swift run Compass` as a child process, record that exact
PID, and terminate only that PID after the check. Avoid broad process-killing
commands such as `pkill -f Compass`, `killall swift`, `killall codex`, or
port-wide kill commands that could stop the live Compass session running the
iteration. The Shared VM sandbox makes this safer by default — runaway
`pkill` inside the guest cannot reach the host orchestrator.
