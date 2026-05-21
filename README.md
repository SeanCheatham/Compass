# Compass

Compass is a macOS-native app for running recursive Plan / Develop / Reflect
loops over a Git repository. It talks to any OpenAI-compatible chat
completions endpoint (default: MiniMax), drives the loop with its own tool
dispatcher, and keeps per-repository state in `.compass/` so multiple
projects can run side by side from one desktop workspace.

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

Debug builds copy to `/Applications/CompassLocal.app` by default and use the
`com.seancheatham.CompassLocal` bundle identifier/display name. The shared Xcode
scheme waits for that app to be launched by Finder/launchd so
Virtualization.framework's install helper sees a signed app outside DerivedData
without overwriting or confusing a real `/Applications/Compass.app` install:

```bash
open Compass.xcodeproj
# Press Cmd-R; Xcode builds/copies and waits.
# Then launch /Applications/CompassLocal.app from Finder/Spotlight.
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

## Configure the agent endpoint

Compass talks to an OpenAI-compatible chat completions endpoint using
[MacPaw/OpenAI](https://github.com/MacPaw/OpenAI). The base URL, API key,
default model, and per-phase model overrides are configured in **Compass →
Settings…** (⌘,). The API key is stored in the macOS Keychain; the rest
lives in UserDefaults under the app's bundle id and persists across
launches.

Environment variables seed empty fields on first launch — useful for
scripted setup / CI:

| Variable                       | Default                          |
| ------------------------------ | -------------------------------- |
| `COMPASS_AGENT_BASE_URL`       | `https://api.minimax.io/v1`      |
| `COMPASS_AGENT_API_KEY`        | _(no default, required)_         |
| `COMPASS_AGENT_MODEL`          | `MiniMax-M2.7`                   |
| `COMPASS_AGENT_MODEL_PLAN`     | _(falls back to default model)_  |
| `COMPASS_AGENT_MODEL_DEV`      | _(falls back to default model)_  |
| `COMPASS_AGENT_MODEL_REFLECT`  | _(falls back to default model)_  |

Any endpoint that implements OpenAI-style streaming chat completions with
`tools` / `tool_choice` / multi-turn `tool_calls` works. MiniMax-M2.7 is
the default because it is what this branch was developed against;
swapping to a different provider is a Settings-only change.

## Workflow

Add Git repositories from the sidebar project list. Each project keeps its
own `.compass/` data, Live log, and active agent run, so multiple projects
can run in parallel. The main content header contains per-project play,
pause, and stop controls. Play is auto-play: it keeps running Plan →
Develop iterations until paused, stopped, or Plan reports no immediate
work.

Each phase is driven by Compass's own agent loop: the model is given a
fixed tool set, streams reasoning + tool calls back, and ends the turn by
calling the special `submit_result` tool with a JSON payload that matches
the phase contract.

- Plan runs with a **read-only** tool set (`read_file`, `ls`, `grep`,
  `glob`) and asks the model for a structured state result plus optional
  `lessonEdits`. The app backs up `.compass/state.json` first, applies
  lesson edits with exact find/replace mechanics, then writes the decoded
  state after the run.
- Reflect runs on the default cadence (`COMPASS_REFLECT_EVERY`, default
  `5`) with the same read-only tool set and can return either no state
  change or a full updated `PlanState`.
- Develop runs with the **full** tool set (`read_file`, `ls`, `grep`,
  `glob`, `write_file`, `edit_file`, `bash`) so the model can edit,
  verify, and commit. When the repo has a HEAD, Develop runs in a
  disposable Git worktree and temporary branch; the app promotes it with
  a fast-forward merge only after post-checks pass. Develop must return
  `lessonEdits` instead of editing `.compass/lessons.md` directly, so
  durable lessons land in the main Compass workspace rather than the
  disposable worktree.
- Develop post-checks repeat the verify command, require
  `git status --porcelain` to be clean, and retry failed post-checks up
  to three attempts with failure context.
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
`.sharedVM` selected, file-level tools still operate directly on the host
worktree (it is VirtioFS-mounted into the guest), but the agent's `bash`
tool routes through SSH and runs `/bin/zsh -lc` inside the guest — so
builds, tests, and any side effects of `bash` calls happen in the VM, not
on the host.

The VM is built from scratch on the user's machine using
`VZMacOSRestoreImage.fetchLatestSupported` (Apple CDN, ~14 GB IPSW, no auth)
and installed via `VZMacOSInstaller`. After install, a one-shot
LaunchDaemon planted by Compass finishes first-boot headlessly — it
creates the `compass` user, authorises Compass's SSH key, and enables
Remote Login without any user interaction. Subsequent iterations reuse
the same persistent guest.

Requirements:

- Apple Silicon Mac, macOS 26 or newer.
- ~30 GB free disk under `~/Library/Application Support/Compass/SharedVM/`
  (sparse image — may drift larger over time).
- First-time setup takes ~25–45 minutes (IPSW download + install +
  headless first-boot). One macOS admin authentication prompt fires
  during provisioning so Compass can plant the LaunchDaemon onto the
  freshly-installed Data volume.
- Apple's Virtualization.framework caps the host at 2 concurrent macOS
  guests. Conflicts with other VZ-based products (Parallels' VZ backend,
  Tart, etc.) surface as `Shared VM unavailable: 2-guest cap reached` and
  Develop transparently falls back to the host route.

When using Compass to develop Compass itself, treat the currently running
Compass process as infrastructure, not as the test subject. If a launch smoke
test is needed, start `swift run Compass` as a child process, record that exact
PID, and terminate only that PID after the check. Avoid broad process-killing
commands such as `pkill -f Compass` or `killall swift` that could stop the
live Compass session running the iteration. The Shared VM sandbox makes
this safer by default — runaway `pkill` inside the guest cannot reach the
host orchestrator.
