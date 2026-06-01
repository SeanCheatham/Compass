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
      midTerm: "- Queue the next planning polish",
      longTerm: "Make waiting time easier to understand."
    )

    let overview = PlanWorkflowOverview(state: state)

    try #require(overview.sections.map(\.kind) == [.immediate, .midTerm, .longTerm])
    try #require(
      overview.immediate.body == "Build the overview\n\n- Keep completed summaries selectable")
    try #require(overview.midTerm.body == "- Queue the next planning polish")
    try #require(overview.longTerm.body == "Make waiting time easier to understand.")
    try #require(!overview.immediate.isEmpty)
  }

  @Test
  func testOverviewKindsMapToStableTimelineDestinations() throws {
    try #require(PlanWorkflowOverview.Kind.immediate.timelineItemID == "plan-immediate")
    try #require(PlanWorkflowOverview.Kind.midTerm.timelineItemID == "plan-mid-term")
    try #require(PlanWorkflowOverview.Kind.longTerm.timelineItemID == "plan-long-term")

    try #require(PlanWorkflowOverview.Kind(timelineItemID: "plan-immediate") == .immediate)
    try #require(PlanWorkflowOverview.Kind(timelineItemID: "plan-mid-term") == .midTerm)
    try #require(PlanWorkflowOverview.Kind(timelineItemID: "plan-long-term") == .longTerm)
    try #require(PlanWorkflowOverview.Kind(timelineItemID: "plan-history-0") == nil)
  }

  @Test
  func testSectionTimelineDestinationsFollowOverviewOrder() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        completed: ["Past work"],
        midTerm: "Queue",
        longTerm: "Arc"
      )
    )

    try #require(overview.sections.map(\.kind) == [.immediate, .midTerm, .longTerm])
    try #require(
      overview.sections.map(\.timelineItemID) == [
        "plan-immediate", "plan-mid-term", "plan-long-term",
      ]
    )
    try #require(
      PlanWorkflowOverview.TimelineDestination.allCases.map(\.overviewKind) == [
        .immediate, .midTerm, .longTerm,
      ]
    )
  }

  @Test
  func testNoImmediateStateKeepsQueueAndArcVisible() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        completed: ["Everything shipped"],
        immediate: nil,
        midTerm: "- Later work",
        longTerm: "Long arc"
      )
    )

    try #require(overview.immediate.isEmpty)
    try #require(overview.immediate.body == "")
    try #require(overview.immediate.excerpt == nil)
    try #require(overview.immediate.verifyCommand == nil)
    try #require(overview.immediate.verifyTimeoutLabel == nil)
    try #require(overview.immediate.estimatedDifficulty == nil)
    try #require(overview.midTerm.excerpt == "- Later work")
    try #require(overview.longTerm.excerpt == "Long arc")
  }

  @Test
  func testEmptyQueueAndArcExposeSpecificEmptyMessages() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        immediate: nil,
        midTerm: " \n ",
        longTerm: "\t"
      )
    )

    try #require(overview.midTerm.isEmpty)
    try #require(overview.longTerm.isEmpty)
    try #require(
      overview.midTerm.emptyMessage
        == "No mid-term queue. Future planning has no staged direction yet.")
    try #require(
      overview.longTerm.emptyMessage
        == "No long-term arc. Add the larger product direction when it becomes clear.")
  }

  @Test
  func testNormalizesMarkdownWhitespace() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        midTerm: " \tFirst\t\titem  \r\n\r\n\r\n  - Queue\t two  \r Continued    text \n\n",
        longTerm: "  Arc\t\twith   spacing  "
      )
    )

    try #require(overview.midTerm.body == "First item\n\n- Queue two\nContinued text")
    try #require(overview.longTerm.body == "Arc with spacing")
  }

  @Test
  func testBoundsDenseExcerpts() throws {
    let overview = PlanWorkflowOverview(
      state: makeState(
        longTerm: "Alpha beta gamma delta epsilon zeta eta theta iota"
      ),
      excerptLimit: 25
    )

    try #require(overview.longTerm.excerpt == "Alpha beta gamma delta...")
    try #require(overview.longTerm.excerpt?.count ?? 0 <= 25)
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
        midTerm: "Queue",
        longTerm: "Arc"
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

    let go = PlanVerifyCommandSummary(command: "go test ./...")
    try #require(go.title == "Runs Go tests")
    try #require(go.detail == "Compass will run Go tests across every package in the module.")

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
  func testFactoryBriefSummarizesImmediateWorkForNonEngineers() throws {
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
    let brief = PlanFactoryBrief(
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
    try #require(brief.routeLabel == "Native macOS")
    try #require(brief.chips.map(\.label).contains("Swift"))
    try #require(brief.chips.map(\.label).contains("Medium difficulty"))
    try #require(brief.chips.map(\.label).contains("Timeout 90s"))
  }

  @Test
  func testFactoryBriefRoutesCoverageRepairBackToPlan() throws {
    let state = makeState(
      immediate: PlanNext(
        plan: """
          ## Outcome
          Add Go coverage for parser failures.

          ## Acceptance checks
          - Go tests exercise parser failures.
          """,
        verify: "go test ./..."
      )
    )
    let brief = PlanFactoryBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: []),
      launchPlan: .host(),
      languageProfile: profile(.go, hints: [.goMod]),
      forgeProfile: .goModule
    )

    try #require(brief.status == .planning)
    try #require(brief.title == "Clarify Before Building")
    try #require(brief.detail.contains("Coverage-ready verify"))
    try #require(brief.primaryActionLabel == "Run Plan")
    try #require(brief.proofLabel == "Runs Go tests")
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
  func testHandoffRepairGuideFlagsMissingForgeCoverage() throws {
    let guide = PlanHandoffRepairGuide(
      plan: """
        ## Outcome
        Add Go coverage for parser failures.

        ## Acceptance checks
        - Go tests exercise parser failures.
        """,
      verify: "go test ./...",
      languageProfile: profile(.go, hints: [.goMod]),
      forgeProfile: .goModule
    )

    try #require(guide.status == .needsRepair)
    try #require(guide.detail == "Add Coverage-ready verify before Develop has a clear finish line.")
    try #require(guide.scoreLabel == "2 of 3 required")
    try #require(guide.steps[2].title == "Coverage-ready verify")
    try #require(guide.steps[2].detail == "Add coverage to the verify command for Go (module).")
    try #require(guide.suggestedVerifyCommand == "go test -coverprofile=.compass/coverage.out ./...")
  }

  @Test
  func testHandoffRepairGuideHidesForExecutablePlanEvenWithoutOptionalWhy() throws {
    let guide = PlanHandoffRepairGuide(
      plan: """
        ## Outcome
        Add a readable factory launch checklist.

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
        Add a readable factory launch checklist.

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
    try #require(payload.text.contains("Status: Executable handoff"))
    try #require(payload.text.contains("Readiness: Ready for Develop (3 of 3 required)"))
    try #require(payload.text.contains("Outcome:\nAdd a readable factory launch checklist."))
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
  func testFactoryBriefRoutesWeakHandoffsBackToPlan() throws {
    let state = makeState(
      immediate: PlanNext(
        plan: "Make the Plan tab easier to read.",
        verify: "swift test --filter PlanWorkflowOverviewTests",
        estimatedDifficulty: .low
      )
    )
    let brief = PlanFactoryBrief(
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
  func testFactoryBriefPrioritizesReliabilityNotice() throws {
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
    let brief = PlanFactoryBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: [session]),
      launchPlan: .host(fallbackReason: "Shared VM has not been provisioned yet."),
      languageProfile: profile(.swift)
    )

    try #require(brief.status == .needsAttention)
    try #require(brief.title == "Factory Needs Attention")
    try #require(brief.detail.contains("Develop blocked"))
    try #require(brief.detail.contains("Missing signing credentials"))
    try #require(brief.primaryActionLabel == "Retry Develop")
  }

  @Test
  func testFactoryBriefFallsBackToQueueWhenNoImmediateWorkExists() throws {
    let state = makeState(
      immediate: nil,
      midTerm: "- Improve onboarding language\n- Add tests",
      longTerm: "Make Compass understandable."
    )
    let brief = PlanFactoryBrief(
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
  func testFactoryBriefNarratorUsesFoundationModelsAsOptionalPolish() async throws {
    let state = makeState()
    let brief = PlanFactoryBrief(
      state: state,
      reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: []),
      launchPlan: .host(),
      languageProfile: profile(.swift)
    )

    try await withMockFoundationModels(response: "Compass is ready to build the next slice.") {
      let generatedNarration = await PlanFactoryBriefNarrator.narrate(brief: brief)
      let narration = try #require(generatedNarration)
      try #require(narration.briefIdentifier == brief.narrationIdentifier)
      try #require(narration.text == "Compass is ready to build the next slice.")
    }

    try await withMockFoundationModels(available: false) {
      let narration = await PlanFactoryBriefNarrator.narrate(brief: brief)
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
    midTerm: String = "",
    longTerm: String = ""
  ) -> PlanState {
    PlanState(
      completed: completed,
      immediate: immediate,
      midTerm: midTerm,
      longTerm: longTerm
    )
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
