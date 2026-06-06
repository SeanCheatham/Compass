import Foundation
import Testing

@testable import Compass

private func testPlanProposal(
  immediate: PlanNext?,
  candidates: String,
  strategicContext: String,
  openQuestions: [PlanQuestion] = []
) -> PlanProposal {
  PlanProposal(
    immediate: immediate,
    candidates: testPlanCandidates(candidates),
    strategicContext: testStrategicContext(strategicContext),
    openQuestions: openQuestions
  )
}

struct PlanTransitionValidatorTests {
  @Test func testRejectsClearingCandidatesWithoutCompletion() throws {
    let current = makeState(completed: ["done"], candidates: "- Next queued item")
    let next = makeState(completed: ["done"], candidates: "   \n")

    assertTransitionRejected(from: current, to: next, contains: "clear all actionable candidates")
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
    let current = makeState(candidates: "- Build the next slice")
    let next = makeState(
      immediate: PlanNext(plan: executablePlan("Build the next slice"), verify: "swift test"),
      candidates: "- Build the next slice\n- Polish follow-up"
    )

    try PlanTransitionValidator.validate(from: current, to: next)
  }

  @Test func testRejectsProductTournamentImmediateThatMentionsMultipleExperiments() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users cannot compare product bets.",
      now: Date(timeIntervalSince1970: 1)
    )
    let first = config.experiments[0]
    let second = config.experiments[1]
    let current = makeState(candidates: "- Improve active experiments")
    let next = makeState(
      immediate: PlanNext(
        plan: executablePlan("Improve \(first.id) and \(second.id) in one slice"),
        verify: "swift test --filter ProductTournamentLoopTests"
      ),
      candidates: "- Improve active experiments"
    )

    let error = try rejectedTransition(
      from: current,
      to: next,
      productTournamentConfig: config
    )

    try #require(error.reason == .multiExperimentImmediate)
    try #require(error.message.contains(first.id))
    try #require(error.message.contains(second.id))
    try #require(error.missingLabels == ["Single experiment scope"])
  }

  @Test func testAcceptsSharedInfrastructureImmediateAcrossExperiments() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users cannot compare product bets.",
      now: Date(timeIntervalSince1970: 1)
    )
    let first = config.experiments[0]
    let second = config.experiments[1]
    let current = makeState(candidates: "- Improve active experiments")
    let next = makeState(
      immediate: PlanNext(
        plan: executablePlan(
          "Add shared experiment infrastructure for \(first.id) and \(second.id)"
        ),
        verify: "swift test --filter ProductTournamentLoopTests"
      ),
      candidates: "- Improve active experiments"
    )

    try PlanTransitionValidator.validate(
      from: current,
      to: next,
      productTournamentConfig: config
    )
  }

  @Test func testAcceptsCandidateRewriteWithoutChangingCompleted() throws {
    let current = makeState(completed: ["First slice"], candidates: "- Old queue")
    let proposal = testPlanProposal(
      immediate: PlanNext(
        plan: executablePlan("Take the rewritten next step"), verify: "swift test"),
      candidates: "- Rewritten queue",
      strategicContext: "Long-term direction"
    )
    let next = current.applying(proposal: proposal)

    try #require(next.completed == current.completed)
    try PlanTransitionValidator.validate(from: current, to: next)
  }

  @Test func testAcceptsNoImmediateWorkState() throws {
    let current = makeState(completed: ["Everything shipped"], candidates: "", strategicContext: "")
    let next = makeState(
      completed: ["Everything shipped"], immediate: nil, candidates: "", strategicContext: "")

    try PlanTransitionValidator.validate(from: current, to: next)
  }

  @Test func testRejectsNoImmediateWorkWhenCandidatesRemain() throws {
    let current = makeState(completed: ["done"], candidates: "- Next queued item", strategicContext: "")
    let next = makeState(
      completed: ["done"], immediate: nil, candidates: "- Next queued item", strategicContext: "")

    let error = try rejectedTransition(from: current, to: next)
    try #require(error.message.contains("Immediate Plan"))
    try #require(error.reason == .noImmediateWork)
  }

  @Test func testRejectsWeakImmediateHandoff() throws {
    let current = makeState(candidates: "- Make Plan easier to follow")
    let next = makeState(
      immediate: PlanNext(
        plan: "Make Plan easier to follow.",
        verify: "swift test --filter PlanWorkflowOverviewTests"
      ),
      candidates: "- Make Plan easier to follow"
    )

    let error = try rejectedTransition(from: current, to: next)
    try #require(error.message.contains("Missing Acceptance checks"))
    try #require(error.reason == .weakHandoff)
    try #require(error.missingLabels == ["Acceptance checks"])
  }

  @Test func testRejectsCommandOnlyAcceptanceChecks() throws {
    let current = makeState(candidates: "- Make retry recovery safer")
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
      candidates: "- Make retry recovery safer"
    )

    let error = try rejectedTransition(from: current, to: next)
    try #require(error.message.contains("Acceptance checks cannot be only verify commands"))
    try #require(error.message.contains("`Verify: swift test --filter RecoveryTests`"))
    try #require(error.rejectedAcceptanceChecks == ["Verify: swift test --filter RecoveryTests"])
    try #require(error.reason == .weakHandoff)
    try #require(error.missingLabels == ["Acceptance checks"])
  }

  @Test func testRejectsVagueAcceptanceChecks() throws {
    let current = makeState(candidates: "- Make Plan handoffs clearer")
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
      candidates: "- Make Plan handoffs clearer"
    )

    let error = try rejectedTransition(from: current, to: next)
    try #require(error.message.contains("Acceptance checks are too vague"))
    try #require(error.message.contains("`The planned behavior is implemented.`"))
    try #require(error.vagueAcceptanceChecks == ["The planned behavior is implemented."])
    try #require(error.reason == .weakHandoff)
    try #require(error.missingLabels == ["Acceptance checks"])
  }

  @Test func testAcceptsNoImmediateWorkWhenOnlyStrategicContextRemains() throws {
    let current = makeState(completed: ["done"], candidates: "", strategicContext: "")
    let next = makeState(
      completed: ["done"],
      immediate: nil,
      candidates: "",
      strategicContext: "Build toward the Explore layer"
    )

    try PlanTransitionValidator.validate(from: current, to: next)
  }

  @Test func testAcceptsNoImmediateWorkWhenClearingExistingStrategicContext() throws {
    let current = makeState(
      completed: ["done"],
      candidates: "",
      strategicContext: "Build toward the Explore layer"
    )
    let next = makeState(completed: ["done"], immediate: nil, candidates: "", strategicContext: "")

    try PlanTransitionValidator.validate(from: current, to: next)
  }

  private func makeState(
    completed: [String] = [],
    immediate: PlanNext? = nil,
    candidates: String = "",
    strategicContext: String = "Long-term direction"
  ) -> PlanState {
    PlanState(
      completed: completed,
      immediate: immediate,
      candidates: testPlanCandidates(candidates),
      strategicContext: testStrategicContext(strategicContext)
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
    forgeProfile: ForgeProfile? = nil,
    productTournamentConfig: ProductTournamentConfig? = nil
  ) throws -> PlanTransitionValidationError {
    do {
      try PlanTransitionValidator.validate(
        from: current,
        to: next,
        forgeProfile: forgeProfile,
        productTournamentConfig: productTournamentConfig
      )
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
        candidates: testPlanCandidates("- Build toward the Explore layer"),
        strategicContext: testStrategicContext("Build toward the Explore layer")
      )
    )

    let payload = PlanRunResult(
      state: testPlanProposal(
        immediate: nil,
        candidates: "- Build toward the Explore layer",
        strategicContext: "Build toward the Explore layer"
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
      try #require(error.message.contains("current candidates"))
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
        candidates: testPlanCandidates("- Make Plan safer for weak handoffs"),
        strategicContext: testStrategicContext("Build a better factory")
      )
    )

    let payload = PlanRunResult(
      state: testPlanProposal(
        immediate: PlanNext(
          plan: "Make Plan safer for weak handoffs.",
          verify: "swift test --filter PlanDomainTests"
        ),
        candidates: "- Make Plan safer for weak handoffs",
        strategicContext: "Build a better factory"
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
        candidates: [],
        strategicContext: .empty
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
    project.languageProfile = rustProfile()
    project.forgeProfile = .rustCargo
    let workspace = project.makeWorkspace(repoURL: repoURL)
    try workspace.initialize()
    try workspace.writeState(
      PlanState(
        completed: [],
        immediate: PlanNext(
          plan: """
            ## Outcome
            Add Rust coverage for parser failures.

            ## Acceptance checks
            - Rust tests exercise parser failures.
          """,
          verify: "cargo test"
        ),
        candidates: [],
        strategicContext: .empty
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

  private func rustProfile() -> RepositoryLanguageProfile {
    var counts = RepositoryLanguageCounts()
    counts[.rust] = 1
    return RepositoryLanguageProfile(
      counts: counts,
      manifestHints: [.cargoToml],
      primaryLanguage: .rust,
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
      candidates: [],
      strategicContext: .empty
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

  @Test func testAcceptsCommonAliasArguments() async throws {
    let tool = AgentPlanHistoryTool()
    let context = AgentToolContext(
      workingDirectory: FileManager.default.temporaryDirectory,
      planHistoryEntries: ["First", "Second", "Third", "Fourth"]
    )

    let result = try await tool.invoke(
      arguments: Data(#"{"skip":"1","max_results":2}"#.utf8),
      context: context
    )

    try #require(!result.isError)
    try #require(result.content.contains("#3: Third"))
    try #require(result.content.contains("#2: Second"))
    try #require(!result.content.contains("#4: Fourth"))
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
        "verify_timeout_ms": "600000",
        "estimated_difficulty": " Medium ",
        "requires_host_xcode": "true"
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
        "implementation_plan": "  Build the safer handoff\\n",
        "verify_command": "\\n swift test --filter PlanDomainTests  ",
        "requires_host_xcode": "no"
      }
      """)

    try #require(next.plan == "Build the safer handoff")
    try #require(next.verify == "swift test --filter PlanDomainTests")
    try #require(!next.requiresHostXcode)
  }

  @Test func decoderAcceptsCommonVerifyCommandAliasesFromLessCapableModels() throws {
    let cases = [
      ("test_command", "swift test --filter PlanNextDecoderTests"),
      ("check_command", "./scripts/test-local.sh"),
      ("validation_command", "npm test"),
      ("validation_cmd", "xcodebuild test -scheme Compass"),
      ("command", "swift build"),
    ]

    for (key, command) in cases {
      let next = try decodePlanNext(
        """
        {
          "plan": "Build",
          "\(key)": "  \(command)\\n"
        }
        """)

      try #require(next.verify == command)
    }
  }

  @Test func decoderAcceptsPlanAndVerifyArraysFromLessCapableModels() throws {
    let next = try decodePlanNext(
      """
      {
        "plan": [
          "## Outcome",
          "Make PlanNext decoding tolerate array-shaped handoffs.",
          "",
          "## Acceptance checks",
          "- Array plan text decodes into newline-delimited Markdown.",
          "- Single-item verify arrays decode to the intended shell command."
        ],
        "verify": [
          "swift test --filter PlanNextDecoderTests"
        ]
      }
      """)

    try #require(
      next.plan
        == """
        ## Outcome
        Make PlanNext decoding tolerate array-shaped handoffs.
        ## Acceptance checks
        - Array plan text decodes into newline-delimited Markdown.
        - Single-item verify arrays decode to the intended shell command.
        """
    )
    try #require(next.verify == "swift test --filter PlanNextDecoderTests")
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
  @Test func decoderAcceptsKeyStatusBooleanAndLessonEditAliasesFromLessCapableModels() throws {
    let data = Data(
      """
      {
        "completion_status": "completed",
        "details": "Implemented the recovery copy.",
        "next_plan_handoff": "Run controls now name the exact handoff field that needs repair.",
        "bypass_verify": "false",
        "lesson_edits": {
          "old_string": "old lesson",
          "new_string": "new lesson",
          "global": "true"
        }
      }
      """.utf8
    )

    let summary = try JSONDecoder().decode(DevelopSummary.self, from: data)

    try #require(summary.status == .succeeded)
    try #require(summary.summary == "Implemented the recovery copy.")
    try #require(
      summary.feedback == "Run controls now name the exact handoff field that needs repair."
    )
    try #require(summary.bypassVerify == false)
    try #require(summary.lessonEdits.count == 1)
    try #require(summary.lessonEdits[0].find == "old lesson")
    try #require(summary.lessonEdits[0].replace == "new lesson")
    try #require(summary.lessonEdits[0].replaceAll == true)
  }

  @Test func decoderAcceptsSummaryAndFeedbackArraysForFreeformText() throws {
    let data = Data(
      """
      {
        "status": "succeeded",
        "summary": [
          "Implemented the recovery copy.",
          "Covered the missing-submit retry path."
        ],
        "feedback": [
          "Missing submit_result turns now retry with a phase-shaped packet.",
          "No follow-up unless live copy needs tuning."
        ],
        "bypassVerify": false,
        "lessonEdits": []
      }
      """.utf8
    )

    let summary = try JSONDecoder().decode(DevelopSummary.self, from: data)

    try #require(
      summary.summary
        == "Implemented the recovery copy.\nCovered the missing-submit retry path."
    )
    try #require(
      summary.feedback
        == "Missing submit_result turns now retry with a phase-shaped packet.\nNo follow-up unless live copy needs tuning."
    )
  }
}

struct CriticVerdictDecoderTests {
  @Test func decoderAcceptsSummaryAndFeedbackArraysForFreeformText() throws {
    let data = Data(
      """
      {
        "decision": "changes_requested",
        "summary": [
          "One blocking issue remains.",
          "The fix is localized."
        ],
        "feedback": [
          "- Retry copy does not mention the failed field.",
          "- Add the field name to the repair prompt."
        ]
      }
      """.utf8
    )

    let verdict = try JSONDecoder().decode(CriticVerdict.self, from: data)

    try #require(verdict.verdict == .requestChanges)
    try #require(verdict.summary == "One blocking issue remains.\nThe fix is localized.")
    try #require(
      verdict.feedback
        == "- Retry copy does not mention the failed field.\n- Add the field name to the repair prompt."
    )
  }

  @Test func decoderAcceptsReviewAliasesFromLessCapableModels() throws {
    let data = Data(
      """
      {
        "result": "needs_work",
        "rationale": [
          "One blocking issue remains.",
          "The repair is local to run-control copy."
        ],
        "requested_changes": [
          "- Develop retry copy does not name the rejected field.",
          "- Add a focused test for the rejected-field message."
        ]
      }
      """.utf8
    )

    let verdict = try JSONDecoder().decode(CriticVerdict.self, from: data)

    try #require(verdict.verdict == .requestChanges)
    try #require(
      verdict.summary
        == "One blocking issue remains.\nThe repair is local to run-control copy."
    )
    try #require(
      verdict.feedback
        == "- Develop retry copy does not name the rejected field.\n- Add a focused test for the rejected-field message."
    )
  }
}

struct PlanningEnvelopeDecoderTests {
  @Test func planRunResultDecoderAcceptsCanonicalTypedPlanningState() throws {
    let data = Data(
      """
      {
        "state": {
          "immediate": {
            "plan": "Build the envelope decoder tolerance.",
            "verify": "swift test --filter PlanningEnvelopeDecoderTests",
            "selectedBecause": "It is the smallest decoder-hardening slice.",
            "source": "candidate",
            "candidateID": "decoder-hardening"
          },
          "candidates": [
            {
              "id": "payload-hardening",
              "title": "Continue payload hardening",
              "outcome": "Planning payloads stay strict and readable.",
              "category": "reliability",
              "origin": "plan",
              "priority": "medium",
              "status": "available",
              "why": "It keeps submit-result failures actionable.",
              "evidence": [],
              "blockedBy": []
            }
          ],
          "strategicContext": {
            "thesis": "Make Compass forgiving at the edges and strict at the core.",
            "principles": [],
            "constraints": [],
            "nonGoals": [],
            "risks": []
          },
          "openQuestions": []
        },
        "lesson_edits": {
          "find": "old planning lesson",
          "replace": "new planning lesson",
          "replace_all": "false"
        }
      }
      """.utf8
    )

    let result = try JSONDecoder().decode(PlanRunResult.self, from: data)

    try #require(result.state.immediate?.plan == "Build the envelope decoder tolerance.")
    try #require(
      result.state.immediate?.verify == "swift test --filter PlanningEnvelopeDecoderTests")
    try #require(result.state.candidates.map(\.title) == ["Continue payload hardening"])
    try #require(
      result.state.strategicContext.thesis
        == "Make Compass forgiving at the edges and strict at the core.")
    try #require(result.lessonEdits.count == 1)
    try #require(result.lessonEdits[0].replaceAll == false)
  }

  @Test func planRunResultDecoderAcceptsScalarCandidateListFields() throws {
    let data = Data(
      """
      {
        "state": {
          "immediate": null,
          "candidates": [
            {
              "id": "array-recovery",
              "title": "Recover scalar array fields",
              "outcome": "Candidate metadata survives common scalar-list mistakes.",
              "category": "reliability",
              "origin": "plan",
              "priority": "high",
              "status": "available",
              "why": "It avoids wasting a retry on advisory candidate metadata.",
              "evidence": "Recent submit_result rejection named state.candidates.Index 0.evidence.",
              "blockedBy": "Follow-up verify is not ready yet.",
              "risk": null
            }
          ],
          "strategicContext": {
            "thesis": "Make schema recovery boring.",
            "principles": [],
            "constraints": [],
            "nonGoals": [],
            "risks": []
          },
          "openQuestions": []
        },
        "lessonEdits": []
      }
      """.utf8
    )

    let result = try JSONDecoder().decode(PlanRunResult.self, from: data)

    try #require(
      result.state.candidates[0].evidence
        == ["Recent submit_result rejection named state.candidates.Index 0.evidence."]
    )
    try #require(result.state.candidates[0].blockedBy == ["Follow-up verify is not ready yet."])
    try #require(result.lessonEdits.isEmpty)
  }

  @Test func planRunResultDecoderAcceptsScalarStrategicContextLists() throws {
    let data = Data(
      """
      {
        "state": {
          "immediate": null,
          "candidates": [],
          "strategicContext": {
            "thesis": ["Keep recovery understandable.", "Keep the loop moving."],
            "principles": "Make model mistakes recoverable instead of mysterious.",
            "constraints": {
              "route": "On-device models may emit scalar fields during repair."
            },
            "non_goals": "Do not loosen executable immediate work.",
            "risks": [
              {
                "field": "state.strategicContext.principles",
                "issue": "Sometimes emitted as a string."
              },
              true
            ]
          },
          "openQuestions": []
        },
        "lessonEdits": []
      }
      """.utf8
    )

    let result = try JSONDecoder().decode(PlanRunResult.self, from: data)

    try #require(
      result.state.strategicContext.thesis
        == "Keep recovery understandable.\nKeep the loop moving.")
    try #require(
      result.state.strategicContext.principles
        == ["Make model mistakes recoverable instead of mysterious."])
    try #require(
      result.state.strategicContext.constraints
        == ["route: On-device models may emit scalar fields during repair."])
    try #require(
      result.state.strategicContext.nonGoals
        == ["Do not loosen executable immediate work."])
    try #require(
      result.state.strategicContext.risks
        == [
          "field: state.strategicContext.principles; issue: Sometimes emitted as a string.",
          "true",
        ])
  }

  @Test func planRunResultDecoderAcceptsStringStrategicContextAsThesis() throws {
    let data = Data(
      """
      {
        "state": {
          "immediate": null,
          "candidates": [],
          "strategicContext": "Keep Compass forgiving at the edges and strict at the core.",
          "openQuestions": []
        },
        "lessonEdits": []
      }
      """.utf8
    )

    let result = try JSONDecoder().decode(PlanRunResult.self, from: data)

    try #require(
      result.state.strategicContext.thesis
        == "Keep Compass forgiving at the edges and strict at the core.")
    try #require(result.state.strategicContext.principles.isEmpty)
  }

  @Test func planRunResultDecoderAcceptsStructuredCandidateEvidence() throws {
    let data = Data(
      """
      {
        "state": {
          "immediate": null,
          "candidates": [
            {
              "id": "structured-evidence",
              "title": "Recover structured evidence",
              "outcome": "Candidate metadata survives object-shaped evidence.",
              "category": "reliability",
              "origin": "plan",
              "priority": "high",
              "status": "available",
              "why": "On-device tool repair sometimes emits evidence as structured notes.",
              "evidence": [
                {
                  "file": "tessera-cli/src/commands.rs",
                  "note": "grep showed the command module"
                },
                79,
                true
              ],
              "blockedBy": {
                "reason": "Need a smaller Develop finish"
              },
              "risk": null
            }
          ],
          "strategicContext": {
            "thesis": "Make candidate metadata forgiving.",
            "principles": [],
            "constraints": [],
            "nonGoals": [],
            "risks": []
          },
          "openQuestions": []
        },
        "lessonEdits": []
      }
      """.utf8
    )

    let result = try JSONDecoder().decode(PlanRunResult.self, from: data)

    try #require(
      result.state.candidates[0].evidence
        == [
          "file: tessera-cli/src/commands.rs; note: grep showed the command module",
          "79",
          "true",
        ])
    try #require(result.state.candidates[0].blockedBy == ["reason: Need a smaller Develop finish"])
  }

  @Test func planRunResultDecoderAcceptsLessonEditsWrapperObject() throws {
    let data = Data(
      """
      {
        "state": {
          "immediate": null,
          "candidates": [],
          "strategicContext": {
            "thesis": "Keep lesson edit recovery narrow.",
            "principles": [],
            "constraints": [],
            "nonGoals": [],
            "risks": []
          },
          "openQuestions": []
        },
        "lessonEdits": {
          "edits": [
            {
              "find": "old lesson",
              "replace": "new lesson",
              "replaceAll": false
            }
          ]
        }
      }
      """.utf8
    )

    let result = try JSONDecoder().decode(PlanRunResult.self, from: data)

    try #require(result.lessonEdits.count == 1)
    try #require(result.lessonEdits[0].find == "old lesson")
    try #require(result.lessonEdits[0].replace == "new lesson")
  }

  @Test func planRunResultDecoderAcceptsOmittedImmediateAsNil() throws {
    let data = Data(
      """
      {
        "state": {
          "candidates": [],
          "strategicContext": {
            "thesis": "Nullable immediate may be omitted by older on-device schemas.",
            "principles": [],
            "constraints": [],
            "nonGoals": [],
            "risks": []
          },
          "openQuestions": []
        },
        "lessonEdits": []
      }
      """.utf8
    )

    let result = try JSONDecoder().decode(PlanRunResult.self, from: data)

    try #require(result.state.immediate == nil)
  }

  @Test func reflectSummaryDecoderAcceptsCanonicalTypedPlanningState() throws {
    let data = Data(
      """
      {
        "state": {
          "immediate": null,
          "candidates": [],
          "strategicContext": {
            "thesis": "Keep the factory understandable to non-engineers.",
            "principles": [],
            "constraints": [],
            "nonGoals": [],
            "risks": []
          },
          "openQuestions": []
        },
        "reflection": [
          "The strategy still points at non-engineer UX.",
          "No immediate planning update is needed."
        ],
        "lesson_edits": "none"
      }
      """.utf8
    )

    let summary = try JSONDecoder().decode(ReflectSummary.self, from: data)

    try #require(summary.state?.immediate == nil)
    try #require(summary.state?.candidates == [])
    try #require(
      summary.state?.strategicContext.thesis
        == "Keep the factory understandable to non-engineers.")
    try #require(
      summary.summary
        == "The strategy still points at non-engineer UX.\nNo immediate planning update is needed."
    )
    try #require(summary.lessonEdits.isEmpty)
  }

  @Test func reflectSummaryDecoderAcceptsProductDecisionUpdates() throws {
    let data = Data(
      """
      {
        "state": null,
        "summary": "Evidence supports narrowing the prototype.",
        "lessonEdits": [],
        "productDecisionUpdates": [
          {
            "experimentID": "experiment-command-board",
            "decision": "narrow",
            "summary": "Repeated objections point at import setup, not the pain.",
            "evidenceRunIDs": ["run-one", "run-two"],
            "decidedBy": "Reflect"
          }
        ]
      }
      """.utf8
    )

    let summary = try JSONDecoder().decode(ReflectSummary.self, from: data)

    try #require(summary.productDecisionUpdates.count == 1)
    try #require(summary.productDecisionUpdates[0].experimentID == "experiment-command-board")
    try #require(summary.productDecisionUpdates[0].decision == .narrow)
    try #require(summary.productDecisionUpdates[0].evidenceRunIDs == ["run-one", "run-two"])
  }

  @Test func planProposalDecoderAcceptsCanonicalTypedState() throws {
    let data = Data(
      """
      {
        "immediate": null,
        "candidates": [
          {
            "id": "weak-model-recovery",
            "title": "Harden weak-model recovery",
            "outcome": "Recovery copy names the repairable field.",
            "category": "reliability",
            "origin": "reflect",
            "priority": "high",
            "status": "available",
            "why": "It makes model mistakes recoverable instead of mysterious.",
            "evidence": ["Recent submit_result rejection was confusing."],
            "blockedBy": []
          }
        ],
        "strategicContext": {
          "thesis": "Keep the factory understandable to non-engineers.",
          "principles": ["Make model mistakes recoverable instead of mysterious."],
          "constraints": [],
          "nonGoals": [],
          "risks": []
        },
        "openQuestions": []
      }
      """.utf8
    )

    let proposal = try JSONDecoder().decode(PlanProposal.self, from: data)

    try #require(proposal.immediate == nil)
    try #require(proposal.candidates.map(\.title) == ["Harden weak-model recovery"])
    try #require(proposal.strategicContext.thesis == "Keep the factory understandable to non-engineers.")
    try #require(
      proposal.strategicContext.principles
        == ["Make model mistakes recoverable instead of mysterious."])
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

  @Test func testTreatsGoModuleAsUnsupportedOtherFiles() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    try write("module example.com/app\n\ngo 1.22\n", to: repoURL.appending(path: "go.mod"))
    try write(
      "package main\n\nfunc main() {}\n",
      to: repoURL.appending(path: "main.go"))

    let profile = RepositoryLanguageProfileService.scan(repoURL: repoURL)

    try #require(profile.primaryLanguage == .other)
    try #require(profile.manifestHints.isEmpty)
    try #require(profile.counts.other == 2)
    try #require(profile.scannedFileCount == 2)
    try #require(!profile.wasTruncated)
    try #require(profile.hudSummary?.contains("Repository profile") == true)
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
