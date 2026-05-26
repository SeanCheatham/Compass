import Foundation
import Testing
import XCTest

@testable import Compass

final class PlanTransitionValidatorTests: XCTestCase {
  func testRejectsClearingMidTermWithoutCompletion() {
    let current = makeState(completed: ["done"], midTerm: "- Next queued item")
    let next = makeState(completed: ["done"], midTerm: "   \n")

    assertTransitionRejected(from: current, to: next, contains: "clear a non-empty midTerm queue")
  }

  func testRejectsPlaceholderVerifyCommands() {
    let current = makeState()
    let next = makeState(immediate: PlanNext(plan: "Do work", verify: " true "))

    assertTransitionRejected(from: current, to: next, contains: "placeholder verify command")
  }

  func testAcceptsNormalImmediateWork() throws {
    let current = makeState(midTerm: "- Build the next slice")
    let next = makeState(
      immediate: PlanNext(plan: "Build the next slice", verify: "swift test"),
      midTerm: "- Build the next slice\n- Polish follow-up"
    )

    try PlanTransitionValidator.validate(from: current, to: next)
  }

  func testAcceptsMidTermRewriteWithoutChangingCompleted() throws {
    let current = makeState(completed: ["First slice"], midTerm: "- Old queue")
    let proposal = PlanProposal(
      immediate: PlanNext(plan: "Take the rewritten next step", verify: "swift test"),
      midTerm: "- Rewritten queue",
      longTerm: "Long-term direction"
    )
    let next = current.applying(proposal: proposal)

    XCTAssertEqual(next.completed, current.completed)
    try PlanTransitionValidator.validate(from: current, to: next)
  }

  func testAcceptsNoImmediateWorkState() throws {
    let current = makeState(completed: ["Everything shipped"], midTerm: "")
    let next = makeState(
      completed: ["Everything shipped"], immediate: nil, midTerm: "", longTerm: "")

    try PlanTransitionValidator.validate(from: current, to: next)
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

  private func assertTransitionRejected(
    from current: PlanState,
    to next: PlanState,
    contains expectedText: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try PlanTransitionValidator.validate(from: current, to: next),
      file: file,
      line: line
    ) { error in
      let message =
        (error as? PlanTransitionValidationError)?.message
        ?? (error as? LocalizedError)?.errorDescription
        ?? error.localizedDescription
      XCTAssertTrue(
        message.contains(expectedText),
        "Expected error containing `\(expectedText)`, got `\(message)`.",
        file: file,
        line: line
      )
    }
  }
}

final class PlanCompletionRecorderTests: XCTestCase {
  func testRecordsSuccessfulSessionPlanLine() {
    let state = PlanState.empty
    let sessions = [
      makeSucceededSession(1, plan: "Ship feature X\n\nDetails"),
    ]

    let updated = PlanCompletionRecorder.recordingShippedIterations(
      into: state,
      sessions: sessions
    )

    XCTAssertEqual(updated.completed, ["Ship feature X"])
  }

  func testDoesNotDuplicateAlreadyRecordedSessions() {
    let state = makeState(completed: ["Ship feature X"])
    let sessions = [makeSucceededSession(1, plan: "Ship feature X")]

    let updated = PlanCompletionRecorder.recordingShippedIterations(
      into: state,
      sessions: sessions
    )

    XCTAssertEqual(updated.completed, state.completed)
  }

  func testIgnoresFailedSessions() {
    var failed = SessionRecord.started(1)
    failed.status = .failed
    failed.plan = "Should not record"
    failed.endedAt = Date().timeIntervalSince1970 * 1000

    let updated = PlanCompletionRecorder.recordingShippedIterations(
      into: .empty,
      sessions: [failed]
    )

    XCTAssertEqual(updated.completed, [])
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

final class PlanHistoryPageTests: XCTestCase {
  func testReturnsNewestEntriesFirstWithPaginationHint() {
    let page = PlanHistoryPage.read(
      entries: ["First", "Second", "Third"],
      offset: 1,
      limit: 1
    )

    XCTAssertEqual(page.totalCount, 3)
    XCTAssertEqual(page.entries.map(\.iteration), [2])
    XCTAssertEqual(page.entries.map(\.summary), ["Second"])
    XCTAssertTrue(page.formatted().contains("offset 1 from newest"))
    XCTAssertTrue(page.formatted().contains("more: call plan_history with offset 2"))
  }

  func testIterationNumbersWithOffsetAndFourPlusEntries() {
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
    XCTAssertEqual(page.totalCount, 5)
    XCTAssertEqual(page.entries.map(\.iteration), [3, 2])
    XCTAssertEqual(page.entries.map(\.summary), ["C", "B"])
  }
}

final class AgentPlanHistoryToolTests: XCTestCase {
  func testReturnsPaginatedHistoryFromContext() async throws {
    let tool = AgentPlanHistoryTool()
    let args = try JSONSerialization.data(withJSONObject: ["offset": 0, "limit": 2])
    let context = AgentToolContext(
      workingDirectory: FileManager.default.temporaryDirectory,
      planHistoryEntries: ["First", "Second", "Third"]
    )

    let result = try await tool.invoke(arguments: args, context: context)

    XCTAssertFalse(result.isError)
    XCTAssertTrue(result.content.contains("#3: Third"))
    XCTAssertTrue(result.content.contains("#2: Second"))
    XCTAssertFalse(result.content.contains("#1: First"))
  }
}

struct PlanNextDecoderTests {
  @Test
  func decoderTrimsPlanAndVerifyAndKeepsPositiveTimeout() throws {
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
  }

  @Test
  func decoderDropsNonPositiveTimeouts() throws {
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
    let data = try XCTUnwrap(json.data(using: .utf8))
    return try JSONDecoder().decode(PlanNext.self, from: data)
  }
}

final class RepositoryLanguageProfileServiceTests: XCTestCase {
  func testDetectsSwiftPackageWhileIgnoringBuildDirectories() throws {
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

    XCTAssertEqual(profile.primaryLanguage, .swift)
    XCTAssertEqual(profile.manifestHints, [.packageSwift])
    XCTAssertEqual(profile.counts.swift, 2)
    XCTAssertEqual(profile.counts.typeScriptJavaScript, 0)
    XCTAssertEqual(profile.counts.python, 0)
    XCTAssertEqual(profile.scannedFileCount, 2)
    XCTAssertFalse(profile.wasTruncated)
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
