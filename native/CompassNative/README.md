# CompassNative

CompassNative is a macOS-native prototype of Compass. It keeps the same per-repo
`.compass/` workspace shape as the TypeScript implementation, but it is
Codex-only and shells out to `codex exec` instead of embedding the Claude Agent
SDK or the Codex SDK.

The native prototype requires macOS 15 or newer because its Cinematic tab uses
RealityKit's SwiftUI `RealityView` renderer.

Run it from this package:

```bash
cd native/CompassNative
swift run CompassNative
```

After the build line, the process stays running and the CompassNative window
should come to the foreground. Close the window to stop the app. The Codex
binary field defaults to `COMPASS_CODEX_BIN` when set, then common macOS
locations including `/Applications/Codex.app/Contents/Resources/codex`.

The app remembers known projects in macOS Application Support and starts with
the most recently opened repository selected. Add Git repositories from the
sidebar project list; each project keeps its own `.compass/` data, Live log,
and active Codex process, so multiple projects can run in parallel. The main
content header contains the per-project play, pause, and stop controls. Play is
auto-play: it keeps running Plan -> Develop iterations until paused, stopped, or
Plan reports no immediate work.

## Prototype Boundaries

- Plan runs `codex exec` in read-only sandbox mode and asks Codex for a
  structured `PlanState`. The app backs up `.compass/state.json` first, then
  writes the decoded state after the run.
- Reflect runs on the same default cadence as the TypeScript loop
  (`COMPASS_REFLECT_EVERY`, default `5`) and can return either no state change
  or a full updated `PlanState`.
- The Codex binary and model can be overridden with the sidebar fields. If the
  model field is empty, the phase-specific TypeScript env vars are honored:
  `COMPASS_CODEX_PLAN_MODEL`, `COMPASS_CODEX_DEV_MODEL`, and
  `COMPASS_CODEX_REFLECT_MODEL`.
- Develop runs `codex exec` in `danger-full-access` sandbox mode so Codex can
  edit, verify, and commit. When the repo has a HEAD, Develop runs in a
  disposable Git worktree and temporary branch; the app promotes it with a
  fast-forward merge only after post-checks pass.
- Develop post-checks mirror the TypeScript runner's core gates: repeat the
  verify command, require `git status --porcelain` to be clean, and retry failed
  post-checks up to three attempts with failure context.
- History metadata is written to `.compass/sessions.json` using the same broad
  schema as the TypeScript app.
- The prototype intentionally omits Claude runtime selection, Codex SDK usage,
  MCP tools, Codex sidecar review, cache warming for disposable worktrees, and
  the browser server.
