import Foundation
import Testing

@testable import Compass

/// The Plan prompt has two failure modes worth pinning byte-for-byte:
///
///   * The agent wraps its `submit_result` payload in an extra `state:`
///     layer, which causes `PlanRunResult.init(from:)` to fail with a
///     "data couldn't be read because it is missing" decode error. The
///     prompt's `submit_result arguments` stanza spells out the
///     top-level shape and explicitly tells the model not to nest.
///
///   * The agent bakes an absolute `cd <workspace>` into the verify
///     command, which gets persisted to state.json and rots the moment
///     the workspace path changes. The planning rules say verify runs
///     with the workspace already as its cwd and no `cd` prefix is
///     allowed.
///
/// These tests assert on the wording the model pattern-matches against
/// so a future prompt edit that softens or drops them surfaces here.
struct PlanPromptTests {

  @Test func testPlanPromptForbidsWrappingSubmitResultInExtraState() throws {
    let prompt = try makePlanPrompt()
    try #require(
      prompt.contains("Do not wrap them in another object"),
      "plan prompt must warn against wrapping in an extra object"
    )
    // The phrase wraps across a line break in the triple-quoted
    // prompt, so check the two halves separately.
    try #require(
      prompt.contains("do not nest"),
      "plan prompt must call out nesting as the failure mode"
    )
    try #require(
      prompt.contains("another `state` field"),
      "plan prompt must name the `state` field as the trap"
    )
  }

  @Test func testPlanPromptOmitsCompletedFromSubmitResultShape() throws {
    let prompt = try makePlanPrompt()
    try #require(
      prompt.contains("Completed plan history is managed by Compass, not by submit_result"),
      "plan prompt must say history is outside submit_result"
    )
    try #require(
      prompt.contains("plan_history` tool"),
      "plan prompt must direct the agent to plan_history for prior work"
    )
    try #require(
      !prompt.contains("\"completed\""),
      "plan prompt submit_result shape must not include completed entries"
    )
  }

  @Test func testPlanPromptForbidsCdPrefixInVerifyCommand() throws {
    let prompt = try makePlanPrompt()
    try #require(
      prompt.contains("never prepend a `cd`"),
      "plan prompt must forbid prepending `cd` to the verify command"
    )
    try #require(
      prompt.contains("absolute paths to the working directory"),
      "plan prompt must call out absolute-path injection as the failure mode"
    )
  }

  @Test func testPlanPromptGuidesFeatureMatrixAndGrepVerifySemantics() throws {
    let prompt = try makePlanPrompt(forgeProfile: .rustCargo)
    try #require(prompt.contains("feature-gated"))
    try #require(prompt.contains("cargo test --all-features"))
    try #require(prompt.contains("Avoid brittle grep-only verify commands"))
    try #require(prompt.contains("no matches"))
  }

  @Test func testPlanPromptDeclaresRustOnlyGeneratedOutput() throws {
    let prompt = try makePlanPrompt(forgeProfile: .rustCargo)
    try #require(prompt.contains("Generated output target: Rust only"))
    try #require(prompt.contains("Compass itself is Swift/macOS"))
    try #require(prompt.contains("legacy imported Swift/TypeScript/JavaScript"))
    try #require(prompt.contains("crates/app-core"))
    try #require(prompt.contains("crates/app-desktop"))
    try #require(prompt.contains("eframe"))
    try #require(prompt.contains("egui"))
    try #require(prompt.contains("cargo run -p xtask -- visual-verify --emit-base64"))
  }

  @Test func testPlanPromptRequiresPlainLanguageExecutableHandoffs() throws {
    let prompt = try makePlanPrompt()
    try #require(prompt.contains("non-engineer owner"))
    try #require(prompt.contains("weaker Develop model"))
    try #require(prompt.contains("Outcome"))
    try #require(prompt.contains("Why it matters"))
    try #require(prompt.contains("Acceptance checks"))
    try #require(prompt.contains("explicit sequencing"))
    try #require(prompt.contains("Acceptance checks describe observable behavior"))
    try #require(prompt.contains("Put commands only in `state.immediate.verify`"))
    try #require(prompt.contains("or `Verify: ...` as acceptance bullets"))
    try #require(prompt.contains("Do not use placeholder checks"))
    try #require(prompt.contains("the planned behavior is"))
    try #require(prompt.contains("unedited template text"))
  }

  @Test func testPlanPromptIncludesCopyableImmediateHandoffTemplate() throws {
    let prompt = try makePlanPrompt()

    try #require(prompt.contains("Immediate handoff template"))
    try #require(prompt.contains("state.immediate.plan"))
    try #require(prompt.contains("```markdown"))
    try #require(prompt.contains("## Outcome\n<one sentence: what will change>"))
    try #require(
      prompt.contains("## Why it matters\n<who benefits and why this slice is worth doing now>"))
    try #require(prompt.contains("## Acceptance checks"))
    try #require(prompt.contains("<observable finish-line behavior Develop can verify>"))
    try #require(
      prompt.contains("<another observable result; `state.immediate.verify` must prove it>"))
    try #require(prompt.contains("## Sequence"))
    try #require(prompt.contains("Do not add speculative files"))
    try #require(prompt.contains("acceptance checks that the verify command cannot observe"))
    try #require(!prompt.contains("<the planned verify command proves the change>"))
  }

  @Test func testPlanPromptDefaultsTowardImmediatePlan() throws {
    let prompt = try makePlanPrompt()
    try #require(
      prompt.contains("Default to returning an Immediate Plan"),
      "plan prompt must bias the agent toward selecting concrete immediate work"
    )
    try #require(
      prompt.contains("Compass projects are almost")
        && prompt.contains("never truly done"),
      "plan prompt must frame project completion as rare"
    )
    try #require(
      prompt.contains("Strategic context alone is not remaining work"),
      "plan prompt must not treat strategic context as a task queue"
    )
  }

  /// The "submit_result arguments" stanza is the model's primary
  /// reference for the output shape. We previously duplicated it as
  /// a separate "State shape" section, and the redundancy caused the
  /// model to wrap its output in an extra `state:` layer. Pin the
  /// consolidation so the duplicate section doesn't sneak back in.
  @Test func testPlanPromptDoesNotIncludeRedundantStateShapeSection() throws {
    let prompt = try makePlanPrompt()
    try #require(
      !prompt.contains("State shape:"),
      "plan prompt previously duplicated the schema as a `State shape:` section; consolidated into submit_result arguments"
    )
  }

  @Test func testPlanPromptSubmitResultExampleUsesSchemaValidChoiceValues() throws {
    let prompt = try makePlanPrompt()

    try #require(prompt.contains("\"estimatedDifficulty\": \"low\""))
    try #require(!prompt.contains("\"estimatedDifficulty\": \"low|medium|high\""))
    try #require(prompt.contains("Replace `\"estimatedDifficulty\": \"low\"`"))
    try #require(prompt.contains("`\"medium\"` or `\"high\"`"))
    try #require(prompt.contains("replace the entire `immediate` object with `null`"))
    try #require(!prompt.contains("} | null"))
  }

  @Test func testHostXcodePlanningIsAbsentUnlessProjectOptInIsEnabled() throws {
    let state = PlanProposal(
      immediate: PlanNext(
        plan: "Build the app",
        verify: "xcodebuild -scheme App build",
        requiresHostXcode: true
      ),
      candidates: "",
      strategicContext: ""
    )

    let prompt = try Prompts.planPrompt(
      state: state,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature
    )

    #expect(!prompt.contains("requiresHostXcode"))
    #expect(!prompt.contains("Host Xcode"))
  }

  @Test func testHostXcodePlanningAppearsWhenProjectOptInIsEnabled() throws {
    let prompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature,
      hostXcodeBuildTestEnabled: true
    )

    #expect(prompt.contains("requiresHostXcode"))
    #expect(prompt.contains("\"requiresHostXcode\": true"))
    #expect(!prompt.contains("true|false"))
    #expect(prompt.contains("do not combine both choices in the JSON value"))
    #expect(prompt.contains("default to host-side execution"))
    #expect(prompt.contains("_TestingInterop"))
    #expect(!prompt.contains("simctl"))
    #expect(!prompt.contains("`open`"))
  }

  /// `.compass/` is supposed to be hidden from the agent — its
  /// contents are injected into the user message instead. The
  /// Draft and state storage are injected into the prompt rather than exposed
  /// as files the agent should inspect. Lessons are named explicitly because
  /// agents edit them through structured `lessonEdits`.
  @Test func testPlanPromptDoesNotMentionHiddenDraftOrStatePaths() throws {
    let prompt = try makePlanPrompt()
    try #require(
      !prompt.contains("drafts.md"),
      "plan prompt must not name `drafts.md` — describe drafts as host-side storage instead"
    )
    try #require(
      !prompt.contains("state.json"),
      "plan prompt must not name `state.json` — refer to `## Current planning state` instead"
    )
  }

  @Test func testReflectPromptDoesNotMentionHiddenStatePath() throws {
    let prompt = try Prompts.reflectPrompt(
      state: .empty,
      lessons: "",
      vision: "",
      recentSessions: [],
      iteration: 1
    )
    try #require(
      !prompt.contains("state.json"),
      "reflect prompt must not name `state.json`"
    )
  }

  @Test func testReflectPromptIncludesRecentSessionBriefForCourseCorrection() throws {
    let prompt = try Prompts.reflectPrompt(
      state: .empty,
      lessons: "",
      vision: "",
      recentSessions: [
        makeSession(
          7,
          startedAt: 7_000,
          status: .failed,
          plan: """
            ## Outcome
            Show plain-language reflection cues.

            ## Why it matters
            Smaller Reflect models can notice repeated failure patterns.

            ## Acceptance checks
            - Reflect prompt names the attempted outcome.
            - Reflect prompt explains the failed verify command.
            """,
          verify: "swift test --filter ReflectSessionBriefTests",
          notes: ["Develop reported failure: missing retry coverage."],
          verifyOutput: VerifyOutput(
            command: "swift test --filter ReflectSessionBriefTests",
            exitCode: 65,
            tail: "expected retry note in the reflection brief"
          ),
          feedback: "Retry with a smaller prompt-only slice."
        )
      ],
      iteration: 3
    )

    try #require(prompt.contains("## Recent session brief"))
    try #require(
      prompt.contains("Use this brief to spot patterns before reading the raw session JSON."))
    try #require(prompt.contains("Raw JSON below remains authoritative."))
    try #require(prompt.contains("Status mix: 1 failed."))
    try #require(prompt.contains("Session #7: Failed"))
    try #require(prompt.contains("Handoff: Executable handoff"))
    try #require(prompt.contains("Outcome: Show plain-language reflection cues."))
    try #require(prompt.contains("Acceptance: Reflect prompt names the attempted outcome."))
    try #require(prompt.contains("Verify: Runs Swift tests"))
    try #require(prompt.contains("focused on ReflectSessionBriefTests"))
    try #require(prompt.contains("Result: verify failed exit 65"))
    try #require(prompt.contains("Tail: expected retry note in the reflection brief"))
    try #require(prompt.contains("Feedback: Retry with a smaller prompt-only slice."))
    try #require(prompt.contains("Note: Develop reported failure: missing retry coverage."))
  }

  @Test func testReflectPromptIncludesCopyableSubmitResultShapes() throws {
    let prompt = try Prompts.reflectPrompt(
      state: .empty,
      lessons: "",
      vision: "",
      recentSessions: [],
      iteration: 1
    )

    try #require(prompt.contains("Copy this shape when no planning update is needed"))
    try #require(prompt.contains("\"state\": null"))
    try #require(prompt.contains("\"summary\": \"<why the current plan is still on course>\""))
    try #require(prompt.contains("\"lessonEdits\": []"))
    try #require(prompt.contains("containing all required keys"))
    try #require(prompt.contains("\"immediate\": null"))
    try #require(prompt.contains("\"candidates\": []"))
    try #require(prompt.contains("\"strategicContext\": {"))
    try #require(prompt.contains("\"openQuestions\": []"))
    try #require(prompt.contains("copy the full current immediate"))
    try #require(prompt.contains("Do not include completed"))
  }

  /// The focus block is what biases the planner away from compounding
  /// feature work. Pin both the header and a representative line from
  /// the interaction rules so a future prompt edit that drops the
  /// focus injection surfaces here rather than silently regressing.
  @Test func testPlanPromptIncludesFocusHeaderAndInteractionRules() throws {
    let prompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .test
    )
    try #require(
      prompt.contains("## Focus for this iteration: tests"),
      "plan prompt must include the focus header for the chosen focus"
    )
    try #require(
      prompt.contains("Drafts always win"),
      "plan prompt must keep the drafts-win-over-focus rule"
    )
    try #require(
      prompt.contains("pick the available candidate that best matches the focus"),
      "plan prompt must permit the focus to override candidate order"
    )
  }

  @Test func testPlanPromptIncludesDraftReadinessMap() throws {
    let prompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: """
        - Make setup faster because users get stuck; success looks like the setup check shows clear progress.

        - Improve onboarding copy
        """,
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature
    )

    try #require(prompt.contains("## Draft readiness map"))
    try #require(prompt.contains("Raw drafts are still authoritative"))
    try #require(prompt.contains("weaker Develop model"))
    try #require(prompt.contains("Draft 1: Ready for Plan (3 of 3)"))
    try #require(prompt.contains("Signals present: Outcome, Why, Success signal"))
    try #require(prompt.contains("Draft 2: Add one more signal (1 of 3)"))
    try #require(prompt.contains("Missing signals: Why, Success signal"))
    try #require(prompt.contains("supply the"))
    try #require(prompt.contains("missing clarity in the Immediate handoff"))
  }

  /// Each PlanFocus variant carries its own detail block. If one is
  /// ever dropped from the prompt the planner silently loses the
  /// steer for that category, so pin every variant.
  @Test func testPlanPromptIncludesDetailBlockForEachFocus() throws {
    for focus in PlanFocus.allCases {
      let prompt = try Prompts.planPrompt(
        state: .empty,
        completedCount: 0,
        drafts: "",
        feedback: "",
        lessons: "",
        vision: "",
        focus: focus
      )
      try #require(
        prompt.contains("## Focus for this iteration: \(focus.displayName)"),
        "plan prompt missing focus header for \(focus.displayName)"
      )
      try #require(
        prompt.contains("Focus details — \(focus.displayName):"),
        "plan prompt missing focus detail block for \(focus.displayName)"
      )
    }
  }

  @Test func testDevelopPromptDoesNotMentionHiddenDraftOrStatePaths() throws {
    let prompt = Prompts.developPrompt(
      next: PlanNext(
        plan: "p", verify: "swift build", verifyTimeoutMs: nil, estimatedDifficulty: nil),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )
    try #require(
      !prompt.contains("drafts.md"),
      "develop prompt must not name `drafts.md`"
    )
    try #require(
      !prompt.contains("state.json"),
      "develop prompt must not name `state.json`"
    )
  }

  @Test func testDevelopPromptCarriesUXAndGeneratedTextGuardrails() throws {
    let prompt = Prompts.developPrompt(
      next: PlanNext(
        plan: """
          ## Outcome
          Make setup status readable.

          ## Acceptance checks
          - Setup explains the next action.
          """,
        verify: "swift test --filter PlanPromptTests"
      ),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )

    try #require(prompt.contains("Build for non-engineer users"))
    try #require(prompt.contains("deterministic guides"))
    try #require(prompt.contains("Foundation Models"))
    try #require(prompt.contains("non-load-bearing"))
    try #require(prompt.contains("output sanitization"))
  }

  @Test func testDevelopPromptIncludesExecutableHandoffDigest() throws {
    let prompt = Prompts.developPrompt(
      next: PlanNext(
        plan: """
          ## Outcome
          Make draft polish available without Apple Intelligence.

          ## Why it matters
          Non-engineers still get a cleaner draft before planning.

          ## Acceptance checks
          - Preview appears for a non-empty draft.
          - Deterministic polish remains the fallback.
          """,
        verify: "swift test --filter DraftRefinementTests",
        verifyTimeoutMs: nil,
        estimatedDifficulty: .medium
      ),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )

    try #require(prompt.contains("## Execution handoff"))
    try #require(prompt.contains("Handoff status: Executable handoff"))
    try #require(prompt.contains("Treat the checks below as the finish line"))
    try #require(
      prompt.contains("Outcome: Make draft polish available without Apple Intelligence."))
    try #require(
      prompt.contains("Why it matters: Non-engineers still get a cleaner draft before planning."))
    try #require(prompt.contains("- Preview appears for a non-empty draft."))
    try #require(prompt.contains("Verify meaning: Runs Swift tests"))
    try #require(prompt.contains("focused on DraftRefinementTests"))
  }

  @Test func testDevelopPromptRequiresConcreteFeedbackHandoff() throws {
    let prompt = Prompts.developPrompt(
      next: PlanNext(
        plan: """
          ## Outcome
          Make Develop feedback harder to ignore.

          ## Acceptance checks
          - Placeholder feedback is rejected before the run finishes.
          """,
        verify: "swift test --filter DevelopFeedbackValidatorTests"
      ),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )

    try #require(prompt.contains("concrete handoff note for the next Plan pass"))
    try #require(prompt.contains("Do not use"))
    try #require(prompt.contains("`done`"))
    try #require(prompt.contains("No follow-up; verified <command>"))
    try #require(prompt.contains("smallest recovery action"))
  }

  @Test func testDevelopPromptIncludesCopyableSubmitResultShape() throws {
    let prompt = Prompts.developPrompt(
      next: PlanNext(
        plan: """
          ## Outcome
          Make Develop easier to finish.

          ## Acceptance checks
          - A schema-valid submit result example is available.
          """,
        verify: "swift test --filter PlanPromptTests"
      ),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )

    try #require(prompt.contains("Copy this shape when the implementation is complete"))
    try #require(prompt.contains("\"status\": \"succeeded\""))
    try #require(prompt.contains("\"bypassVerify\": false"))
    try #require(prompt.contains("\"lessonEdits\": []"))
    try #require(prompt.contains("`\"blocked\"` or `\"failed\"`"))
    try #require(!prompt.contains("succeeded|blocked|failed"))
  }

  @Test func testDevelopPromptRequiresConcreteVerifyBypassReason() throws {
    let prompt = Prompts.developPrompt(
      next: PlanNext(
        plan: """
          ## Outcome
          Make verify bypass harder to misuse.

          ## Acceptance checks
          - Verify bypass without a reason is rejected.
          """,
        verify: "swift test --filter DevelopVerifyBypassValidatorTests"
      ),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )

    try #require(prompt.contains("verify command itself is wrong or out"))
    try #require(prompt.contains("feedback` must explicitly name the concrete file"))
    try #require(prompt.contains("suite, command, or environment detail"))
    try #require(prompt.contains("smallest Plan recovery action"))
    try #require(prompt.contains("Do not use true because"))
    try #require(prompt.contains("not yet run"))
  }

  @Test func testDevelopPromptMentionsHostXcodeOnlyWhenEnabledAndRequired() throws {
    let next = PlanNext(
      plan: "Build the app",
      verify: "xcodebuild -scheme App build",
      requiresHostXcode: true
    )

    let disabled = Prompts.developPrompt(
      next: next,
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )
    let enabled = Prompts.developPrompt(
      next: next,
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: [],
      hostXcodeBuildTestEnabled: true
    )

    #expect(!disabled.contains("host_xcode"))
    #expect(enabled.contains("host_xcode"))
    #expect(enabled.contains("build/test checks only"))
  }

  @Test func testPhasePromptsIncludeAssumptionLedgerSection() throws {
    let assumptions = """
      User-affirmed assumptions (strong guidance)
      - [asm-1] The user wants a native macOS app.
      """
    let plan = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      assumptions: assumptions,
      vision: "",
      focus: .feature
    )
    let reflect = try Prompts.reflectPrompt(
      state: .empty,
      lessons: "",
      assumptions: assumptions,
      vision: "",
      recentSessions: [],
      iteration: 1
    )
    let develop = Prompts.developPrompt(
      next: PlanNext(plan: "p", verify: "swift build"),
      lessons: "",
      assumptions: assumptions,
      vision: "",
      attempt: 1,
      priorIssues: []
    )
    let critic = Prompts.criticPrompt(
      next: PlanNext(plan: "p", verify: "swift build"),
      developSummary: DevelopSummary(status: .succeeded, summary: "done", feedback: ""),
      verifyCommand: "swift build",
      verifyExitCode: 0,
      verifyOutput: "",
      gitDiff: "",
      priorCritiques: [],
      lessons: "",
      assumptions: assumptions,
      vision: "",
      iteration: 1,
      maxIterations: 3
    )

    for prompt in [plan, reflect, develop, critic] {
      try #require(prompt.contains("## Assumptions"))
      try #require(prompt.contains("The user wants a native macOS app."))
    }
    try #require(critic.contains("denied assumption"))
  }

  @Test func testPendingChangesCommitPromptIsCommitOnlyPreflight() throws {
    let system = Prompts.pendingChangesCommitSystemPrompt(
      workingDirectoryPath: "/tmp/CompassProject"
    )
    let user = Prompts.pendingChangesCommitPrompt(status: " M Sources/App.swift\n?? README.md")

    try #require(system.contains("preflight commit agent"))
    try #require(system.contains("commit-only preflight"))
    try #require(system.contains("Do not push"))
    try #require(system.contains("Do not use destructive Git commands"))
    try #require(system.contains("git reset --hard"))
    try #require(system.contains("\"status\": \"succeeded\""))
    try #require(user.contains(" M Sources/App.swift"))
    try #require(user.contains("?? README.md"))
    try #require(user.contains("git status --porcelain --untracked-files=all"))
  }

  private func makePlanPrompt(forgeProfile: ForgeProfile? = nil) throws -> String {
    try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature,
      forgeProfile: forgeProfile
    )
  }

  private func makeSession(
    _ number: Int,
    startedAt: Double,
    status: SessionStatus = .succeeded,
    plan: String? = "Plan",
    verify: String? = "swift test",
    commits: [SessionCommit] = [],
    notes: [String] = [],
    verifyOutput: VerifyOutput? = nil,
    feedback: String? = nil
  ) -> SessionRecord {
    SessionRecord(
      session: number,
      startedAt: startedAt,
      endedAt: startedAt + 500,
      plan: plan,
      verify: verify,
      beforeSha: nil,
      afterSha: nil,
      commits: commits,
      status: status,
      notes: notes,
      verifyOutput: verifyOutput,
      feedback: feedback
    )
  }
}
