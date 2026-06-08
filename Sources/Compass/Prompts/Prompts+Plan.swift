import Foundation

extension Prompts {
  static func planPrompt(
    state: PlanProposal,
    completedCount: Int,
    drafts: String,
    feedback: String,
    lessons: String,
    assumptions: String = "",
    vision: String,
    focus: PlanFocus,
    forgeProfile: ForgeProfile? = nil,
    coverageSnapshot: CoverageSnapshot? = nil,
    productTournamentConfig: ProductTournamentConfig = .empty,
    productTournamentEvidenceIndex: ProductTournamentEvidenceIndex = .empty,
    hostXcodeBuildTestEnabled: Bool = false
  ) throws -> String {
    let promptState = hostXcodeBuildTestEnabled ? state : state.removingHostXcodeRequirement()
    let stateJSON = try CompassWorkspace.encodeProposal(promptState.promptDigest())
    let draftIntakeGuide = DraftIntakeGuide(drafts: drafts)
    let lessonsDigest = compactPromptBlock(lessons, maxLines: 8, maxCharacters: 1800)
    let assumptionsDigest = compactPromptBlock(assumptions, maxLines: 8, maxCharacters: 1800)
    let feedbackDigest = compactPromptBlock(feedback, maxLines: 8, maxCharacters: 1800)
    let visionDigest = compactPromptBlock(vision, maxLines: 10, maxCharacters: 2400)
    let productTournamentDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: productTournamentConfig,
      evidenceIndex: productTournamentEvidenceIndex
    )
    let includeHostXcodeGuidance =
      hostXcodeBuildTestEnabled && forgeProfile != .rustCargo && forgeProfile != .typeScriptVitest
    let hostXcodePlanningRule =
      includeHostXcodeGuidance
      ? """
      - Shared VM develop/verify runs in the guest unless this increment uses
        host Xcode. For Swift, SwiftPM, macOS/iOS/tvOS/watchOS,
        Apple Intelligence / FoundationModels, and any Apple-platform build
        or test, default to host-side execution: set
        `requiresHostXcode` to true and choose an `xcodebuild ... build` or
        `xcodebuild ... test` verify command (never guest `swift test` or guest
        `xcodebuild` verify — the guest has Command Line Tools only and lacks
        libraries such as `_TestingInterop`). Do not pair `requiresHostXcode: true` with
        `swift test`; host Xcode verify commands must start with `xcodebuild`.
        For SwiftPM packages use the generated workspace when needed:
        `xcodebuild -workspace .swiftpm/xcode/package.xcworkspace -scheme <Package>-Package -destination 'platform=macOS' -skipMacroValidation ... test`.
        During Plan probing, use `host_xcode` instead of `bash` for these checks.
        Use `requiresHostXcode` for build/test only — not app launch, Simulator
        control, or arbitrary host shell.
      """
      : sharedVMApplePlatformPlanningRuleWhenHostXcodeDisabled(forgeProfile: forgeProfile)
    let compassTestsMigrationRule =
      includeHostXcodeGuidance
      ? """
      - While `CompassTests` is mid-migration from XCTest to Testing, do not plan
        guest `swift test` as verify. Use host `xcodebuild ... test` with
        `requiresHostXcode: true` when host Xcode is enabled; otherwise prefer
        `swift build --target CompassTests` for compile-only guest increments.
      """
      : """
      - While `CompassTests` is mid-migration from XCTest to Testing, do not plan
        guest `swift test` as verify. Prefer `swift build --target CompassTests`
        for compile-only guest increments.
      """
    let hostXcodeShape =
      includeHostXcodeGuidance
      ? ",\n            \"requiresHostXcode\": true"
      : ""
    let hostXcodeShapeGuidance =
      includeHostXcodeGuidance
      ? "When the field appears, set `requiresHostXcode` to the boolean `true` or `false`; do not combine both choices in the JSON value."
      : ""
    return """
      You are the Plan agent in Compass's Product Tournament work loop (see the system
      message for how the loop works). Treat the structured JSON you return as
      Compass's plan update contract.

      Your job is to choose exactly one concrete next implementation increment
      for the next Develop pass Compass will run automatically. You have read access to the repository and
      `bash` for probing — run builds, tests, or other shell commands when
      they would ground your decision. Do not edit files or commit. End by
      calling the `submit_result` tool with the arguments described below.

      Planning rules:
      - Start from the current planning state exactly as given.
      - Generated output target: Rust only. Compass itself is Swift/macOS, and
        legacy imported Swift/TypeScript/JavaScript repositories may still be
        inspected or repaired, but new generated projects, replacement
        scaffolds, frontends, CLIs, desktop apps, schemas, tests, and automation
        must default to Rust/Cargo.
      - For new Rust projects use Compass's blessed Cargo workspace:
        `crates/app-core`, `crates/app-cli`, `crates/app-desktop` using
        `eframe`/`egui`, `xtask`, `schemas/`, and `rust-toolchain.toml`.
        Keep generated apps conducive to deterministic simulation testing:
        user-visible behavior should flow through pure `app-core` transitions
        with explicit serializable inputs and stable snapshot/event-log outputs
        exposed by `app-cli`, so agents can safely "use" the app in a sandboxed,
        replayable path without relying on GUI automation or ambient host state.
        For GUI behavior, prefer semantic replay traces and snapshots
        (`gui-replay`) as the deterministic assertion surface; use screenshots
        as rendering proof, not as the only source of truth. Desktop visual
        proof should show the project or contender UI being built, not the
        untouched Compass scaffold labels or generic demo panel.
        Standard checks are `cargo fmt --all --check`,
        `cargo clippy --workspace --all-targets --all-features -- -D warnings`,
        `cargo test --workspace --all-features`, `cargo build --workspace`,
        and, for desktop UI, `cargo run -p xtask -- visual-verify --emit-base64`.
      - Completed plan history is managed by Compass, not by submit_result.
        Compass has \(completedCount) completed iteration(s) on record. Use the
        `plan_history` tool when prior shipped work would inform your choice.
      - Revise `candidates`, `strategicContext`, and `openQuestions` only when
        this iteration has a concrete reason. Do not use them as archives.
      - Ground the plan in the repository before choosing work.
      - Default to returning an Immediate Plan. Compass projects are almost
        never truly done; if you can name any useful cleanup, test, polish,
        documentation, reliability, or exploration increment, choose it as
        `immediate`.
      - Pick one commit-sized `immediate` with a real verify command that proves
        the important behavior. If there are no relevant tests, use build or
        typecheck as the fallback.
      - Write `immediate.plan` as a handoff that a non-engineer owner can
        understand and a weaker Develop model can execute. Prefer short
        markdown sections named `Outcome`, `Why it matters`, and
        `Acceptance checks`; keep jargon explained, name the concrete surface
        being changed, and include explicit sequencing when order matters.
        Acceptance checks describe observable behavior or UI/state outcomes,
        not shell commands. Put commands only in `state.immediate.verify`;
        never write checks like `swift test`, `npm test`, `cargo test`,
        `pytest`, or `Verify: ...` as acceptance bullets.
        Do not use placeholder checks like `the planned behavior is
        implemented`, `it works`, or unedited template text.
      - Set `immediate.selectedBecause` to a one-sentence reason for choosing
        this slice now. Set `immediate.source` to one of: `draft`, `feedback`,
        `candidate`, `focus`, `repository`, `repair`. If the slice came from a
        candidate, set `immediate.candidateID` to that candidate's `id`.
      - If the increment touches feature-gated, optional-provider, platform-specific,
        or conditional-compilation code, plan a verify matrix that compiles the
        relevant variants (for Rust/Cargo this usually means including
        `cargo test --all-features` or an equivalent all-feature check).
      - The verify command runs with the repo working tree already as its
        current directory. Write it as a plain command — e.g. `swift build`,
        `swift test`, `make check` — and never prepend a `cd` or include
        absolute paths to the working directory. Those paths get saved to
        state and rot the moment the working directory changes.
      - Avoid brittle grep-only verify commands. If a verify step uses `grep`,
        make the intended presence/absence semantics explicit so "no matches"
        cannot accidentally fail a successful build.
      - Use `immediate: null` only when there are no actionable candidates,
        no blocking feedback, no useful repo-originated cleanup/test/docs slice,
        and no draft intent waiting to be turned into work.
        Strategic context alone is not remaining work.
      - If feedback reports a blocker, plan the next smallest step that resolves
        it or rescope so Develop can make progress.
      - Treat product tournament evidence as advisory product pressure, not an
        engineering failure or Verify bypass. It can motivate product changes,
        reprioritize roadmap work, challenge the pain or contender plan,
        or expose evidence gaps, but normal build/test/verify discipline still
        applies.
      - Start tournament planning from the active pain hypotheses, product
        tournament rounds, contenders, and experiment branches in Product
        Tournament Context. Choose work that advances one contender in one round
        whenever that is the sharpest next step.
      - Round 1 is plan-only: do not implement product code just to compare
        product plans. Improve the plan, scenario, simulated-user prompt, or
        evaluation rubric when the current round is `product_plans`.
      - If Round 1 plan readiness has already been applied, respect contender
        statuses: build Round 2 only for narrowed survivors, revise
        `needs_revision` contenders before more implementation, and do not spend
        implementation work on eliminated contenders.
      - Round 2 should prove the core technology for a surviving contender.
        Round 3 should exercise a low-medium fidelity product implementation.
      - When Product Tournament Context includes a "Round 2 implementation target",
        treat it as the current implementation target: the Immediate handoff
        must name `selected_experiment`, use that branch/worktree, build only
        `only_contender`, and keep the Outcome scoped to the named
        `core_technology_proof`. Pull at least one Acceptance check from the
        target's acceptance signals.
      - When Product Tournament Context includes `round_2_evidence_lock`, treat
        `paused_sibling_experiments` as intentionally paused tournament tracks.
        Do not plan scenario, cohort, Tournament Automation, or implementation work for
        those siblings until Round 2 transitions; mention the pause in Outcome
        or Why it matters when it could otherwise look like missing evidence.
      - When Product Tournament Context includes only a "Round 2 feasibility
        handoff", treat it as supporting evidence for the same narrowed
        contender: scope one Immediate around that contender's experiment
        branch/worktree and the named core-technology proof.
      - Preserve contender and experiment branch isolation. Do not plan one
        Immediate handoff that implements several competing contenders at once.
        If the slice truly serves more than one contender, explicitly scope it
        as shared tournament infrastructure and explain why it is not
        contender-specific work.
      - Use deterministic product tournament simulation fixtures before live
        persona-model runs when possible, so evidence can be replayed and
        compared across revisions.
      - Distinguish engineering failures from tournament risks and evidence
        gaps. Repeated target-persona confusion or objections should influence
        the next increment when they are fresher or more specific than generic
        roadmap ideas.
      - If evidence is thin, stale, or missing for active tournament contenders,
        prefer an increment that improves the deterministic experience contract,
        creates a better scenario, or makes simulation easier to run. Do not
        blindly optimize for simulated praise.
      - If weak evidence comes from a shallow implementation, plan a sharper
        contender or implementation slice before declaring the pain invalid.
      - If drafts are empty, choose a useful candidate that matches the focus, or
        originate a new candidate from the repo, lessons, completed history, and
        strategic context.
      - Use the Draft readiness map as a deterministic checklist for user
        intent. Raw drafts are still authoritative; the map only tells you
        whether each draft already names an Outcome, Why, and Success signal.
        If a signal is missing, preserve the user's words and supply the
        missing clarity in the Immediate handoff instead of inventing facts.
      - Keep `candidates` to at most 6 active candidate directions. Drop `done`
        and `stale` entries instead of carrying shipped archives forward.
      - Keep `strategicContext` strategic and stable: thesis, principles,
        constraints, non-goals, and risks. Do not put task lists or shipped
        milestone inventories there.
      - Keep `openQuestions` to at most 4 consequential unresolved questions.
      - Never choose placeholder verify commands like `true`, `exit 0`,
        `echo no tests`, `not-running-tests`, `none`, or `n/a`.
      \(compassTestsMigrationRule)
      - Compass projects use opinionated forge profiles. Rust/Cargo is the sole
        generated-project profile; SwiftPM and TypeScript/Vitest are legacy
        imported-repo profiles only. Test verify commands must collect coverage
        — see the forge profile section below. Compile-only verify may omit coverage.
      \(forgeCoveragePlanningRules(forgeProfile: forgeProfile))
      - Never write code or commit from Plan. Running builds, tests, or other
        read-only shell commands to confirm assumptions is fine; that's what
        `bash` is for here.
      \(hostXcodePlanningRule)

      Immediate handoff template — when `state.immediate` is not null, make
      `state.immediate.plan` follow this exact compact Markdown shape. Replace
      the bracketed text; keep the headings:
      ```markdown
      ## Outcome
      <one sentence: what will change>

      ## Why it matters
      <who benefits and why this slice is worth doing now>

      ## Acceptance checks
      - <observable finish-line behavior Develop can verify>
      - <another observable result; `state.immediate.verify` must prove it>
      ```
      If sequencing matters, add a short `## Sequence` section after Why it
      matters with 2-4 ordered steps. Do not add speculative files, fake test
      names, or acceptance checks that the verify command cannot observe.

      \(lessonEditsGuidance())

      submit_result arguments — call the tool with EXACTLY this shape.
      The top-level object has exactly two keys: `state` and
      `lessonEdits`. Do not wrap them in another object; do not nest
      the result under another `state` field.
      {
        "state": {
          "immediate": {
            "plan": "markdown plan for one implementation increment",
            "verify": "shell command — no `cd` prefix, no absolute paths",
            "verifyTimeoutMs": 600000,
            "estimatedDifficulty": "low",
            "selectedBecause": "why this slice is the right next step",
            "source": "candidate",
            "candidateID": "candidate-id-if-applicable"\(hostXcodeShape)
          },
          "candidates": [
            {
              "id": "stable-slug",
              "title": "short candidate title",
              "outcome": "what would change",
              "why": "why this remains worth doing",
              "category": "feature",
              "origin": "plan",
              "priority": "medium",
              "status": "available",
              "evidence": [],
              "blockedBy": [],
              "risk": null
            }
          ],
          "strategicContext": {
            "thesis": "durable product intent",
            "principles": [],
            "constraints": [],
            "nonGoals": [],
            "risks": []
          },
          "openQuestions": []
        },
        "lessonEdits": [
          {
            "find": "exact current text",
            "replace": "replacement text",
            "replaceAll": false
          }
        ]
      }
      Replace `"estimatedDifficulty": "low"` with `"medium"` or `"high"` only when \
      that better fits. If the project is genuinely complete, replace the entire \
      `immediate` object with `null`; keep `candidates`, `strategicContext`, \
      `openQuestions`, and `lessonEdits` present. \(hostXcodeShapeGuidance)

      \(focus.promptGuidance)

      ## Current planning state
      Compact digest only. Compass intentionally omits shipped roadmap archives
      from this block; use `plan_history` if older shipped work matters.

      ```json
      \(stateJSON)
      ```

      ## Drafts from the user
      Compass snapshotted these drafts immediately before invoking you
      and cleared them from host-side storage. Drafts arriving during
      this run will be picked up next iteration.

      \(fencedOrEmpty(drafts, empty: "_(no new drafts)_"))

      ## Draft readiness map
      Deterministic preflight over the snapshotted drafts. Use it to keep
      the next Immediate Plan concrete enough for a weaker Develop model.

      \(draftIntakeGuide.promptText)

      ## Feedback from the previous Develop pass
      This is the latest non-empty Develop feedback from a prior completed
      session. Use it to fix a blocker or continue from state alone.

      \(fencedOrEmpty(feedbackDigest, empty: "_(no feedback)_"))

      ## Lessons
      \(fencedOrEmpty(lessonsDigest, empty: "_(no lessons yet)_"))

      ## Assumptions
      \(fencedOrEmpty(assumptionsDigest, empty: "_(no assumptions recorded)_"))

      ## Vision
      \(fencedOrEmpty(visionDigest, empty: "_(no vision set)_"))

      ## Product Tournament Context
      \(productTournamentDigest)

      \(forgeProfileSection(forgeProfile: forgeProfile))

      ## Coverage (last successful verify)
      \(coverageSnapshot?.formattedForPrompt() ?? "_(no coverage snapshot yet)_")

      When you have decided the next increment, call submit_result with the
      arguments shape above.
      """
  }

  private static func compactPromptBlock(
    _ text: String,
    maxLines: Int,
    maxCharacters: Int
  ) -> String {
    let normalized =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var seen = Set<String>()
    var lines: [String] = []
    for rawLine in normalized.components(separatedBy: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }
      guard !seen.contains(line) else { continue }
      seen.insert(line)
      lines.append(line)
      if lines.count >= maxLines { break }
    }
    let joined = lines.joined(separator: "\n")
    guard joined.count > maxCharacters else { return joined }
    return String(joined.prefix(max(0, maxCharacters - 3)))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
