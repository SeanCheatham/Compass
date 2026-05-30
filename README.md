# Compass

Compass is a macOS-native app for running recursive Plan / Develop / Reflect
loops over a Git repository. It talks to any OpenAI-compatible chat
completions endpoint (default: MiniMax), drives the loop with its own tool
dispatcher, and keeps per-repository state in `.compass/` so multiple
projects can run side by side from one desktop workspace.

Compass requires macOS 26 or newer on Apple Silicon. The Shared VM sandbox
is built directly on Apple's `Virtualization.framework`.

## Run

The Shared VM sandbox requires the `com.apple.security.virtualization`
entitlement, which only the signed Xcode-built app bundle has. For Shared VM
work, create a local signing override first:

```bash
cp App/LocalSigning.example.xcconfig App/LocalSigning.xcconfig
# Edit COMPASS_DEVELOPMENT_TEAM to your Apple development team id.
```

Debug builds copy to `/Applications/CompassLocal.app` by default and use the
`com.seancheatham.CompassLocal` bundle identifier/display name. Launch that app
via Finder/Spotlight (not from Xcode's debugger) so Virtualization.framework's
install helper sees a signed app outside DerivedData without overwriting a real
`/Applications/Compass.app` install.

**Recommended — command line:**

```bash
./scripts/run-local.sh              # build, copy, and open CompassLocal
./scripts/run-local.sh --clean      # wipe DerivedData/ then build + open
./scripts/run-local.sh --no-build   # open the existing install only
./scripts/test-local.sh             # swift test (no app bundle needed)
```

`build-local.sh` runs `xcodebuild` with a repo-local `DerivedData/` folder and
copies the Debug app to `/Applications/CompassLocal.app`. Team id comes from
`App/LocalSigning.xcconfig` or `COMPASS_DEVELOPMENT_TEAM`.

**Optional — Xcode:**

```bash
open Compass.xcodeproj
# Press Cmd-B to build (check the log for "Copied Compass.app").
# Then launch /Applications/CompassLocal.app from Finder/Spotlight.
```

Raw `xcodebuild` equivalent:

```bash
./scripts/build-local.sh
open "/Applications/CompassLocal.app"
```

The SwiftPM executable still builds (`swift run Compass`) and is fine for
non-VM work, but `VZVirtualMachine` APIs will fail without the entitlement,
so the Shared VM sandbox is disabled in that mode.

## Configure the agent endpoint

Compass talks to an OpenAI-compatible chat completions endpoint using
[MacPaw/OpenAI](https://github.com/MacPaw/OpenAI). The base URL, API key,
default model, and per-phase model overrides are configured in **Compass →
Settings…** (⌘,). The API key is stored in a `0600` file under
`~/Library/Application Support/Compass/secrets/`; the rest lives in
UserDefaults under the app's bundle id and persists across launches.

Environment variables seed empty fields on first launch — useful for
scripted setup / CI:

| Variable                              | Default                          |
| ------------------------------------- | -------------------------------- |
| `COMPASS_AGENT_BASE_URL`              | `https://api.minimax.io/v1`      |
| `COMPASS_AGENT_API_KEY`               | _(no default, required)_         |
| `COMPASS_AGENT_MODEL`                 | `MiniMax-M2.7`                   |
| `COMPASS_AGENT_MODEL_PLAN`            | _(falls back to default model)_  |
| `COMPASS_AGENT_MODEL_DEV`             | _(falls back to default model)_  |
| `COMPASS_AGENT_MODEL_REFLECT`         | _(falls back to default model)_  |
| `COMPASS_AGENT_MODEL_CRITIC`          | _(falls back to default model; point at a different / stronger model than Develop for independent adversarial review)_ |
| `COMPASS_AGENT_MODEL_CODEMAP`         | _(falls back to default model; use a cheap small model for the per-file summary fan-out)_ |
| `COMPASS_AGENT_CONTEXT_WINDOW_TOKENS` | `200000` (`0` disables compaction) |
| `COMPASS_REFLECT_EVERY`               | `5` (Reflect cadence in iterations) |

Each Plan / Develop / Reflect iteration reports its token usage back to
Compass via `stream_options.include_usage`. When usage crosses 75% of
`COMPASS_AGENT_CONTEXT_WINDOW_TOKENS`, the executor runs a tool-free
summary call and rebuilds the message history as `[system prompt,
original task prompt, compacted summary]` so the next turn fits with
fresh headroom. Set the variable to `0` to disable auto-compaction (e.g.
for a model that returns clear 400s on overflow and you want them to
bubble up).

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

- Plan runs with inspection tools (`read_file`, `ls`, `grep`, `glob`,
  `bash`, plus the codemap tools `outline`, `find_symbol`, `summary`,
  `importers_of`, `list_files`, and `delegate`). The system prompt — not
  the presence of `bash` — enforces the no-mutation contract. `bash` is
  included so the agent can probe the project (build, test, lint, git)
  when deciding what to plan. The app backs up `.compass/state.json` first,
  applies lesson edits with exact find/replace mechanics, then writes the
  decoded state after the run.
- Reflect runs on the default cadence (`COMPASS_REFLECT_EVERY`, default
  `5`) with the same read-only tool set and can return either no state
  change or a full updated `PlanState`.
- Develop runs with the full tool set (inspection tools plus
  `write_file`, `edit_file`, `bash`) inside the Shared VM's persistent
  per-repo guest workspace. Plan and Reflect also run inside the same
  guest when the VM is ready; if the VM is unavailable they fall back
  to a direct host invocation. Develop must return `lessonEdits`
  instead of editing `.compass/lessons.md` directly, so durable lessons
  land in the main Compass workspace rather than only inside the guest.
- Develop post-checks repeat the verify command, require
  `git status --porcelain` to be clean, and retry failed post-checks up
  to three attempts with failure context. If post-checks still fail,
  Compass hands the failure output to Plan as feedback and continues the
  loop instead of stopping auto-play.
- Critic runs after Develop's post-checks pass and acts as an
  adversarial review gate. It sees the Develop summary, the Verify
  output, and the working-tree diff, and finishes by calling
  `submit_result` with `verdict: "approve" | "request_changes"`. On
  `request_changes` Compass re-runs Develop with the critic's feedback
  appended; the loop is capped at three critic reviews per iteration,
  after which Compass accepts and proceeds regardless so the loop
  always terminates. Critic has the read-only tool set plus `bash` so
  it can run extra linters / individual tests, but it cannot edit,
  write, or commit — the prompt enforces that intent. Configure a
  dedicated model via `COMPASS_AGENT_MODEL_CRITIC` or the Settings UI;
  pointing it at a different / stronger model than Develop produces
  more independent critique.
- Every phase exposes a `delegate(task, tools?, model?)` tool that
  spawns a focused sub-agent in the same working directory and returns
  a single `findings` string. Use it for self-contained investigations
  ("find every callsite of X and report how they handle Y") so the
  parent's context stays focused. The sub-agent inherits the parent's
  tools minus `delegate` itself — sub-agents cannot nest, so the loop
  depth is capped at 1.
- Every phase can call `record_assumption` when it relies on a
  consequential guess about user intent, environment, constraints, or
  acceptance criteria. Compass stores these in an assumptions ledger and
  shows them to the user for explicit affirmation or denial. Affirmed
  assumptions are injected as strong guidance, denied assumptions as
  corrections, and unreviewed assumptions as true but lower-confidence
  context.
- History metadata is written to `.compass/sessions.json`.

## Compass Workspace

Everything lives in `.compass/` inside each selected repository:

```text
{repo}/.compass/
├── state.json        # Plan/Reflect own.
├── state.json.bak    # Best-effort backup before each iteration.
├── drafts.md         # User-owned draft queue.
├── lessons.md        # Durable guidance shared across iterations.
├── assumptions.json  # Agent-recorded assumptions and user reviews.
├── sessions.json     # Per-iteration session index and latest feedback.
├── sessions/         # Activity/session artifacts.
└── COMPASS.md        # User-owned project vision.
```

## Explore

Explore is an AI-powered layer that helps users understand software produced
by Compass. Rather than leaving generated code opaque, it surfaces meaning —
what changed, why, and how the pieces fit together — using Apple's on-device
Foundation Models so explanations stay local and fast.

Explore has seven main components:

- **`CodemapFileSystem`** (`Sources/Compass/Explore/CodemapFileSystem.swift`) —
  File-system scanner that walks the repository tree and produces a
  ``FileTreeNode`` hierarchy mirroring the source directory layout.
  Used by ``ExploreTreeBuilder`` when ``GitSourcePaths`` cannot enumerate
  files via `git ls-files` (e.g. in a fresh or sparse checkout).
  Available on all macOS versions. Entry point: ``CodemapFileSystem(rootURL:).buildTree()``.

- **`CommitExplainer`** (`Sources/Compass/Explore/CommitExplainer.swift`) —
  Takes a git diff and produces a plain-English summary in roughly three
  sentences. Uses `FoundationModelsAvailability.isAvailable` from the on-device Foundation
  Models framework. Requires **macOS 26** and is gated behind `@available(macOS 26.0, *)`.
  Returns `nil` gracefully when Foundation Models is unavailable.  Supports
  two prompt modes: ``summarize(diff:)`` answers "what changed?"; ``summarizeWhyGenerated(diff:)``
  answers "why does this file exist?" using a distinct prompt template focused on
  purpose and architectural role.

- **`CommitTourGenerator`** (`Sources/Compass/Explore/CommitTourGenerator.swift`) —
  Synthesizes a multi-commit diff into a 3–5 sentence architectural guided-tour
  narrative explaining what was built, why, and how the pieces fit together.
  Uses `FoundationModelsAvailability.isAvailable` from the on-device Foundation Models
  framework. Requires **macOS 26** and is gated behind `@available(macOS 26.0, *)`.
  Returns `nil` gracefully when Foundation Models is unavailable.

- **`ExploreRepositorySnapshot`** (`Sources/Compass/Explore/ExploreRepositorySnapshot.swift`) —
  Immutable snapshot combining the repository file tree with indexed
  codemap entries. ``ExploreRepositorySnapshotCache`` provides thread-safe
  in-memory caching; ``ExploreRepositorySnapshotLoader`` assembles the snapshot
  by delegating to ``ExploreTreeBuilder`` and ``CodemapStore``. Available on all
  macOS versions. Entry point: ``ExploreRepositorySnapshotLoader.load(repoURL:codemapDirectory:)``.

- **`FileExplainer`** (`Sources/Compass/Explore/FileExplainer.swift`) —
  Parses `git diff --stat` output and enriches each changed file with
  codemap-based categorization (`Source`, `Tests`, `Config`, `Other`).
  Provides `FileChange` objects with language, line-count labels, and
  category for consistent presentation in the UI. Available on all macOS
  versions. Two explanation modes are exposed: ``explain(file:repoURL:commits:)``
  describes *what changed* via the diff; ``whyGenerated(file:repoURL:commits:)``
  explains *why the file exists* — its purpose and architectural role.

- **`RepoQnA`** (`Sources/Compass/Explore/RepoQnA.swift`) —
  Answers free-text questions about repository changes using on-device
  Foundation Models. Uses `FoundationModelsAvailability.isAvailable` from the Foundation
  Models framework. Requires **macOS 26** and is gated behind `@available(macOS 26.0, *)`.
  Returns `nil` gracefully when Foundation Models is unavailable. See the
  Vision document for the full feature description. Entry point: ``answer(question:repoURL:)``.

- **`ArchitectureGraph`** (`Sources/Compass/Explore/ArchitectureGraph.swift`) —
  Produces a plain-English architectural description of a codebase's import graph.
  Covers top-level modules, key cross-module dependencies, and architecturally
  significant files (central infrastructure, likely entry points, unusual patterns).
  Uses `FoundationModelsAvailability.isAvailable` from the on-device Foundation Models
  framework. Requires **macOS 26** and is gated behind `@available(macOS 26.0, *)`.
  Returns `nil` gracefully when Foundation Models is unavailable. Entry point: ``explain(graph:repoURL:)``.

Explore is documented in the Vision under the "Explore layer" section.

### Why Was This File Generated?

The "why generated" explainer answers a distinct question from per-file diff summarization: instead of describing *what changed* in a diff, it explains *why the file was created and what role it plays* in the codebase. This capability is surfaced via ``FileExplainer.whyGenerated(file:repoURL:commits:)``, which routes the same git diff through a purpose-focused prompt chain in ``CommitExplainer/summarizeWhyGenerated(diff:)``.

The two prompt modes share the same diff input but answer different questions:

| Mode | Method | Prompt focus |
| --- | --- | --- |
| What changed | ``CommitExplainer.summarize(diff:)`` | Intent and effect of the diff |
| Why it exists | ``CommitExplainer.summarizeWhyGenerated(diff:)`` | Purpose and architectural role of the file |

The "why generated" view is useful when exploring new or unfamiliar files — it answers "why does this file exist at all?" rather than "what happened to this file in this commit range?".

## Development

Two build flows coexist:

- `swift build` / `swift test` — fast, headless, no signing, no entitlements.
  Best for unit tests, type-checking, and CI.
- `xcodebuild -project Compass.xcodeproj -scheme Compass` — produces the
  signed `Compass.app` with the virtualization entitlement. Required for
  any Shared VM work.

Formatting is enforced by [swift-format](https://github.com/swiftlang/swift-format),
which ships with the Swift 6 toolchain. The config lives at `.swift-format`
(swift-format's official defaults: 2-space indent, 100-char lines, all
default rules). Two helpers wrap the common invocations:

```bash
./scripts/format.sh          # rewrite Sources/, Tests/, Package.swift in place
./scripts/format.sh --lint   # report violations only; exits non-zero if any
```

The lint pass must be clean (`exit 0`) and `swift test` must be green
before pushing. A handful of C-ABI mirrors and `XCTAssert`-style helpers
opt out of `AlwaysUseLowerCamelCase` / `TypeNamesShouldBeCapitalized` via
inline `// swift-format-ignore` annotations.

Both reference the same sources under `Sources/Compass/`. New `.swift` files
dropped there are picked up automatically — Package.swift uses an executable
target, and the Xcode project uses synchronized folder groups (Xcode 15.3+),
so no manual project-file edits are needed for routine source additions.

App-bundle metadata lives under `App/`:

- `App/Info.plist` — bundle id, version, category, min macOS.
- `App/Compass.entitlements` — `com.apple.security.virtualization` (for the
  Shared VM) and `keychain-access-groups` (for the Shared VM's SSH guest
  credential, the only secret Compass still stores in the macOS Keychain).
  Add more entitlements here if Compass ever needs sandboxed network, hardware
  access, etc. App Sandbox is intentionally **off** — Compass is distributed
  outside the App Store (via `.dmg`), so the sandbox's file-access restrictions
  and security-scoped-bookmark dance are not needed.

Codesigning uses `App/Signing.xcconfig` plus the git-ignored
`App/LocalSigning.xcconfig` for personal team ids. For `.dmg` distribution,
swap to a Developer ID Application cert via Xcode -> Signing & Capabilities,
then notarize the resulting `.app` before packaging.

## Sandbox: Shared macOS VM

Compass runs every Develop iteration inside a shared macOS guest VM —
the user no longer chooses between routes. Each project gets a
persistent per-repo workspace inside the guest, and the agent talks to
its tools (`read_file`, `write_file`, `edit_file`, `bash`, etc.) over
vsock. Once Verify passes, Compass pulls the guest workspace back into
the host repo so the iteration's commits land in the main checkout.

Plan and Reflect use the same guest workspace and vsock tool path when
the VM is ready. If the guest workspace catalog cannot map the repo or
the VM is unavailable, Compass falls back to a direct host invocation
internally. Only Develop iterations and their post-Verify file sync
require the guest to be ready.

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
  Tart, etc.) surface as `Shared VM unavailable: 2-guest cap reached`,
  which blocks Develop until the other guest exits.

When using Compass to develop Compass itself, treat the currently running
Compass process as infrastructure, not as the test subject. If a launch smoke
test is needed, start `swift run Compass` as a child process, record that exact
PID, and terminate only that PID after the check. Avoid broad process-killing
commands such as `pkill -f Compass` or `killall swift` that could stop the
live Compass session running the iteration. The Shared VM sandbox makes
this safer by default — runaway `pkill` inside the guest cannot reach the
host orchestrator.
