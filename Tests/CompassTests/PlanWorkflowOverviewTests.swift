import Foundation
import Testing

@testable import Compass

struct PlanWorkflowOverviewTests {
  @Test
  func testBuildsPopulatedOverviewSections() throws {
    let state = makeState(
      completed: ["Set up planning", "Ship history"],
      immediate: PlanNext(
        plan: " Build the overview \n\n - Keep completed summaries selectable ",
        verify: " swift test ",
        estimatedDifficulty: .medium
      ),
      candidates: "- Queue the next planning polish",
      strategicContext: "Make waiting time easier to understand."
    )

    let overview = PlanWorkflowOverview(state: state)

    try #require(overview.sections.map(\.kind) == [.immediate, .candidates, .strategicContext])
    try #require(
      overview.immediate.body == "Build the overview\n\n- Keep completed summaries selectable")
    try #require(overview.candidates.body == "- Queue the next planning polish")
    try #require(overview.strategicContext.body == "Make waiting time easier to understand.")
    try #require(!overview.immediate.isEmpty)
  }

  @Test
  func testOverviewKindsMapToStableTimelineDestinations() throws {
    try #require(PlanWorkflowOverview.Kind.immediate.timelineItemID == "plan-immediate")
    try #require(PlanWorkflowOverview.Kind.candidates.timelineItemID == "plan-candidates")
    try #require(
      PlanWorkflowOverview.Kind.strategicContext.timelineItemID == "plan-strategic-context")

    try #require(PlanWorkflowOverview.Kind(timelineItemID: "plan-immediate") == .immediate)
    try #require(PlanWorkflowOverview.Kind(timelineItemID: "plan-candidates") == .candidates)
    try #require(
      PlanWorkflowOverview.Kind(timelineItemID: "plan-strategic-context") == .strategicContext)
    try #require(PlanWorkflowOverview.Kind(timelineItemID: "plan-history-0") == nil)
  }

  @Test
  func testSectionTimelineDestinationsFollowOverviewOrder() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        completed: ["Past work"],
        candidates: "Queue",
        strategicContext: "Arc"
      )
    )

    try #require(overview.sections.map(\.kind) == [.immediate, .candidates, .strategicContext])
    try #require(
      overview.sections.map(\.timelineItemID) == [
        "plan-immediate", "plan-candidates", "plan-strategic-context",
      ]
    )
    try #require(
      PlanWorkflowOverview.TimelineDestination.allCases.map(\.overviewKind) == [
        .immediate, .candidates, .strategicContext,
      ]
    )
  }

  @Test
  func testNoImmediateStateKeepsCandidatesAndStrategyVisible() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        completed: ["Everything shipped"],
        immediate: nil,
        candidates: "- Later work",
        strategicContext: "Long arc"
      )
    )

    try #require(overview.immediate.isEmpty)
    try #require(overview.immediate.body == "")
    try #require(overview.immediate.excerpt == nil)
    try #require(overview.immediate.verifyCommand == nil)
    try #require(overview.immediate.verifyTimeoutLabel == nil)
    try #require(overview.immediate.estimatedDifficulty == nil)
    try #require(overview.candidates.excerpt == "- Later work")
    try #require(overview.strategicContext.excerpt == "Long arc")
  }

  @Test
  func testEmptyCandidatesAndStrategyExposeSpecificEmptyMessages() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        immediate: nil,
        candidates: " \n ",
        strategicContext: "\t"
      )
    )

    try #require(overview.candidates.isEmpty)
    try #require(overview.strategicContext.isEmpty)
    try #require(
      overview.candidates.emptyMessage
        == "No candidate directions yet. Plan can originate the next useful slice from the repo, drafts, feedback, or focus."
    )
    try #require(
      overview.strategicContext.emptyMessage
        == "No strategic context yet. Add durable thesis, principles, constraints, risks, or non-goals when they become clear."
    )
  }

  @Test
  func testNormalizesMarkdownWhitespace() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        candidates: " \tFirst\t\titem  \r\n\r\n\r\n  - Queue\t two  \r Continued    text \n\n",
        strategicContext: "  Arc\t\twith   spacing  "
      )
    )

    try #require(overview.candidates.body == "- First item\n- Queue two\n- Continued text")
    try #require(overview.strategicContext.body == "Arc with spacing")
  }

  @Test
  func testBoundsDenseExcerpts() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        strategicContext: "Alpha beta gamma delta epsilon zeta eta theta iota"
      ),
      excerptLimit: 25
    )

    try #require(overview.strategicContext.excerpt == "Alpha beta gamma delta...")
    try #require(overview.strategicContext.excerpt?.count ?? 0 <= 25)
  }

  @Test
  func testPreservesVerifyAndDifficultyMetadata() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        immediate: PlanNext(
          plan: "Implement the slice",
          verify: " swift test --filter PlanWorkflowOverviewTests ",
          estimatedDifficulty: .high
        )
      )
    )

    try #require(
      overview.immediate.verifyCommand == "swift test --filter PlanWorkflowOverviewTests")
    try #require(overview.immediate.estimatedDifficulty == .high)
    try #require(overview.immediate.estimatedDifficultyLabel == "High")
  }

  @Test
  func testVerifyTimeoutMetadataFormatsExplicitSeconds() throws {
    let metadata = PlanVerifyMetadata(timeoutMs: 90_000)

    try #require(metadata.label == "Timeout 90s")
  }

  @Test
  func testVerifyTimeoutMetadataFormatsExplicitMinutes() throws {
    let metadata = PlanVerifyMetadata(timeoutMs: 600_000)

    try #require(metadata.label == "Timeout 10m")
  }

  @Test
  func testVerifyTimeoutMetadataLabelsDefaultTimeout() throws {
    let metadata = PlanVerifyMetadata(timeoutMs: nil)

    try #require(metadata.label == "Default timeout 10m")
  }

  @Test
  func testSectionPropagatesVerifyTimeoutMetadataOnlyForImmediatePlan() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        immediate: PlanNext(
          plan: "Implement the slice",
          verify: "swift test --filter PlanWorkflowOverviewTests",
          verifyTimeoutMs: 90_000,
          estimatedDifficulty: .medium
        ),
        candidates: "Queue",
        strategicContext: "Arc"
      )
    )

    try #require(overview.immediate.verifyTimeoutLabel == "Timeout 90s")
    try #require(overview.sections.map(\.verifyTimeoutLabel) == ["Timeout 90s", nil, nil])
  }

  @Test
  func testSectionPropagatesDefaultVerifyTimeoutMetadataForImmediatePlan() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        immediate: PlanNext(
          plan: "Implement the slice",
          verify: "swift test --filter PlanWorkflowOverviewTests",
          estimatedDifficulty: .low
        )
      )
    )

    try #require(overview.immediate.verifyTimeoutLabel == "Default timeout 10m")
  }

  @Test
  func testPreservesCompletedCountMetadata() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(completed: ["one", "two", "three"])
    )

    try #require(overview.completedCount == 3)
    try #require(overview.sections.map(\.completedCount) == [3, 3, 3])
  }

  @Test
  func testVerifyCommandSummaryExplainsCommonTestCommands() throws {
    let swift = PlanVerifyCommandSummary(command: "swift test --filter DraftRefinementTests")
    try #require(swift.title == "Runs Swift tests")
    try #require(swift.detail == "Compass will run Swift tests focused on DraftRefinementTests.")
    try #require(swift.command == "swift test --filter DraftRefinementTests")

    let rust = PlanVerifyCommandSummary(command: "cargo test --all-features")
    try #require(rust.title == "Runs Rust tests")
    try #require(
      rust.detail == "Compass will run the Rust test suite with all feature flags enabled.")

    let xcode = PlanVerifyCommandSummary(
      command:
        "xcodebuild -scheme Compass -only-testing:CompassTests/PlanWorkflowOverviewTests test"
    )
    try #require(xcode.title == "Runs Xcode tests")
    try #require(
      xcode.detail
        == "Compass will run Xcode tests focused on CompassTests/PlanWorkflowOverviewTests."
    )

    let python = PlanVerifyCommandSummary(command: "uv run pytest tests/test_plan.py")
    try #require(python.title == "Runs Python tests")
    try #require(python.detail == "Compass will run the Python test suite with pytest.")

    let js = PlanVerifyCommandSummary(command: "npm run test -- --run")
    try #require(js.title == "Runs JavaScript tests")
    try #require(
      js.detail == "Compass will run the project's JavaScript or TypeScript test command.")
  }

  @Test
  func testVerifyCommandSummaryExplainsCoverageCommands() throws {
    let swift = PlanVerifyCommandSummary(
      command: "swift test --enable-code-coverage --filter DraftRefinementTests"
    )
    try #require(swift.title == "Runs Swift coverage")
    try #require(
      swift.detail
        == "Compass will run Swift tests focused on DraftRefinementTests. Coverage collection is enabled."
    )

    let rust = PlanVerifyCommandSummary(command: "cargo llvm-cov --summary-only")
    try #require(rust.title == "Runs Rust coverage")
    try #require(
      rust.detail == "Compass will run Rust tests through cargo-llvm-cov and report coverage.")

    let python = PlanVerifyCommandSummary(command: "uv run pytest --cov src tests")
    try #require(python.title == "Runs Python coverage")
    try #require(python.detail == "Compass will run pytest with Python coverage enabled.")

    let js = PlanVerifyCommandSummary(
      command: "pnpm test -- --coverage --coverage.reporter=json-summary"
    )
    try #require(js.title == "Runs JavaScript coverage")
    try #require(
      js.detail
        == "Compass will run the project's JavaScript or TypeScript tests with coverage enabled.")
  }

  @Test
  func testVerifyCommandSummaryExplainsBuildAndFallbackCommands() throws {
    let swiftBuild = PlanVerifyCommandSummary(command: "swift build --target CompassTests")
    try #require(swiftBuild.title == "Builds the Swift package")
    try #require(
      swiftBuild.detail == "Compass will compile the CompassTests target and fail on build errors.")

    let webBuild = PlanVerifyCommandSummary(command: "pnpm run build")
    try #require(webBuild.title == "Builds the web project")
    try #require(
      webBuild.detail
        == "Compass will run the project's build script and fail on compile or bundling errors.")

    let unknown = PlanVerifyCommandSummary(command: "make verify")
    try #require(unknown.title == "Runs verification")
    try #require(
      unknown.detail
        == "Compass will run the planned command and treat a non-zero exit as a failed check."
    )
  }

  @Test
  func testHandoffDigestExtractsPlainLanguageSections() throws {
    let digest = PlanHandoffDigest(
      plan: """
        ## Outcome
        Make draft polish available without Apple Intelligence.

        ## Why it matters
        Non-engineers still get a cleaner draft before planning.

        ## Acceptance checks
        - Preview appears for a non-empty draft.
        - Generated polish is used only when available.
        - Deterministic polish remains the fallback.
        - Extra checks stay hidden from the compact digest.
        """
    )

    try #require(digest.status == .ready)
    try #require(digest.title == "Executable handoff")
    try #require(digest.outcome == "Make draft polish available without Apple Intelligence.")
    try #require(
      digest.whyItMatters == "Non-engineers still get a cleaner draft before planning."
    )
    try #require(
      digest.acceptanceChecks == [
        "Preview appears for a non-empty draft.",
        "Generated polish is used only when available.",
        "Deterministic polish remains the fallback.",
      ]
    )
    try #require(digest.missingPieces.isEmpty)
  }

  @Test
  func testHandoffDigestAcceptsSuccessSignalWording() throws {
    let digest = PlanHandoffDigest(
      plan: """
        Outcome: Make setup progress understandable.

        Value: Non-engineers can decide whether to wait or change their draft.

        Success looks like:
        - Setup check shows the current stage.
        - A finish-line message appears when setup is done.
        """
    )

    try #require(digest.status == .ready)
    try #require(digest.outcome == "Make setup progress understandable.")
    try #require(
      digest.whyItMatters == "Non-engineers can decide whether to wait or change their draft.")
    try #require(
      digest.acceptanceChecks == [
        "Setup check shows the current stage.",
        "A finish-line message appears when setup is done.",
      ]
    )
    try #require(digest.missingPieces.isEmpty)
  }

  @Test
  func testHandoffDigestPreservesLeadingNumbersInAcceptanceChecks() throws {
    let digest = PlanHandoffDigest(
      plan: """
        ## Outcome
        Make error recovery understandable.

        ## Acceptance checks
        - [ ] 404 message explains the missing page.
        1. 2FA recovery copy stays visible after retry.
        2) [x] 500 error shows a support-safe next step.
        """
    )

    try #require(digest.status == .ready)
    try #require(
      digest.acceptanceChecks == [
        "404 message explains the missing page.",
        "2FA recovery copy stays visible after retry.",
        "500 error shows a support-safe next step.",
      ]
    )
    try #require(digest.missingPieces == [.whyItMatters])
  }

  @Test
  func testHandoffDigestIgnoresCommandOnlyAcceptanceChecks() throws {
    let digest = PlanHandoffDigest(
      plan: """
        ## Outcome
        Make run recovery safer.

        ## Acceptance checks
        - Verify: swift test --filter RecoveryTests
        - npm test
        - Retry button explains the saved failure before it runs again.
        """
    )

    try #require(digest.status == .ready)
    try #require(
      digest.acceptanceChecks == [
        "Retry button explains the saved failure before it runs again."
      ])
    try #require(
      digest.commandOnlyAcceptanceChecks == [
        "Verify: swift test --filter RecoveryTests",
        "npm test",
      ])

    let commandOnly = PlanHandoffDigest(
      plan: """
        ## Outcome
        Make run recovery safer.

        ## Acceptance checks
        - swift test --filter RecoveryTests
        - true
        """
    )

    try #require(commandOnly.status == .needsDetail)
    try #require(commandOnly.acceptanceChecks.isEmpty)
    try #require(
      commandOnly.commandOnlyAcceptanceChecks == [
        "swift test --filter RecoveryTests",
        "true",
      ])
    try #require(commandOnly.missingPieces == [.acceptanceChecks, .whyItMatters])
  }

  @Test
  func testHandoffDigestIgnoresVagueAcceptanceChecks() throws {
    let digest = PlanHandoffDigest(
      plan: """
        ## Outcome
        Make run recovery safer.

        ## Acceptance checks
        - The planned behavior is implemented.
        - It works.
        - Retry button explains the saved failure before it runs again.
        """
    )

    try #require(digest.status == .ready)
    try #require(
      digest.acceptanceChecks == [
        "Retry button explains the saved failure before it runs again."
      ])
    try #require(
      digest.vagueAcceptanceChecks == [
        "The planned behavior is implemented.",
        "It works.",
      ])

    let vagueOnly = PlanHandoffDigest(
      plan: """
        ## Outcome
        Make run recovery safer.

        ## Acceptance checks
        - The planned behavior is implemented.
        - <observable finish-line behavior>
        """
    )

    try #require(vagueOnly.status == .needsDetail)
    try #require(vagueOnly.acceptanceChecks.isEmpty)
    try #require(
      vagueOnly.vagueAcceptanceChecks == [
        "The planned behavior is implemented.",
        "<observable finish-line behavior>",
      ])
    try #require(vagueOnly.missingPieces == [.acceptanceChecks, .whyItMatters])
  }

  @Test
  func testHandoffDigestFlagsMissingAcceptanceChecks() throws {
    let digest = PlanHandoffDigest(
      plan: """
        Outcome: Explain why Develop is blocked.

        Why it matters: Owners need a plain-language next step.
        """
    )

    try #require(digest.status == .needsDetail)
    try #require(digest.title == "Handoff needs detail")
    try #require(digest.outcome == "Explain why Develop is blocked.")
    try #require(digest.acceptanceChecks.isEmpty)
    try #require(digest.missingPieces == [.acceptanceChecks])
    try #require(digest.detail.contains("Acceptance checks"))
  }

  @Test
  func testHandoffDigestFallsBackToFirstPlanLine() throws {
    let digest = PlanHandoffDigest(
      plan: """
        Add a launch checklist to the Plan tab.

        - Keep the exact verify command visible.
        """
    )

    try #require(digest.status == .needsDetail)
    try #require(digest.outcome == "Add a launch checklist to the Plan tab.")
    try #require(digest.missingPieces == [.acceptanceChecks, .whyItMatters])
  }

  @Test
  func testTournamentBriefSummarizesImmediateWorkForNonEngineers() throws {
    let state = makeState(
      completed: ["one", "two"],
      immediate: PlanNext(
        plan: """
          ## Outcome
          Make draft polish available when Apple Intelligence is off.

          ## Acceptance checks
          - Preview appears when Foundation Models are unavailable.
          """,
        verify: "swift test --filter DraftRefinementTests",
        verifyTimeoutMs: 90_000,
        estimatedDifficulty: .medium
      )
    )
    let brief = PlanTournamentBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: []),
      launchPlan: .host(fallbackReason: "Shared VM has not been provisioned yet."),
      languageProfile: profile(.swift)
    )

    try #require(brief.status == .ready)
    try #require(brief.title == "Ready To Build")
    try #require(
      brief.detail == "Next slice: Make draft polish available when Apple Intelligence is off."
    )
    try #require(brief.primaryActionLabel == "Run Develop")
    try #require(brief.proofLabel == "Runs Swift tests")
    try #require(
      brief.proofDetail == "Compass will run Swift tests focused on DraftRefinementTests."
    )
    try #require(brief.proofCommand == "swift test --filter DraftRefinementTests")
    try #require(brief.handoffDigest.status == .ready)
    try #require(
      brief.handoffDigest.outcome
        == "Make draft polish available when Apple Intelligence is off."
    )
    try #require(brief.routeLabel == "This Mac")
    try #require(brief.chips.map(\.label).contains("Swift"))
    try #require(brief.chips.map(\.label).contains("Medium difficulty"))
    try #require(brief.chips.map(\.label).contains("Timeout 90s"))
  }

  @Test
  func testTournamentBriefClipboardPayloadPackagesCurrentStateForReuse() throws {
    let state = makeState(
      completed: ["one", "two"],
      immediate: PlanNext(
        plan: """
          ## Outcome
          Make draft polish available when Apple Intelligence is off.

          ## Why it matters
          Non-engineers still need a clear next step.

          ## Acceptance checks
          - Preview appears when Foundation Models are unavailable.
          """,
        verify: "swift test --filter DraftRefinementTests",
        verifyTimeoutMs: 90_000,
        estimatedDifficulty: .medium
      )
    )
    let brief = PlanTournamentBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: []),
      launchPlan: .host(fallbackReason: "Shared VM has not been provisioned yet."),
      languageProfile: profile(.swift)
    )
    let payload = PlanTournamentBriefClipboardPayload(brief: brief)

    try #require(payload.text.contains("Compass PMF Proof Loop Brief Handoff"))
    try #require(payload.text.contains("Recipient instructions:"))
    try #require(payload.text.contains("Do not invent files, commands, credentials"))
    try #require(payload.text.contains("Status: Ready To Build (ready)"))
    try #require(payload.text.contains("Action: Run Develop"))
    try #require(payload.text.contains("Proof:\nRuns Swift tests"))
    try #require(payload.text.contains("swift test --filter DraftRefinementTests"))
    try #require(payload.text.contains("Runtime:\nThis Mac"))
    try #require(payload.text.contains("Status: Executable handoff"))
    try #require(
      payload.text.contains("Outcome: Make draft polish available when Apple Intelligence is off.")
    )
    try #require(payload.text.contains("Why it matters: Non-engineers still need"))
    try #require(
      payload.text.contains("- Preview appears when Foundation Models are unavailable.")
    )
    try #require(payload.text.contains("Context:\n- 2 completed"))
    try #require(payload.text.contains("- Swift"))
    try #require(payload.text.contains("- Medium difficulty"))
    try #require(payload.text.contains("- Timeout 90s"))
    try #require(payload.text.count <= PlanTournamentBriefClipboardPayload.textLimit)
    try #require(!payload.isEmpty)
  }

  @Test
  func testTournamentBriefPresentsReadySharedVMAsPrivateWorkspace() throws {
    let state = makeState(
      immediate: PlanNext(
        plan: """
          ## Outcome
          Make generated app changes safer.

          ## Acceptance checks
          - The run stays isolated from the user's project folder.
          """,
        verify: "swift test --filter PlanWorkflowOverviewTests",
        estimatedDifficulty: .low
      )
    )
    let route = SharedVMRoute(
      sshDestination: "compass@192.0.2.10",
      hostWorktreeURL: URL(fileURLWithPath: "/tmp/CompassRouteTest"),
      guestWorkspacePath: "/Users/compass/Compass/Repos/AAA/worktree"
    )
    let brief = PlanTournamentBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: []),
      launchPlan: AgentExecutionLaunchPlan(
        selectedPreference: .sharedVM,
        effectiveRoute: .sharedVM(route),
        vmReadiness: .ready(sshDestination: route.sshDestination)
      ),
      languageProfile: profile(.swift)
    )
    let payload = PlanTournamentBriefClipboardPayload(brief: brief)

    try #require(brief.routeLabel == "Private workspace")
    try #require(brief.routeDetail == "Develop will run inside your isolated private workspace.")
    try #require(brief.chips.map(\.label).contains("Private workspace"))
    try #require(payload.text.contains("Runtime:\nPrivate workspace"))
    try #require(!payload.text.contains("Shared VM"))
  }

  @Test
  func testTournamentBriefTranslatesWorkspaceFallbackReasonForNonEngineers() throws {
    let state = makeState(
      immediate: PlanNext(
        plan: """
          ## Outcome
          Make draft polish available when Apple Intelligence is off.

          ## Acceptance checks
          - Preview appears when Foundation Models are unavailable.
          """,
        verify: "swift test --filter DraftRefinementTests",
        estimatedDifficulty: .medium
      )
    )
    let brief = PlanTournamentBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: []),
      launchPlan: .host(fallbackReason: "Shared VM has not been provisioned yet."),
      languageProfile: profile(.swift)
    )
    let payload = PlanTournamentBriefClipboardPayload(brief: brief)

    try #require(brief.routeLabel == "This Mac")
    try #require(
      brief.routeDetail
        == "Compass is using this Mac because the private workspace has not been prepared yet."
    )
    try #require(payload.text.contains("Runtime:\nThis Mac"))
    try #require(!payload.text.contains("Shared VM"))
  }

  @Test
  func testTournamentBriefRoutesCoverageRepairBackToPlan() throws {
    let state = makeState(
      immediate: PlanNext(
        plan: """
          ## Outcome
          Add Rust coverage for parser failures.

          ## Acceptance checks
          - Rust tests exercise parser failures.
          """,
        verify: "cargo test"
      )
    )
    let brief = PlanTournamentBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: []),
      launchPlan: .host(),
      languageProfile: profile(.rust, hints: [.cargoToml]),
      forgeProfile: .rustCargo
    )

    try #require(brief.status == .planning)
    try #require(brief.title == "Clarify Before Building")
    try #require(brief.detail.contains("Coverage-ready verify"))
    try #require(brief.primaryActionLabel == "Run Plan")
    try #require(brief.proofLabel == "Runs Rust tests")
  }

  @Test
  func testHandoffRepairGuideCreatesTemplateForMissingImmediatePlan() throws {
    let guide = PlanHandoffRepairGuide(
      plan: "",
      verify: nil,
      languageProfile: profile(.swift, hints: [.packageSwift])
    )

    try #require(guide.status == .missingHandoff)
    try #require(guide.shouldShow)
    try #require(guide.title == "Create the handoff")
    try #require(guide.scoreLabel == "0 of 3 required")
    try #require(guide.suggestedVerifyCommand == "swift test")
    try #require(guide.steps.filter { $0.isRequired }.allSatisfy { !$0.isSatisfied })
    try #require(guide.planTemplate?.contains("## Outcome") == true)
    try #require(guide.planTemplate?.contains("\n\n## Why it matters\n") == true)
    try #require(guide.planTemplate?.contains("Verify: swift test") == true)
  }

  @Test
  func testHandoffRepairGuideFlagsWeakPlanAndPlaceholderVerify() throws {
    let guide = PlanHandoffRepairGuide(
      plan: "Make the Plan tab easier to read.",
      verify: #"echo "No tests available""#,
      languageProfile: profile(.typeScriptJavaScript, hints: [.packageJSON])
    )

    try #require(guide.status == .needsRepair)
    try #require(guide.shouldShow)
    try #require(guide.title == "Make this executable")
    try #require(
      guide.detail
        == "Add Acceptance checks and Verify command before Develop has a clear finish line.")
    try #require(guide.scoreLabel == "1 of 3 required")
    try #require(guide.steps[0].isSatisfied)
    try #require(!guide.steps[1].isSatisfied)
    try #require(!guide.steps[2].isSatisfied)
    try #require(!guide.steps[3].isSatisfied)
    try #require(!guide.steps[3].isRequired)
    try #require(guide.suggestedVerifyCommand == "npm test")
    try #require(guide.planTemplate?.contains("Make the Plan tab easier to read.") == true)
  }

  @Test
  func testHandoffRepairGuideFlagsFailureMaskingVerify() throws {
    let guide = PlanHandoffRepairGuide(
      plan: """
        ## Outcome
        Make retry recovery safer.

        ## Acceptance checks
        - Failed verification remains visible to the run controls.
        """,
      verify: "swift test || true",
      languageProfile: profile(.swift, hints: [.packageSwift])
    )

    try #require(guide.status == .needsRepair)
    try #require(guide.shouldShow)
    try #require(guide.scoreLabel == "2 of 3 required")
    try #require(guide.steps[0].isSatisfied)
    try #require(guide.steps[1].isSatisfied)
    try #require(!guide.steps[2].isSatisfied)
    try #require(
      guide.steps[2].detail == "Remove fallback no-op clauses so failed checks still fail.")
    try #require(guide.suggestedVerifyCommand == "swift test")
  }

  @Test
  func testHandoffRepairGuideExplainsCommandOnlyAcceptanceChecks() throws {
    let guide = PlanHandoffRepairGuide(
      plan: """
        ## Outcome
        Make retry recovery safer.

        ## Acceptance checks
        - Verify: swift test --filter RecoveryTests
        """,
      verify: "swift test --filter RecoveryTests",
      languageProfile: profile(.swift)
    )

    try #require(guide.status == .needsRepair)
    try #require(!guide.steps[1].isSatisfied)
    try #require(
      guide.steps[1].detail == "Replace command-only checks with observable finish-line behavior."
    )
  }

  @Test
  func testHandoffRepairGuideExplainsVagueAcceptanceChecks() throws {
    let guide = PlanHandoffRepairGuide(
      plan: """
        ## Outcome
        Make retry recovery safer.

        ## Acceptance checks
        - The planned behavior is implemented.
        """,
      verify: "swift test --filter RecoveryTests",
      languageProfile: profile(.swift)
    )

    try #require(guide.status == .needsRepair)
    try #require(!guide.steps[1].isSatisfied)
    try #require(
      guide.steps[1].detail == "Replace vague checks with specific observable finish-line behavior."
    )
  }

  @Test
  func testHandoffRepairGuideNarrationIdentifierTracksRepairSteps() throws {
    let guide = PlanHandoffRepairGuide(
      plan: "Make the Plan tab easier to read.",
      verify: "true",
      languageProfile: profile(.typeScriptJavaScript, hints: [.packageJSON])
    )

    try #require(guide.allowsNarration)
    try #require(guide.narrationIdentifier.contains("status:needsRepair"))
    try #require(guide.narrationIdentifier.contains("acceptanceChecks"))
    try #require(guide.narrationIdentifier.contains("verifyCommand"))
    try #require(guide.narrationIdentifier.contains("suggestedVerify:npm test"))
  }

  @Test
  func testHandoffRepairNarratorUsesFoundationModelsAsOptionalPolish() async throws {
    let guide = PlanHandoffRepairGuide(
      plan: "Make the Plan tab easier to read.",
      verify: "true",
      languageProfile: profile(.typeScriptJavaScript, hints: [.packageJSON])
    )

    try await withMockFoundationModels(
      response:
        "Plan needs observable acceptance checks and a real verify command before Develop can start."
    ) {
      let generatedNarration = await PlanHandoffRepairGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      try #require(narration.guideIdentifier == guide.narrationIdentifier)
      try #require(
        narration.text
          == "Plan needs observable acceptance checks and a real verify command before Develop can start."
      )
    }
  }

  @Test
  func testHandoffRepairNarratorSkipsReadyOrUnavailableGuides() async throws {
    let readyGuide = PlanHandoffRepairGuide(
      plan: """
        ## Outcome
        Add a readable tournament launch checklist.

        ## Acceptance checks
        - Checklist appears beside the immediate plan.
        """,
      verify: "swift test --filter PlanWorkflowOverviewTests",
      languageProfile: profile(.swift)
    )
    let repairGuide = PlanHandoffRepairGuide(
      plan: "Make the Plan tab easier to read.",
      verify: "true",
      languageProfile: profile(.swift)
    )

    try #require(!readyGuide.allowsNarration)
    await withMockFoundationModels(response: "Should not be used") {
      let narration = await PlanHandoffRepairGuideNarrator.narrate(guide: readyGuide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(available: false, response: "Should not be used") {
      let narration = await PlanHandoffRepairGuideNarrator.narrate(guide: repairGuide)
      #expect(narration == nil)
    }
  }

  @Test
  func testHandoffRepairNarratorRejectsStructuredBulletedOrLinkedOutput() async throws {
    let guide = PlanHandoffRepairGuide(
      plan: "Make the Plan tab easier to read.",
      verify: "true",
      languageProfile: profile(.swift)
    )

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await PlanHandoffRepairGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "- Add hidden work before repair") {
      let narration = await PlanHandoffRepairGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await PlanHandoffRepairGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  @Test
  func testHandoffRepairGuideFlagsMissingForgeCoverage() throws {
    let guide = PlanHandoffRepairGuide(
      plan: """
        ## Outcome
        Add Rust coverage for parser failures.

        ## Acceptance checks
        - Rust tests exercise parser failures.
        """,
      verify: "cargo test",
      languageProfile: profile(.rust, hints: [.cargoToml]),
      forgeProfile: .rustCargo
    )

    try #require(guide.status == .needsRepair)
    try #require(
      guide.detail == "Add Coverage-ready verify before Develop has a clear finish line.")
    try #require(guide.scoreLabel == "2 of 3 required")
    try #require(guide.steps[2].title == "Coverage-ready verify")
    try #require(guide.steps[2].detail == "Add coverage to the verify command for Rust (Cargo).")
    try #require(
      guide.suggestedVerifyCommand == "cargo llvm-cov --summary-only")
  }

  @Test
  func testHandoffRepairGuideHidesForExecutablePlanEvenWithoutOptionalWhy() throws {
    let guide = PlanHandoffRepairGuide(
      plan: """
        ## Outcome
        Add a readable tournament launch checklist.

        ## Acceptance checks
        - Checklist appears beside the immediate plan.
        - Focused Plan tests pass.
        """,
      verify: "swift test --filter PlanWorkflowOverviewTests",
      languageProfile: profile(.swift)
    )

    try #require(guide.status == .ready)
    try #require(!guide.shouldShow)
    try #require(guide.scoreLabel == "3 of 3 required")
    try #require(guide.planTemplate == nil)
    try #require(guide.suggestedVerifyCommand == "swift test --filter PlanWorkflowOverviewTests")
    try #require(guide.steps.filter { $0.isRequired }.allSatisfy { $0.isSatisfied })
    try #require(!guide.steps[3].isSatisfied)
  }

  @Test
  func testHandoffClipboardPayloadPackagesExecutablePlanForReuse() throws {
    let payload = PlanHandoffClipboardPayload(
      plan: """
        ## Outcome
        Add a readable tournament launch checklist.

        ## Why it matters
        Non-engineers can tell whether the next run is safe.

        ## Acceptance checks
        - Checklist appears beside the immediate plan.
        - Focused Plan tests pass.
        """,
      verify: "swift test --filter PlanWorkflowOverviewTests",
      languageProfile: profile(.swift)
    )

    try #require(payload.text.contains("Compass Immediate Work Handoff"))
    try #require(payload.text.contains("Recipient instructions:"))
    try #require(payload.text.contains("Do not invent files, commands, credentials"))
    try #require(
      payload.text.contains("implement only the Original plan and run Verify")
    )
    try #require(payload.text.contains("Status: Executable handoff"))
    try #require(payload.text.contains("Readiness: Ready for Develop (3 of 3 required)"))
    try #require(payload.text.contains("Outcome:\nAdd a readable tournament launch checklist."))
    try #require(
      payload.text.contains("- Checklist appears beside the immediate plan.")
    )
    try #require(
      payload.text.contains("Verify:\nswift test --filter PlanWorkflowOverviewTests")
    )
    try #require(!payload.text.contains("Repair before Develop:"))
    try #require(payload.text.count <= PlanHandoffClipboardPayload.textLimit)
  }

  @Test
  func testHandoffClipboardPayloadIncludesRepairTemplateForWeakPlan() throws {
    let payload = PlanHandoffClipboardPayload(
      plan: "Make the Plan tab easier to read.",
      verify: "true",
      languageProfile: profile(.typeScriptJavaScript, hints: [.packageJSON])
    )

    try #require(payload.text.contains("Status: Handoff needs detail"))
    try #require(payload.text.contains("Readiness: Make this executable (1 of 3 required)"))
    try #require(
      payload.text.contains("repair the handoff first and return the Suggested plan shape")
    )
    try #require(payload.text.contains("Missing handoff detail:\n- Acceptance checks"))
    try #require(payload.text.contains("Repair before Develop:"))
    try #require(payload.text.contains("- Verify command: Choose a real command"))
    try #require(payload.text.contains("Suggested verify: npm test"))
    try #require(payload.text.contains("Suggested plan shape:"))
    try #require(payload.text.contains("Original plan:\nMake the Plan tab easier to read."))
  }

  @Test
  func testHandoffRepairClipboardPayloadPackagesWeakPlanForAnotherModel() throws {
    let guide = PlanHandoffRepairGuide(
      plan: "Make the Plan tab easier to read.",
      verify: "true",
      languageProfile: profile(.typeScriptJavaScript, hints: [.packageJSON])
    )

    let payload = PlanHandoffRepairClipboardPayload(guide: guide)

    try #require(payload.text.contains("Compass Plan Repair Handoff"))
    try #require(payload.text.contains("Recipient instructions:"))
    try #require(payload.text.contains("Rewrite the handoff before any coding starts."))
    try #require(payload.text.contains("Use only the facts in this packet."))
    try #require(payload.text.contains("Return one repaired Immediate Work handoff"))
    try #require(payload.text.contains("Status: Make this executable"))
    try #require(payload.text.contains("Readiness: 1 of 3 required"))
    try #require(payload.text.contains("Instruction for Plan:"))
    try #require(payload.text.contains("Return one commit-sized Immediate Work handoff."))
    try #require(payload.text.contains("- Needed Acceptance checks (required)"))
    try #require(payload.text.contains("- Needed Verify command (required)"))
    try #require(payload.text.contains("- Needed Why (optional)"))
    try #require(payload.text.contains("Suggested verify:\nnpm test"))
    try #require(payload.text.contains("Suggested plan shape:"))
    try #require(payload.text.contains("## Outcome\nMake the Plan tab easier to read."))
    try #require(payload.text.count <= PlanHandoffRepairClipboardPayload.textLimit)
  }

  @Test
  func testHandoffRepairClipboardPayloadPackagesMissingPlanTemplate() throws {
    let guide = PlanHandoffRepairGuide(
      plan: "",
      verify: nil,
      languageProfile: profile(.swift, hints: [.packageSwift])
    )

    let payload = PlanHandoffRepairClipboardPayload(guide: guide)

    try #require(payload.text.contains("Status: Create the handoff"))
    try #require(payload.text.contains("Readiness: 0 of 3 required"))
    try #require(payload.text.contains("- Needed Outcome (required)"))
    try #require(payload.text.contains("- Needed Acceptance checks (required)"))
    try #require(payload.text.contains("- Needed Verify command (required)"))
    try #require(payload.text.contains("Suggested verify:\nswift test"))
    try #require(payload.text.contains("Verify: swift test"))
    try #require(!payload.isEmpty)
  }

  @Test
  func testTournamentBriefRoutesWeakHandoffsBackToPlan() throws {
    let state = makeState(
      immediate: PlanNext(
        plan: "Make the Plan tab easier to read.",
        verify: "swift test --filter PlanWorkflowOverviewTests",
        estimatedDifficulty: .low
      )
    )
    let brief = PlanTournamentBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: []),
      launchPlan: .host(),
      languageProfile: profile(.swift)
    )

    try #require(brief.status == .planning)
    try #require(brief.title == "Clarify Before Building")
    try #require(brief.primaryActionLabel == "Run Plan")
    try #require(brief.detail.contains("Acceptance checks"))
    try #require(brief.handoffDigest.status == .needsDetail)
  }

  @Test
  func testTournamentBriefPrioritizesReliabilityNotice() throws {
    let state = makeState()
    let session = SessionRecord(
      session: 4,
      startedAt: 4_000,
      endedAt: 4_500,
      plan: "Plan",
      verify: "swift test",
      beforeSha: nil,
      afterSha: nil,
      commits: [],
      status: .failed,
      notes: ["Develop reported it was blocked but did not request verify bypass."],
      verifyOutput: nil,
      feedback: "Missing signing credentials."
    )
    let brief = PlanTournamentBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: [session]),
      launchPlan: .host(fallbackReason: "Shared VM has not been provisioned yet."),
      languageProfile: profile(.swift)
    )

    try #require(brief.status == .needsAttention)
    try #require(brief.title == "Tournament Needs Attention")
    try #require(brief.detail.contains("Develop blocked"))
    try #require(brief.detail.contains("Missing signing credentials"))
    try #require(brief.primaryActionLabel == "Retry Develop")
  }

  @Test
  func testTournamentBriefFallsBackToCandidatesWhenNoImmediateWorkExists() throws {
    let state = makeState(
      immediate: nil,
      candidates: "- Improve onboarding language\n- Add tests",
      strategicContext: "Make Compass understandable."
    )
    let brief = PlanTournamentBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: []),
      launchPlan: .host(),
      languageProfile: .empty
    )

    try #require(brief.status == .planning)
    try #require(brief.title == "Ready To Choose The Next Slice")
    try #require(brief.detail.contains("Improve onboarding language"))
    try #require(brief.primaryActionLabel == "Run Plan")
    try #require(brief.proofDetail == "No verification command has been selected yet.")
  }

  @Test
  func testTournamentBriefNarratorUsesFoundationModelsAsOptionalPolish() async throws {
    let state = makeState()
    let brief = PlanTournamentBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: []),
      launchPlan: .host(),
      languageProfile: profile(.swift)
    )

    try await withMockFoundationModels(response: "Compass is ready to build the next slice.") {
      let generatedNarration = await PlanTournamentBriefNarrator.narrate(brief: brief)
      let narration = try #require(generatedNarration)
      try #require(narration.briefIdentifier == brief.narrationIdentifier)
      try #require(narration.text == "Compass is ready to build the next slice.")
    }

    try await withMockFoundationModels(available: false) {
      let narration = await PlanTournamentBriefNarrator.narrate(brief: brief)
      try #require(narration == nil)
    }
  }

  private func makeState(
    completed: [String] = [],
    immediate: PlanNext? = PlanNext(
      plan: "Default immediate",
      verify: "swift test",
      estimatedDifficulty: .low
    ),
    candidates: String = "",
    strategicContext: String = ""
  ) -> PlanState {
    PlanState(
      completed: completed,
      immediate: immediate,
      candidates: makeCandidates(candidates),
      strategicContext: PlanStrategicContext(thesis: strategicContext)
    )
  }

  private func makeCandidates(_ text: String) -> [PlanCandidate] {
    text.components(separatedBy: .newlines)
      .map { line in
        line.trimmingCharacters(in: .whitespacesAndNewlines)
          .replacingOccurrences(of: #"^[-*]\s*"#, with: "", options: .regularExpression)
      }
      .filter { !$0.isEmpty }
      .map { PlanCandidate(id: $0, title: $0, outcome: $0) }
  }

  private func profile(
    _ language: RepositoryLanguage,
    hints: [RepositoryManifestHint] = []
  ) -> RepositoryLanguageProfile {
    var counts = RepositoryLanguageCounts()
    counts[language] = 1
    return RepositoryLanguageProfile(
      counts: counts,
      manifestHints: hints,
      primaryLanguage: language,
      scannedFileCount: 1,
      scannedDirectoryCount: 1,
      wasTruncated: false
    )
  }
}
