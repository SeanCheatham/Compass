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
    let next = makeState(immediate: PlanNext(plan: "Do work", verify: " true "))

    assertTransitionRejected(from: current, to: next, contains: "placeholder verify command")
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
      immediate: PlanNext(plan: executablePlan("Take the rewritten next step"), verify: "swift test"),
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

    assertTransitionRejected(from: current, to: next, contains: "Immediate Plan")
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

    assertTransitionRejected(
      from: current,
      to: next,
      contains: "Missing Acceptance checks"
    )
  }

  @Test func testRejectsNoImmediateWorkWhenLongTermRemains() throws {
    let current = makeState(completed: ["done"], midTerm: "", longTerm: "")
    let next = makeState(
      completed: ["done"],
      immediate: nil,
      midTerm: "",
      longTerm: "Build toward the Explore layer"
    )

    assertTransitionRejected(from: current, to: next, contains: "proposed longTerm")
  }

  @Test func testRejectsNoImmediateWorkWhenClearingExistingLongTerm() throws {
    let current = makeState(
      completed: ["done"],
      midTerm: "",
      longTerm: "Build toward the Explore layer"
    )
    let next = makeState(completed: ["done"], immediate: nil, midTerm: "", longTerm: "")

    assertTransitionRejected(from: current, to: next, contains: "current longTerm")
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

    assertTransitionRejected(
      from: current,
      to: next,
      contains: "enable-code-coverage",
      forgeProfile: .swiftSPM
    )
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

  private func executablePlan(_ outcome: String) -> String {
    """
    ## Outcome
    \(outcome).

    ## Why it matters
    The owner can understand the next slice before Develop starts.

    ## Acceptance checks
    - The planned behavior is implemented.
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
