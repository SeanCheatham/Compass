# Compass

Compass is a macOS-native app for running recursive Plan / Develop / Reflect
loops over a Git repository. It talks to any OpenAI-compatible chat
completions endpoint (default: MiniMax), drives the loop with its own tool
dispatcher, and keeps per-repository state in `.compass/` so multiple
projects can run side by side from one desktop workspace.

Compass requires macOS 26 or newer on Apple Silicon. Its private workspace
is built directly on Apple's `Virtualization.framework`.

## Generated Projects Are Rust

Compass itself remains a native Swift/macOS app. The Rust pivot applies to
projects Compass creates, verifies, repairs, and evolves as generated output.
New generated projects are Rust-only across backend/core logic, CLI, desktop UI,
tests, schemas, and automation wherever practical.

The blessed generated-project shape is a Cargo workspace:

- `crates/app-core` for deterministic domain state and schema-backed contracts.
- `crates/app-cli` for command-line inspection and automation entry points.
- `crates/app-desktop` for the Rust desktop/frontend UI, using `eframe`/`egui`.
- `xtask` for Rust-owned automation.
- `schemas/` and `rust-toolchain.toml` for checked-in contracts and toolchain
  expectations.
- Compass's own `crates/compass-engine` is the guest-installed sidecar that
  provides structured Cargo diagnostics, workspace outlines, Rust indexes,
  schema contracts, coverage gaps, and visual verification results.

Generated apps should also be friendly to testing:
load-bearing behavior belongs in pure `app-core` transitions with explicit
serializable inputs and stable snapshot/event-log outputs exposed through
`app-cli`. That gives agents a safe, sandboxed, replayable way to "use" the app
before reaching for desktop automation; visual verification remains proof that
the Rust UI renders the same deterministic state.
Generated GUIs should expose semantic replay traces and snapshots as their
deterministic assertion surface, with screenshots reserved for rendering proof.

Standard generated-project checks are:

```bash
cargo run -p xtask -- verify
cargo run -p xtask -- visual-verify
cargo run -p xtask -- visual-verify --emit-base64
cargo run -p xtask -- product-tournament-trace-check
cargo run -p xtask -- product-tournament-smoke
cargo run -p xtask -- product-tournament-smoke --emit-base64
```

`xtask verify` is the normal fast path: format, lint, test, coverage, and
build without launching the desktop app. `product-tournament-trace-check` proves
the deterministic semantic product-pressure replay. `product-tournament-smoke`
adds coverage and desktop visual verification.

Swift, TypeScript, and JavaScript are retained as legacy imported-repository
inspection/evolution paths only. Host Xcode exists for those legacy Apple
repositories and for Compass's own Swift code; it is not a generated-output
dependency. The Compass host app remains Swift/macOS; the Rust engine is a
Product Tournament verification sidecar and is not used for the host UI or VM lifecycle.

## Product Tournaments

Compass frames product discovery as a tournament. A tournament starts from a
durable user pain, creates several competing product contenders for that pain,
and advances them through rounds:

- **Round 1: product plans.** No product exists yet. Model-free and optional
  Foundation Models persona simulated users inspect the plans, compare them with
  the current alternative, and judge pain recognition, sponsorship, and
  willingness to pay. Accumulated plan readiness tracks plan proof debt: enough
  completed simulated-user evaluations, at least two distinct personas, a
  buyer/sponsor signal, and a viable willingness-to-pay score. Compass only
  advances a contender to Round 2 when that debt is clear;
  otherwise it gathers more plan evidence, marks a plan for revision, or
  eliminates a weak contender before implementation spend. When buyer/sponsor
  debt remains, Round 1 plan evaluation targets an economic-buyer simulated user
  for that contender, even if the plan was originally aimed at an operator. The
  Workbench and Product Tournament Context show each contender's next plan proof
  target so the next run is aimed at the missing evidence instead of merely
  reporting a generic readiness score. They also surface commercial proof so
  low willingness-to-pay evidence points to price, ROI, and sponsorship work
  instead of a vague plan revision. Plan-only scoring rewards explicit monthly
  pricing, ROI or payback claims, sponsorship language, and quantified savings,
  and buyer/sponsor personas discount generic plans that lack those commercial
  signals.
- **Round 2: core technology.** Surviving contenders get the smallest technical
  proof that demonstrates the hard part can work. After Round 1 advances a
  contender, Compass emits a Round 2 feasibility handoff that names the narrowed
  contender, implementation track, branch/worktree, plan-readiness evidence, and
  acceptance signals for the next build slice. Product Tournament Context also
  turns that handoff into a single Plan-facing implementation target, so the
  next Immediate handoff builds only the selected contender's core-technology
  proof on its experiment branch/worktree. Scenario evidence launches validate
  that target before running, blocking accidental evidence collection against
  sibling contenders once Round 2 has narrowed to one implementation track; the
  Workbench also preselects that track and visibly locks sibling scenario/cohort
  run controls, while tournament automation planning omits sibling proof
  targets and evidence steps. Plan/Reflect prompts also receive a
  `round_2_evidence_lock` line naming the paused sibling experiments so the next
  handoff stays focused on the single core-technology proof. A Round 2
  core-technology proof overview summarizes that active target's readiness,
  scoped evidence, persona breadth, experience-use proof, missing capabilities,
  and next transition recommendation in both the Workbench and Product
  Tournament Context. Scoped Round 2 scenario evidence then drives the next
  tournament transition: advance the contender to Round 3, mark the core
  technology for revision, or eliminate the contender before adding prototype
  fidelity. Advancement requires completed evidence from two personas plus two
  stored completed-use proofs derived from traces that reach the required
  product-use action sequence.
- **Round 3: prototype.** Agentic users exercise low-medium fidelity product
  versions and evaluate workflow improvement, switching readiness, continued-use
  pull, and explicit price or sponsorship intent. Scoped prototype evidence can
  select a tournament winner, force a final prototype revision, or eliminate the
  remaining contender. A Round 3 prototype proof overview keeps the active
  contender's winner-readiness, willingness-to-pay, current-alternative proof,
  prototype-use proof, persona breadth, missing capabilities, and next
  transition recommendation visible in both the Workbench and Product
  Tournament Context until the tournament winner is selected. Winner selection
  requires three completed prototype-use proofs derived from completed traces,
  along with current-alternative comparison and willingness-to-pay evidence.
  Workbench scenario-run rows and selected-run details expose whether each run
  counts as completed-use proof.

Simulation is not user research, a sales forecast, or a Verify gate. It is a
skeptical, repeatable product-pressure loop: a scenario works through the app's
semantic `ProductTournamentExperienceTrace`, records structured feedback, and gives
Plan/Reflect bounded evidence about pain recognition, workflow improvement,
objections, missing capabilities, scores, verdicts, scenario gaps, and the
decision intent being stress-tested.

Generated apps expose the contract through:

```bash
cargo run -p app-cli -- product-tournament-experience-schema
cargo run -p app-cli -- product-tournament-experience --input '{"schemaVersion":1,"pain":{"id":"pain-reporting","summary":"Weekly reporting takes too long","impact":"Managers lose visibility"},"productHypothesis":{"id":"hypothesis-compass","title":"Compass workflow helper","promise":"Turn scattered updates into a reviewed weekly report"},"experiment":{"id":"experiment-reporting","branchName":"product-tournament/reporting","successSignal":"Persona completes a report draft and sees why it beats the current workflow"},"scenario":{"seed":"demo","personaSummary":"Operations lead evaluating a workflow tool","task":"Reduce weekly reporting work"},"currentWorkflow":{"summary":"Collect updates manually, paste them into a spreadsheet, and chase missing details.","frictionPoints":["manual copy paste","late follow ups"]},"alternatives":[{"id":"spreadsheet","name":"Shared spreadsheet","description":"A manual tracker with copied status updates.","switchingObjection":"The team already knows the spreadsheet."}],"actions":[]}'
cargo run -p xtask -- product-tournament-trace-check
cargo run -p xtask -- product-tournament-smoke
```

The generated experience input carries the tested `productHypothesis`, and the
semantic trace stamps it as `productHypothesisID`.
`product-tournament-trace-check` is the model-free generated-project semantic
check. It proves the app owns a stable experience contract, replays the expected
product-hypothesis action sequence, completes the contender workflow, and earns
strong willingness-to-pay only after that completed-use proof.
`product-tournament-smoke` adds coverage and desktop visual proof. Live persona
and feedback calls are manual/interactive checks, not part of normal automated
tests.

Tournament state and evidence use the product tournament storage namespace:
`.compass/product-tournament.json` for pain hypotheses, tournaments,
contenders, rounds, product hypotheses, experiment branches, scenarios, and decisions;
`.compass/product-tournament/` for `evidence-index.json` and separate run artifacts
for traces, feedback, transcripts, plan evaluations, and Markdown summaries. The
state schema stores product hypotheses under `productHypotheses`, and Discover
candidate experiments reference them with `productHypothesisID`. The Tournament
workbench lists pain hypotheses, contenders, rounds, implementation
tracks, selectable Round 1 plan evaluations with buyer objections and
willingness-to-pay rationale, per-plan commercial proof, evaluation mode/model
and prompt-version provenance, scenario runs, feedback scores, objections,
missing capabilities, failure kinds, decision history, and copyable Markdown
summaries. Contender rows in the active plan-only round label
the exact focused proof action, such as buyer, price/ROI, persona, or plan proof,
and disable it once the contender is ready for the Round 2 feasibility transition.
Tournament automation proof targets also surface those focused Round 1 actions
with contender and round IDs, so Plan/Reflect can queue plan-only proof before a
prototype or core-technology artifact exists. While the active tournament has no
tournament experience evidence yet, automation turns that target into a runnable
`run_plan_proof` step that executes focused model-free plan evidence first, then
prefers Foundation Models persona-model plan proof before Round 1 transition
when the contender only has deterministic plan evaluations. Both write Round 1
plan-evaluation evidence for that contender. Cycle audits report the before/after
Round 1 plan-proof debt for automation steps directly, so a focused plan run
shows whether it cleared buyer/sponsor, persona, evaluation, or
willingness-to-pay debt before any tournament experience evidence exists. Product
Tournament Context also includes recent Round 1 plan-proof automation deltas so
Plan and Reflect can see the exact debt labels that changed after automation;
matching context rows repeat the latest delta beside the plan-readiness state.
The Workbench contender rows show the same latest proof-debt delta beside the
focused proof action, with the audit and starting/ending debt labels available
from the row help. A Round 1 proof-delta overview also groups active plan-round
contenders so operators can compare cleared, unchanged, missing, or worsened
proof debt before deciding which plan to test next; that overview disappears once
the tournament advances to Round 2 while recent automation deltas remain in
context as history.
Later-round scenario evidence is stamped with tournament, round, and contender
IDs when a narrowed contender is active in Round 2 or Round 3, so agentic-user
feedback remains comparable across tournament rounds. The workbench and
Tournament Automation can apply the best actionable Round 1, Round 2, and Round 3
recommendations to stored tournament state, including selecting a winner when
prototype evidence clears the winner gate. Cycle audits record those automated
round transitions separately from tournament decision updates and evidence runs,
and Round 1 plan-proof cycles capture starting and ending
persona-model/model-free plan evidence counts.
Only the proof overview for the active tournament round is shown at a time:
Round 1 plan proof, Round 2 core-technology proof, or Round 3 prototype winner
proof.
Plan and Reflect receive only a compact advisory summary:
current tournament round, contender plans, Round 1 plan readiness and plan proof
debt, focused Round 1 proof actions, buyer/sponsor signals, willingness-to-pay
signals, persona-model/model-free plan evidence counts, Round 2 feasibility
handoffs, core-technology proof overview, experience-use proof counts, evidence
transitions, Round 3 prototype proof overview and winner recommendations, latest
evidence per active scenario, repeated objections, low-score clusters, verdict
distribution, failures, current alternative comparisons, and tournament evidence-backed
willingness to pay or sponsor.
Raw transcripts stay out of prompt context unless a human inspects them in the
app.

Interpret subjective feedback carefully. Repeated objections across personas or
tasks can justify product work; a single persona-specific complaint should be
treated as a signal to investigate. Tournament evidence can motivate the next
Plan increment, suggest better scenarios, or challenge the hypothesis, but it
never bypasses normal build/test/Verify discipline.

Tournament prompts use the same model/provider settings already configured for
the project and do not add a new network destination. Automatic persona-model
scenario execution is kept disabled unless rollout controls can bound runtime and
flake risk; Round 1 persona-model plan evaluation is available from the
Workbench when Foundation Models is present. Run the generated
`product-tournament-smoke` and inspect tournament evidence manually when
evaluating the feature.

## Developing compass-engine

The structured Rust sidecar lives at `crates/compass-engine` and is built from
the repository root:

```bash
./scripts/build-compass-engine.sh
./scripts/test-rust-engine.sh
```

## Run

The private workspace requires the `com.apple.security.virtualization`
entitlement, which only the signed Xcode-built app bundle has. To exercise it
locally, create a local signing override first:

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
so the private workspace is disabled in that mode.

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
the default MiniMax text model, and swapping to a different provider or
model is a Settings-only change. MiniMax Token's Text settings include a
version menu for MiniMax 2.7 (200k context) and MiniMax 3 (1M context).
By default, MiniMax routes Plan through MiniMax 3 and keeps Develop,
Reflect, Critic, and codemap summaries on the selected base version
(MiniMax 2.7 by default). The per-phase MiniMax menus can opt any role
into 2.7 or 3 explicitly; `COMPASS_AGENT_CONTEXT_WINDOW_TOKENS` still
overrides auto-compaction.

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
  `write_file`, `edit_file`, `bash`) inside Compass's private workspace:
  a persistent per-repo macOS workspace managed by the app. Plan and
  Reflect also use that workspace when it is ready; if the workspace
  infrastructure is unavailable they fall back to a direct host invocation.
  Develop must return `lessonEdits` instead of editing `.compass/lessons.md`
  directly, so durable lessons land in the main Compass workspace rather
  than only inside the private workspace.
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
  context. Agents can call `remove_assumption` when an active assumption
  becomes stale; Compass keeps the record as superseded history but stops
  injecting it into future prompts.
- History metadata is written to `.compass/sessions.jsonl`, with older
  records segmented into `.compass/sessions-archive/` when needed.
  Per-session audit events, manifests, and large artifacts live under
  `.compass/sessions/{session-number}/`.

## Compass Workspace

Everything lives in `.compass/` inside each selected repository:

```text
{repo}/.compass/
├── state.json        # Plan/Reflect own.
├── state.json.bak    # Best-effort backup before each iteration.
├── drafts.md         # User-owned draft queue.
├── lessons.md        # Durable guidance shared across iterations.
├── assumptions.json  # Agent-recorded assumptions and user reviews.
├── product-tournament.json # Pains, tournaments, contenders, rounds, experiments.
├── product-tournament/     # Tournament evidence, runs, and worktrees.
├── sessions.jsonl    # Per-iteration session index and latest feedback.
├── sessions-archive/ # Segmented older session records.
├── sessions/         # Session audit manifests, events, and artifacts.
└── COMPASS.md        # User-owned project vision.
```

## Explore

Explore is an AI-powered layer that helps users understand software produced
by Compass. Rather than leaving generated code opaque, it surfaces meaning —
what changed, why, and how the pieces fit together — using Apple's on-device
Foundation Models so explanations stay local and fast.

Explore has eight main components (some with both a model and a view layer):

- **`CodemapFileSystem`** (`Sources/Compass/Explore/CodemapFileSystem.swift`) —
  File-system scanner that walks the repository tree and produces a
  ``FileTreeNode`` hierarchy mirroring the source directory layout.
  Used by ``ExploreTreeBuilder`` when ``GitSourcePaths`` cannot enumerate
  files via `git ls-files` (e.g. in a fresh or sparse checkout).
  Available on all macOS versions. Entry point: ``CodemapFileSystem(rootURL:).buildSourceTree()``.

- **`CodemapGraphViz`** (`Sources/Compass/Explore/CodemapGraphViz.swift`) —
  Exports the import graph as an SVG for rendering in the Explore tab.
  Provides ``CodemapGraphVizExport`` which walks all indexed source files,
  resolves import declarations, and produces a styled graph.  Entry point:
  ``CodemapGraphVizExport.export(codemap:)``.

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

- **`CommitNarrator`** (`Sources/Compass/Explore/CommitNarrator.swift`) —
  Produces a single concise sentence describing a commit, suitable for
  notification banners, inline commit-list labels, or tour step headers.
  Uses `FoundationModelsAvailability.isAvailable` from the on-device Foundation Models
  framework. Requires **macOS 26** and is gated behind `@available(macOS 26.0, *)`.
  Returns `nil` gracefully when Foundation Models is unavailable. Distinct from
  ``CommitExplainer/summarize(diff:)`` which generates ~3 sentences for popovers.
  Entry point: ``CommitNarrator.narrate(commit:diff:)``.

| Component | File | Description |
| --- | --- | --- |
| ``CodemapFileSystem`` | `Sources/Compass/Explore/CodemapFileSystem.swift` | File-system scanner; entry point for the Explore tab's tree builder |
| ``CodemapGraphViz`` | `Sources/Compass/Explore/CodemapGraphViz.swift` | SVG export of the import graph; used by ``ArchitectureGraphPopover`` |
| ``CommitExplainer`` | `Sources/Compass/Explore/CommitExplainer.swift` | Summarises a single diff in plain English; also serves ``WhyGeneratedPopover`` |
| ``CommitTourGenerator`` | `Sources/Compass/Explore/CommitTourGenerator.swift` | Synthesises a multi-commit diff into a 3–5 sentence guided-tour narrative |
| ``ExploreRepositorySnapshot`` | `Sources/Compass/Explore/ExploreRepositorySnapshot.swift` | Immutable snapshot of file tree + indexed codemap entries |
| ``FileExplainer`` | `Sources/Compass/Explore/FileExplainer.swift` | Categorises changed files and produces per-file diff summaries |
| ``ArchitectureGraphPopover`` | `Sources/Compass/Views/ContentViewPlanTab.swift` | SwiftUI popover for the Explore tab; renders the SVG from ``CodemapGraphViz`` |
| ``WhyGeneratedPopover`` | `Sources/Compass/Views/ContentViewPlanTab.swift` | SwiftUI popover for the Explore tab; shows the "why this file exists" explanation |
| ``RepoQnA`` | `Sources/Compass/Explore/RepoQnA.swift` | Free-text Q&A about repository changes using on-device Foundation Models |

## Development

Two build flows coexist:

- `swift build` / `swift test` — fast, headless, no signing, no entitlements.
  Best for unit tests, type-checking, and CI.
- `xcodebuild -project Compass.xcodeproj -scheme Compass` — produces the
  signed `Compass.app` with the virtualization entitlement. Required for
  local private workspace runs.

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
  private workspace) and `keychain-access-groups` (for the workspace's
  secure connection credential, the only secret Compass still stores in
  the macOS Keychain).
  Add more entitlements here if Compass ever needs sandboxed network, hardware
  access, etc. App Sandbox is intentionally **off** — Compass is distributed
  outside the App Store (via `.dmg`), so the sandbox's file-access restrictions
  and security-scoped-bookmark dance are not needed.

Codesigning uses `App/Signing.xcconfig` plus the git-ignored
`App/LocalSigning.xcconfig` for personal team ids. For `.dmg` distribution,
swap to a Developer ID Application cert via Xcode -> Signing & Capabilities,
then notarize the resulting `.app` before packaging.

## Private Workspace: Shared VM Runtime

Compass runs every Develop iteration inside a private workspace backed by
a Compass-managed VM — currently the existing macOS guest, with the runtime
boundary being kept OS-neutral so a smaller Linux guest can replace it later.
Each project gets a persistent per-repo workspace inside that VM, and
Compass talks to its tools (`read_file`, `write_file`, `edit_file`, `bash`,
etc.) over vsock. The VM provisions Rust as a first-class generated-project
toolchain (`rustc`, `cargo`, `rustfmt`, `clippy`, and `cargo-llvm-cov`) so
Cargo build, lint, test, coverage, launch, and visual verification work
guest-local without host Xcode. It also installs `compass-engine` for
structured Rust workspace and diagnostic tooling. Once Verify passes, Compass
pulls the workspace back into the host repo so the iteration's commits land in
the main checkout.

Plan and Reflect use the same private workspace and vsock tool path when
the VM is ready. If the workspace catalog cannot map the repo or the VM is
unavailable, Compass falls back to a direct host invocation internally.
Only Develop iterations and their post-Verify file sync require the
workspace to be ready.

For blessed Rust desktop workspaces, post-checks can perform Level 2 visual
verification: build in the guest, launch the desktop app, wait for readiness,
send a platform-neutral input request through the Rust app's visual handshake,
capture a Rust-rendered viewport PNG artifact, save the audit artifact, and
terminate the app cleanly. Failures are reported as normal Verify feedback so
Develop can repair and retry.

The current macOS VM is built from scratch on the user's machine using
`VZMacOSRestoreImage.fetchLatestSupported` (Apple CDN, ~14 GB macOS restore
image, no auth) and installed via `VZMacOSInstaller`. After install, a
one-shot LaunchDaemon planted by Compass finishes first boot headlessly:
it creates the `compass` user, authorises Compass's SSH key, and enables
Remote Login without any user interaction. Subsequent iterations reuse
the same persistent workspace.

Requirements:

- Apple Silicon Mac, macOS 26 or newer.
- ~30 GB free disk under `~/Library/Application Support/Compass/SharedVM/`
  (sparse image — may drift larger over time).
- First-time setup takes ~25–45 minutes (macOS restore image download +
  install + headless first boot). One macOS admin authentication prompt fires
  during provisioning so Compass can plant the LaunchDaemon onto the
  freshly-installed Data volume.
- Apple's Virtualization.framework caps the host at 2 concurrent macOS
  guests. Conflicts with other VZ-based products (Parallels' VZ backend,
  Tart, etc.) surface in Compass as a private workspace capacity limit,
  backed by `Shared VM unavailable: 2-guest cap reached` in diagnostic logs.
  Develop stays blocked until the other guest exits.

When using Compass to develop Compass itself, treat the currently running
Compass process as infrastructure, not as the test subject. If a launch smoke
test is needed, start `swift run Compass` as a child process, record that exact
PID, and terminate only that PID after the check. Avoid broad process-killing
commands such as `pkill -f Compass` or `killall swift` that could stop the
live Compass session running the iteration. The private workspace makes this
safer by default — runaway `pkill` inside the workspace cannot reach the host
orchestrator.
