import Foundation
import Testing

@testable import Compass

struct PlanTransitionValidatorTests {
  @Test func testRejectsClearingMidTermWithoutCompletion() throws {
    let current = makeState(completed: ["done"], midTerm: "- Next queued item")
    let next = makeState(completed: ["done"], midTerm: "   \n")

    assertTransitionRejected(from: current, to: next, contains: "clear a non-empty midTerm queue")
  }

  @Test func testRejectsPlaceholderVerifyCommands() throws {
    let current = makeState()
    let commands = [
      (" true ", "true"),
      ("exit 0", "exit 0"),
      (#"echo "No tests available""#, #"echo "No tests available""#),
      (#"echo "Tests passed""#, #"echo "Tests passed""#),
      (":", ":"),
    ]

    for (command, rejectedVerify) in commands {
      let next = makeState(immediate: PlanNext(plan: "Do work", verify: command))

      let error = try rejectedTransition(from: current, to: next)
      try #require(error.message.contains("placeholder verify command"))
      try #require(error.reason == .placeholderVerify)
      try #require(error.missingLabels == ["Verify command"])
      try #require(error.rejectedVerify == rejectedVerify)
    }
  }

  @Test func testRejectsFailureMaskingVerifyCommands() throws {
    let current = makeState()
    let commands = [
      "swift test || true",
      "swift test; true",
      #"swift test || echo "No tests available""#,
      "swift test || exit 0",
    ]

    for command in commands {
      let next = makeState(immediate: PlanNext(plan: executablePlan("Do work"), verify: command))

      let error = try rejectedTransition(from: current, to: next)
      try #require(error.message.contains("failure-masking verify command"))
      try #require(error.message.contains("Refusing to overwrite state.json"))
      try #require(error.reason == .placeholderVerify)
      try #require(error.missingLabels == ["Verify command"])
      try #require(error.rejectedVerify == command)
    }
  }

  @Test func testRejectsMissingVerifyCommand() throws {
    let current = makeState()
    let next = makeState(immediate: PlanNext(plan: executablePlan("Do work"), verify: " \n "))

    let error = try rejectedTransition(from: current, to: next)
    try #require(error.message.contains("empty verify command"))
    try #require(error.reason == .placeholderVerify)
    try #require(error.missingLabels == ["Verify command"])
    try #require(error.rejectedVerify == nil)
  }

  @Test func testAcceptsNormalImmediateWork() throws {
    let current = makeState(midTerm: "- Build the next slice")
    let next = makeState(
      immediate: PlanNext(plan: executablePlan("Build the next slice"), verify: "swift test"),
      midTerm: "- Build the next slice\n- Polish follow-up"
    )

    try PlanTransitionValidator.validate(from: current, to: next)
  }

  @Test func testAcceptsMidTermRewriteWithoutChangingCompleted() throws {
    let current = makeState(completed: ["First slice"], midTerm: "- Old queue")
    let proposal = PlanProposal(
      immediate: PlanNext(
        plan: executablePlan("Take the rewritten next step"), verify: "swift test"),
      midTerm: "- Rewritten queue",
      longTerm: "Long-term direction"
    )
    let next = current.applying(proposal: proposal)

    try #require(next.completed == current.completed)
    try PlanTransitionValidator.validate(from: current, to: next)
  }

  @Test func testAcceptsNoImmediateWorkState() throws {
    let current = makeState(completed: ["Everything shipped"], midTerm: "", longTerm: "")
    let next = makeState(
      completed: ["Everything shipped"], immediate: nil, midTerm: "", longTerm: "")

    try PlanTransitionValidator.validate(from: current, to: next)
  }

  @Test func testRejectsNoImmediateWorkWhenMidTermRemains() throws {
    let current = makeState(completed: ["done"], midTerm: "- Next queued item", longTerm: "")
    let next = makeState(
      completed: ["done"], immediate: nil, midTerm: "- Next queued item", longTerm: "")

    let error = try rejectedTransition(from: current, to: next)
    try #require(error.message.contains("Immediate Plan"))
    try #require(error.reason == .noImmediateWork)
  }

  @Test func testRejectsWeakImmediateHandoff() throws {
    let current = makeState(midTerm: "- Make Plan easier to follow")
    let next = makeState(
      immediate: PlanNext(
        plan: "Make Plan easier to follow.",
        verify: "swift test --filter PlanWorkflowOverviewTests"
      ),
      midTerm: "- Make Plan easier to follow"
    )

    let error = try rejectedTransition(from: current, to: next)
    try #require(error.message.contains("Missing Acceptance checks"))
    try #require(error.reason == .weakHandoff)
    try #require(error.missingLabels == ["Acceptance checks"])
  }

  @Test func testRejectsCommandOnlyAcceptanceChecks() throws {
    let current = makeState(midTerm: "- Make retry recovery safer")
    let next = makeState(
      immediate: PlanNext(
        plan: """
          ## Outcome
          Make retry recovery safer.

          ## Acceptance checks
          - Verify: swift test --filter RecoveryTests
          """,
        verify: "swift test --filter RecoveryTests"
      ),
      midTerm: "- Make retry recovery safer"
    )

    let error = try rejectedTransition(from: current, to: next)
    try #require(error.message.contains("Acceptance checks cannot be only verify commands"))
    try #require(error.message.contains("`Verify: swift test --filter RecoveryTests`"))
    try #require(error.rejectedAcceptanceChecks == ["Verify: swift test --filter RecoveryTests"])
    try #require(error.reason == .weakHandoff)
    try #require(error.missingLabels == ["Acceptance checks"])
  }

  @Test func testRejectsVagueAcceptanceChecks() throws {
    let current = makeState(midTerm: "- Make Plan handoffs clearer")
    let next = makeState(
      immediate: PlanNext(
        plan: """
          ## Outcome
          Make Plan handoffs clearer.

          ## Acceptance checks
          - The planned behavior is implemented.
          """,
        verify: "swift test --filter PlanDomainTests"
      ),
      midTerm: "- Make Plan handoffs clearer"
    )

    let error = try rejectedTransition(from: current, to: next)
    try #require(error.message.contains("Acceptance checks are too vague"))
    try #require(error.message.contains("`The planned behavior is implemented.`"))
    try #require(error.vagueAcceptanceChecks == ["The planned behavior is implemented."])
    try #require(error.reason == .weakHandoff)
    try #require(error.missingLabels == ["Acceptance checks"])
  }

  @Test func testRejectsNoImmediateWorkWhenLongTermRemains() throws {
    let current = makeState(completed: ["done"], midTerm: "", longTerm: "")
    let next = makeState(
      completed: ["done"],
      immediate: nil,
      midTerm: "",
      longTerm: "Build toward the Explore layer"
    )

    let error = try rejectedTransition(from: current, to: next)
    try #require(error.message.contains("proposed longTerm"))
    try #require(error.reason == .noImmediateWork)
  }

  @Test func testRejectsNoImmediateWorkWhenClearingExistingLongTerm() throws {
    let current = makeState(
      completed: ["done"],
      midTerm: "",
      longTerm: "Build toward the Explore layer"
    )
    let next = makeState(completed: ["done"], immediate: nil, midTerm: "", longTerm: "")

    let error = try rejectedTransition(from: current, to: next)
    try #require(error.message.contains("current longTerm"))
    try #require(error.reason == .noImmediateWork)
  }

  private func makeState(
    completed: [String] = [],
    immediate: PlanNext? = nil,
    midTerm: String = "",
    longTerm: String = "Long-term direction"
  ) -> PlanState {
    PlanState(
      completed: completed,
      immediate: immediate,
      midTerm: midTerm,
      longTerm: longTerm
    )
  }

  @Test func testRejectsTestVerifyWithoutCoverageForSwiftProfile() throws {
    let current = makeState()
    let next = makeState(
      immediate: PlanNext(
        plan: "Add tests",
        verify: "swift test --filter FooTests"
      )
    )

    let error = try rejectedTransition(from: current, to: next, forgeProfile: .swiftSPM)
    try #require(error.message.contains("enable-code-coverage"))
    try #require(error.reason == .coverageRequirement)
    try #require(error.missingLabels == ["Coverage-ready verify command"])
    try #require(error.rejectedVerify == "swift test --filter FooTests")
  }

  private func assertTransitionRejected(
    from current: PlanState,
    to next: PlanState,
    contains expectedText: String,
    forgeProfile: ForgeProfile? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    var threw = false
    var message = ""
    do {
      try PlanTransitionValidator.validate(from: current, to: next, forgeProfile: forgeProfile)
    } catch {
      threw = true
      message =
        (error as? PlanTransitionValidationError)?.message
        ?? (error as? LocalizedError)?.errorDescription
        ?? error.localizedDescription
    }
    #expect(threw, "Expected transition to be rejected but it succeeded")
    #expect(
      message.contains(expectedText),
      "Expected error containing `\(expectedText)`, got `\(message)`."
    )
  }

  private func rejectedTransition(
    from current: PlanState,
    to next: PlanState,
    forgeProfile: ForgeProfile? = nil
  ) throws -> PlanTransitionValidationError {
    do {
      try PlanTransitionValidator.validate(from: current, to: next, forgeProfile: forgeProfile)
    } catch let error as PlanTransitionValidationError {
      return error
    }

    Issue.record("Expected transition to be rejected but it succeeded")
    throw PlanTransitionValidationError(message: "Expected rejection did not occur.")
  }

  private func executablePlan(_ outcome: String) -> String {
    """
    ## Outcome
    \(outcome).

    ## Why it matters
    The owner can understand the next slice before Develop starts.

    ## Acceptance checks
    - The owner-visible result appears in the target surface.
    """
  }
}

@MainActor
struct PlanSubmitResultValidationTests {
  @Test func testRejectsNoImmediateWorkBeforeAgentFinishes() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let workspace = project.makeWorkspace(repoURL: repoURL)
    try workspace.initialize()
    try workspace.writeState(
      PlanState(
        completed: ["Prior slice"],
        immediate: nil,
        midTerm: "",
        longTerm: "Build toward the Explore layer"
      )
    )

    let payload = PlanRunResult(
      state: PlanProposal(
        immediate: nil,
        midTerm: "",
        longTerm: "Build toward the Explore layer"
      )
    )
    let args = try JSONEncoder().encode(payload)
    let validate = project.submitResultValidation(
      for: .plan,
      hostRepoURL: repoURL,
      decode: PlanRunResult.self
    )

    do {
      try validate(args)
      Issue.record("Expected no-immediate plan submit_result to be rejected.")
    } catch let error as PlanTransitionValidationError {
      try #require(error.message.contains("Immediate Plan"))
      try #require(error.message.contains("current longTerm"))
    }
  }

  @Test func testRejectsWeakImmediateHandoffBeforeAgentFinishes() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let workspace = project.makeWorkspace(repoURL: repoURL)
    try workspace.initialize()
    try workspace.writeState(
      PlanState(
        completed: [],
        immediate: nil,
        midTerm: "- Make Plan safer for weak handoffs",
        longTerm: "Build a better factory"
      )
    )

    let payload = PlanRunResult(
      state: PlanProposal(
        immediate: PlanNext(
          plan: "Make Plan safer for weak handoffs.",
          verify: "swift test --filter PlanDomainTests"
        ),
        midTerm: "- Make Plan safer for weak handoffs",
        longTerm: "Build a better factory"
      )
    )
    let args = try JSONEncoder().encode(payload)
    let validate = project.submitResultValidation(
      for: .plan,
      hostRepoURL: repoURL,
      decode: PlanRunResult.self
    )

    do {
      try validate(args)
      Issue.record("Expected weak immediate handoff to be rejected.")
    } catch let error as PlanTransitionValidationError {
      try #require(error.message.contains("not executable enough"))
      try #require(error.message.contains("Acceptance checks"))
    }
  }

  @Test func testRejectsWeakDevelopFeedbackBeforeAgentFinishes() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let workspace = project.makeWorkspace(repoURL: repoURL)
    try workspace.initialize()

    let args = Data(
      """
      {
        "status": "succeeded",
        "summary": "Implemented the slice.",
        "feedback": "done",
        "bypassVerify": null,
        "lessonEdits": []
      }
      """.utf8
    )
    let validate = project.submitResultValidation(
      for: .develop,
      hostRepoURL: repoURL,
      decode: DevelopSummary.self
    )

    do {
      try validate(args)
      Issue.record("Expected weak Develop feedback to be rejected.")
    } catch let error as DevelopFeedbackValidationError {
      try #require(error.reason == .placeholder)
      try #require(error.message.contains("next Plan pass"))
    }
  }

  @Test func testAcceptsConcreteDevelopFeedbackBeforeAgentFinishes() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let workspace = project.makeWorkspace(repoURL: repoURL)
    try workspace.initialize()

    let args = Data(
      """
      {
        "status": "succeeded",
        "summary": "Implemented the slice.",
        "feedback": "Draft readiness now appears in run controls; no follow-up unless copy needs tuning.",
        "bypassVerify": null,
        "lessonEdits": []
      }
      """.utf8
    )
    let validate = project.submitResultValidation(
      for: .develop,
      hostRepoURL: repoURL,
      decode: DevelopSummary.self
    )

    try validate(args)
  }

  @Test func testRejectsUnexplainedVerifyBypassBeforeAgentFinishes() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let workspace = project.makeWorkspace(repoURL: repoURL)
    try workspace.initialize()

    let args = Data(
      """
      {
        "status": "succeeded",
        "summary": "Implemented the slice.",
        "feedback": "Draft readiness now appears in run controls; no follow-up unless copy needs tuning.",
        "bypassVerify": true,
        "lessonEdits": []
      }
      """.utf8
    )
    let validate = project.submitResultValidation(
      for: .develop,
      hostRepoURL: repoURL,
      decode: DevelopSummary.self
    )

    do {
      try validate(args)
      Issue.record("Expected unexplained verify bypass to be rejected.")
    } catch let error as DevelopVerifyBypassValidationError {
      try #require(error.reason == .missingReason)
      try #require(error.message.contains("bypassVerify=true"))
    }
  }

  @Test func testAcceptsConcreteVerifyBypassBeforeAgentFinishes() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let workspace = project.makeWorkspace(repoURL: repoURL)
    try workspace.initialize()

    let args = Data(
      """
      {
        "status": "succeeded",
        "summary": "Implemented the slice; verify command points at a removed test suite.",
        "feedback": "Verify command is wrong because DraftReadinessOldTests no longer exists; next Plan should replace it with DraftRefinementTests.",
        "bypassVerify": true,
        "lessonEdits": []
      }
      """.utf8
    )
    let validate = project.submitResultValidation(
      for: .develop,
      hostRepoURL: repoURL,
      decode: DevelopSummary.self
    )

    try validate(args)
  }

  @Test func testRejectsWeakCriticFeedbackBeforeAgentFinishes() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let args = Data(
      """
      {
        "verdict": "request_changes",
        "summary": "Needs work.",
        "feedback": "fix it"
      }
      """.utf8
    )
    let validate = project.submitResultValidation(
      for: .critic,
      hostRepoURL: repoURL,
      decode: CriticVerdict.self
    )

    do {
      try validate(args)
      Issue.record("Expected weak Critic feedback to be rejected.")
    } catch let error as CriticFeedbackValidationError {
      try #require(error.reason == .placeholder)
      try #require(error.message.contains("next Develop pass"))
    }
  }

  @Test func testAcceptsApproveWithEmptyCriticFeedbackBeforeAgentFinishes() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    let args = Data(
      """
      {
        "verdict": "approve",
        "summary": "No blocking issues found.",
        "feedback": ""
      }
      """.utf8
    )
    let validate = project.submitResultValidation(
      for: .critic,
      hostRepoURL: repoURL,
      decode: CriticVerdict.self
    )

    try validate(args)
  }

  @Test func testDevelopStartRefusesWeakExistingImmediateHandoff() async throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    project.languageProfile = swiftProfile()
    let workspace = project.makeWorkspace(repoURL: repoURL)
    try workspace.initialize()
    try workspace.writeState(
      PlanState(
        completed: [],
        immediate: PlanNext(
          plan: "Make Plan safer for weak handoffs.",
          verify: "swift test --filter PlanDomainTests"
        ),
        midTerm: "",
        longTerm: ""
      )
    )

    await project.runDevelopOnly(
      agentSettings: AgentRuntimeSettings(),
      modelOverride: ""
    )

    try #require(!project.isRunning)
    try #require(project.sessions.isEmpty)
    try #require(project.errorMessage?.contains("stronger handoff") == true)
    try #require(project.errorMessage?.contains("Acceptance checks") == true)
    try #require(
      project.liveLog.contains {
        $0.text.contains("Develop needs a stronger handoff")
          && $0.level == .warning
      }
    )
  }

  @Test func testDevelopStartRefusesCoverageMissingVerify() async throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try initGitRepo(at: repoURL)

    let project = CompassProject(repoURL: repoURL)
    project.languageProfile = goProfile()
    project.forgeProfile = .goModule
    let workspace = project.makeWorkspace(repoURL: repoURL)
    try workspace.initialize()
    try workspace.writeState(
      PlanState(
        completed: [],
        immediate: PlanNext(
          plan: """
            ## Outcome
            Add Go coverage for parser failures.

            ## Acceptance checks
            - Go tests exercise parser failures.
            """,
          verify: "go test ./..."
        ),
        midTerm: "",
        longTerm: ""
      )
    )

    await project.runDevelopOnly(
      agentSettings: AgentRuntimeSettings(),
      modelOverride: ""
    )

    try #require(!project.isRunning)
    try #require(project.sessions.isEmpty)
    try #require(project.errorMessage?.contains("Coverage-ready verify") == true)
    try #require(
      project.liveLog.contains {
        $0.text.contains("Develop needs a stronger handoff")
          && $0.text.contains("Coverage-ready verify")
          && $0.level == .warning
      }
    )
  }

  private func swiftProfile() -> RepositoryLanguageProfile {
    var counts = RepositoryLanguageCounts()
    counts[.swift] = 1
    return RepositoryLanguageProfile(
      counts: counts,
      manifestHints: [.packageSwift],
      primaryLanguage: .swift,
      scannedFileCount: 1,
      scannedDirectoryCount: 1,
      wasTruncated: false
    )
  }

  private func goProfile() -> RepositoryLanguageProfile {
    var counts = RepositoryLanguageCounts()
    counts[.go] = 1
    return RepositoryLanguageProfile(
      counts: counts,
      manifestHints: [.goMod],
      primaryLanguage: .go,
      scannedFileCount: 1,
      scannedDirectoryCount: 1,
      wasTruncated: false
    )
  }
}

struct PlanCompletionRecorderTests {
  @Test func testRecordsSuccessfulSessionPlanLine() throws {
    let state = PlanState.empty
    let sessions = [
      makeSucceededSession(1, plan: "Ship feature X\n\nDetails")
    ]

    let updated = PlanCompletionRecorder.recordingShippedIterations(
      into: state,
      sessions: sessions
    )

    try #require(updated.completed == ["Ship feature X"])
  }

  @Test func testCompletionSummarySkipsGenericOutcomeHeading() throws {
    let session = makeSucceededSession(
      1,
      plan: """
        ## Outcome
        Fix the broken doctest in `tessera-core/src/typeck.rs`.

        ## Why it matters
        The test suite should be green.
        """
    )

    let summary = PlanCompletionRecorder.completionSummary(for: session)

    try #require(summary == "Fix the broken doctest in `tessera-core/src/typeck.rs`.")
  }

  @Test func testCompletionSummaryStripsMarkdownHeadingMarker() throws {
    let session = makeSucceededSession(
      1,
      plan: "## Set up Rust workspace with Cargo.toml and tessera-core crate"
    )

    let summary = PlanCompletionRecorder.completionSummary(for: session)

    try #require(summary == "Set up Rust workspace with Cargo.toml and tessera-core crate")
  }

  @Test func testCompletionSummaryBoundsVerboseOneLinePlan() throws {
    let longPlan = String(
      repeating: "Add missing typechecker coverage for nested branch cases. ", count: 8)
    let session = makeSucceededSession(1, plan: longPlan)

    let summary = PlanCompletionRecorder.completionSummary(for: session)

    try #require(summary.count == 180)
    try #require(summary.hasSuffix("..."))
  }

  @Test func testRepairsStoredGenericCompletionSummary() throws {
    let state = makeState(completed: ["## Outcome"])
    let sessions = [
      makeSucceededSession(
        1,
        plan: """
          ## Outcome
          Fix the broken doctest in `tessera-core/src/typeck.rs`.
          """
      )
    ]

    let updated = PlanCompletionRecorder.recordingShippedIterations(
      into: state,
      sessions: sessions
    )

    try #require(
      updated.completed == ["Fix the broken doctest in `tessera-core/src/typeck.rs`."]
    )
  }

  @Test func testDoesNotDuplicateAlreadyRecordedSessions() throws {
    let state = makeState(completed: ["Ship feature X"])
    let sessions = [makeSucceededSession(1, plan: "Ship feature X")]

    let updated = PlanCompletionRecorder.recordingShippedIterations(
      into: state,
      sessions: sessions
    )

    try #require(updated.completed == state.completed)
  }

  @Test func testIgnoresFailedSessions() throws {
    var failed = SessionRecord.started(1)
    failed.status = .failed
    failed.plan = "Should not record"
    failed.endedAt = Date().timeIntervalSince1970 * 1000

    let updated = PlanCompletionRecorder.recordingShippedIterations(
      into: .empty,
      sessions: [failed]
    )

    try #require(updated.completed == [])
  }

  private func makeState(completed: [String]) -> PlanState {
    PlanState(
      completed: completed,
      immediate: nil,
      midTerm: "",
      longTerm: ""
    )
  }

  private func makeSucceededSession(_ number: Int, plan: String) -> SessionRecord {
    var session = SessionRecord.started(number)
    session.status = .succeeded
    session.plan = plan
    session.endedAt = Date().timeIntervalSince1970 * 1000
    return session
  }
}

struct PlanHistoryPageTests {
  @Test func testReturnsNewestEntriesFirstWithPaginationHint() throws {
    let page = PlanHistoryPage.read(
      entries: ["First", "Second", "Third"],
      offset: 1,
      limit: 1
    )

    try #require(page.totalCount == 3)
    try #require(page.entries.map(\.iteration) == [2])
    try #require(page.entries.map(\.summary) == ["Second"])
    try #require(page.formatted().contains("offset 1 from newest"))
    try #require(page.formatted().contains("more: call plan_history with offset 2"))
  }

  @Test func testFormattedHistoryBoundsVerboseEntries() throws {
    let longEntry = String(
      repeating: "Add detailed coverage for the remaining command branches. ", count: 8)
    let page = PlanHistoryPage.read(entries: [longEntry], limit: 1)

    let formatted = page.formatted()

    try #require(formatted.contains("#1: "))
    try #require(formatted.count < longEntry.count)
  }

  @Test func testIterationNumbersWithOffsetAndFourPlusEntries() throws {
    // With 4 entries ["A","B","C","D"], reversed = [D,C,B,A] with indices [0,1,2,3]
    // offset=2 skips D,C → slice=[B,A] with original entries at positions 1,0
    // Correct iterations: B is entry[1] → count(4) - offset(2) - sliceIndex(0) = 2, A is entry[0] → 4-2-1=1
    // So we expect [2, 1] which is exactly what the buggy formula (index+1) gives here.
    // Use offset=2 limit=2 to get 4 entries total: offset=2 skip D,C, limit=2 take B,A → iterations [2,1]
    // But after fix: entries.count(4) - clampedOffset(2) - sliceIndex → 4-2-0=2, 4-2-1=1 → [2,1] — same by coincidence.
    // Test offset=2 limit=2 with 5 entries to expose the bug: ["A","B","C","D","E"]
    // reversed = [E,D,C,B,A] indices [0,1,2,3,4]; offset=2 drops E,D → slice=[C,B,A]
    // prefix(2) → [C,B]; sliceIndex 0→C(iteration=5-2-0=3), sliceIndex 1→B(iteration=5-2-1=2)
    // Buggy formula gives [1,2] (index+1 on [C,B] whose original indices are 2,1 → wrong)
    let page = PlanHistoryPage.read(
      entries: ["A", "B", "C", "D", "E"],
      offset: 2,
      limit: 2
    )

    // E=5, D=4, C=3, B=2, A=1. offset=2 skips E,D → C,B remain → iterations [3,2]
    try #require(page.totalCount == 5)
    try #require(page.entries.map(\.iteration) == [3, 2])
    try #require(page.entries.map(\.summary) == ["C", "B"])
  }
}

struct AgentPlanHistoryToolTests {
  @Test func testReturnsPaginatedHistoryFromContext() async throws {
    let tool = AgentPlanHistoryTool()
    let args = try JSONSerialization.data(withJSONObject: ["offset": 0, "limit": 2])
    let context = AgentToolContext(
      workingDirectory: FileManager.default.temporaryDirectory,
      planHistoryEntries: ["First", "Second", "Third"]
    )

    let result = try await tool.invoke(arguments: args, context: context)

    try #require(!result.isError)
    try #require(result.content.contains("#3: Third"))
    try #require(result.content.contains("#2: Second"))
    try #require(!result.content.contains("#1: First"))
  }
}

struct PlanNextDecoderTests {
  @Test func decoderTrimsPlanAndVerifyAndKeepsPositiveTimeout() throws {
    let json = """
      {
        "plan": "  Build the slice\\n",
        "verify": "\\n swift test  ",
        "verifyTimeoutMs": 120000,
        "estimatedDifficulty": "medium"
      }
      """

    let next = try decodePlanNext(json)

    try #require(next.plan == "Build the slice")
    try #require(next.verify == "swift test")
    try #require(next.verifyTimeoutMs == 120000)
    try #require(next.estimatedDifficulty == .medium)
    #expect(!next.requiresHostXcode)
  }

  @Test func decoderDefaultsMissingRequiresHostXcodeToFalseAndAcceptsTrue() throws {
    let defaulted = try decodePlanNext(
      """
      {
        "plan": "Build",
        "verify": "swift build"
      }
      """)
    let required = try decodePlanNext(
      """
      {
        "plan": "Build in Xcode",
        "verify": "xcodebuild -scheme App build",
        "requiresHostXcode": true
      }
      """)

    #expect(!defaulted.requiresHostXcode)
    #expect(required.requiresHostXcode)
  }

  @Test func decoderAcceptsStringMetadataFromLessCapableModels() throws {
    let next = try decodePlanNext(
      """
      {
        "plan": "Build",
        "verify": "xcodebuild -scheme App test",
        "verifyTimeoutMs": "600000",
        "estimatedDifficulty": " Medium ",
        "requiresHostXcode": "true"
      }
      """)

    try #require(next.verifyTimeoutMs == 600000)
    try #require(next.estimatedDifficulty == .medium)
    try #require(next.requiresHostXcode)
  }

  @Test func decoderAcceptsCommonHandoffAliasesFromLessCapableModels() throws {
    let next = try decodePlanNext(
      """
      {
        "implementationPlan": "  Build the safer handoff\\n",
        "verifyCommand": "\\n swift test --filter PlanDomainTests  ",
        "requiresHostXcode": "no"
      }
      """)

    try #require(next.plan == "Build the safer handoff")
    try #require(next.verify == "swift test --filter PlanDomainTests")
    try #require(!next.requiresHostXcode)
  }

  @Test func decoderPrefersCanonicalPlanAndVerifyOverAliases() throws {
    let next = try decodePlanNext(
      """
      {
        "plan": "Use canonical plan",
        "implementationPlan": "Ignore alias plan",
        "verify": "swift test",
        "verifyCommand": "echo wrong"
      }
      """)

    try #require(next.plan == "Use canonical plan")
    try #require(next.verify == "swift test")
  }

  @Test func decoderIgnoresUnknownOptionalMetadataWithoutRejectingPlan() throws {
    let next = try decodePlanNext(
      """
      {
        "plan": "Build",
        "verify": "swift build",
        "verifyTimeoutMs": "later",
        "estimatedDifficulty": "moderate",
        "requiresHostXcode": "maybe"
      }
      """)

    try #require(next.verifyTimeoutMs == nil)
    try #require(next.estimatedDifficulty == nil)
    try #require(!next.requiresHostXcode)
  }

  @Test func decoderDropsNonPositiveTimeouts() throws {
    let zeroTimeout = try decodePlanNext(
      """
      {
        "plan": "Build",
        "verify": "swift test",
        "verifyTimeoutMs": 0
      }
      """)
    let negativeTimeout = try decodePlanNext(
      """
      {
        "plan": "Build",
        "verify": "swift test",
        "verifyTimeoutMs": -1
      }
      """)

    try #require(zeroTimeout.verifyTimeoutMs == nil)
    try #require(negativeTimeout.verifyTimeoutMs == nil)
  }

  private func decodePlanNext(_ json: String) throws -> PlanNext {
    let data = try #require(json.data(using: .utf8))
    return try JSONDecoder().decode(PlanNext.self, from: data)
  }
}

struct DevelopSummaryDecoderTests {
  @Test func decoderAcceptsStatusBooleanAndLessonEditAliasesFromLessCapableModels() throws {
    let data = Data(
      """
      {
        "status": "completed",
        "summary": "Implemented the recovery copy.",
        "feedback": "Run controls now name the exact handoff field that needs repair.",
        "bypassVerify": "false",
        "lessonEdits": [
          {
            "find": "old lesson",
            "replace": "new lesson",
            "replaceAll": "true"
          }
        ]
      }
      """.utf8
    )

    let summary = try JSONDecoder().decode(DevelopSummary.self, from: data)

    try #require(summary.status == .succeeded)
    try #require(summary.bypassVerify == false)
    try #require(summary.lessonEdits.count == 1)
    try #require(summary.lessonEdits[0].replaceAll == true)
  }
}

struct RepositoryLanguageProfileServiceTests {
  @Test func testDetectsSwiftPackageWhileIgnoringBuildDirectories() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    try write(
      "let package = Package(name: \"Fixture\")\n", to: repoURL.appending(path: "Package.swift"))
    try createDirectory(repoURL.appending(path: "Sources/App", directoryHint: .isDirectory))
    try write("print(\"hello\")\n", to: repoURL.appending(path: "Sources/App/main.swift"))
    try createDirectory(repoURL.appending(path: ".build/generated", directoryHint: .isDirectory))
    try write(
      "console.log('ignored')\n", to: repoURL.appending(path: ".build/generated/ignored.ts"))
    try createDirectory(repoURL.appending(path: "build/generated", directoryHint: .isDirectory))
    try write("print('ignored')\n", to: repoURL.appending(path: "build/generated/ignored.py"))

    let profile = RepositoryLanguageProfileService.scan(repoURL: repoURL)

    try #require(profile.primaryLanguage == .swift)
    try #require(profile.manifestHints == [.packageSwift])
    try #require(profile.counts.swift == 2)
    try #require(profile.counts.typeScriptJavaScript == 0)
    try #require(profile.counts.other == 0)
    try #require(profile.scannedFileCount == 2)
    try #require(!profile.wasTruncated)
  }

  @Test func testDetectsGoModuleWhileIgnoringBuildDirectories() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    try write("module example.com/app\n\ngo 1.22\n", to: repoURL.appending(path: "go.mod"))
    try write(
      "package main\n\nfunc main() {}\n",
      to: repoURL.appending(path: "main.go"))

    let profile = RepositoryLanguageProfileService.scan(repoURL: repoURL)

    try #require(profile.primaryLanguage == .go)
    try #require(profile.manifestHints == [.goMod])
    try #require(profile.counts.go == 1)
    try #require(profile.scannedFileCount == 2)
    try #require(!profile.wasTruncated)
    try #require(profile.hudSummary?.contains("Go forge profile") == true)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CompassTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try createDirectory(directory)
    return directory
  }

  private func createDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func write(_ contents: String, to url: URL) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }
}
