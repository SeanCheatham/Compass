# CompassNative

CompassNative is a macOS-native prototype of Compass. It keeps the same per-repo
`.compass/` workspace shape as the TypeScript implementation, but it is
Codex-only and shells out to `codex exec` instead of embedding the Claude Agent
SDK or the Codex SDK.

Run it from this package:

```bash
cd native/CompassNative
swift run CompassNative
```

The app starts without an active project. Choose a Git repository from the
sidebar, initialize the `.compass` workspace, then add a draft and run a
planning pass or a full Plan -> Develop iteration.

## Prototype Boundaries

- Plan runs `codex exec` in read-only sandbox mode and asks Codex for a
  structured `PlanState`. The app writes `.compass/state.json` after decoding
  that response.
- Develop runs `codex exec` in `danger-full-access` sandbox mode so Codex can
  edit, verify, and commit. The app then repeats the verify command and checks
  `git status --porcelain`.
- Session metadata is written to `.compass/sessions.json` using the same broad
  schema as the TypeScript app.
- The prototype intentionally omits Claude runtime selection, Codex SDK usage,
  MCP tools, disposable worktree promotion, and the browser server.
