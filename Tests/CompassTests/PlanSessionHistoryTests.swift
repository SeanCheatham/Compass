import Foundation
import Testing

@testable import Compass

struct PlanSessionHistoryTests: ~Copyable {

  @Test
  func testOrdersSessionsReverseChronologically() throws {
    let sessions = [
      makeSession(1, startedAt: 1_000),
      makeSession(3, startedAt: 2_000),
      makeSession(2, startedAt: 3_000),
      makeSession(4, startedAt: 3_000),
    ]

    let items = PlanSessionHistory.displayItems(for: sessions)

    #require(items.map(\.sessionNumber) == [4, 2, 3, 1])
  }

  @Test
  func testHandlesEmptyAndPlanlessSessions() throws {
    #require(PlanSessionHistory.displayItems(for: []) == [])

    let items = PlanSessionHistory.displayItems(
      for: [
        makeSession(
          1,
          startedAt: 1_000,
          plan: nil,
          verify: "   ",
          feedback: "\n"
        )
      ]
    )

    #require(items.count == 1)
    #require(items[0].planExcerpt == nil)
    #require(items[0].verifyCommand == nil)
    #require(items[0].feedback == nil)
    #require(items[0].statusText == "Succeeded")
  }

  @Test
  func testPreservesFailedVerifyMetadata() throws {
    let items = PlanSessionHistory.displayItems(
      for: [
        makeSession(
          1,
          startedAt: 1_000,
          status: .failed,
          verify: "swift test",
          verifyOutput: VerifyOutput(
            command: "swift test --filter PlanSessionHistoryTests",
            exitCode: 65,
            tail: "failure tail"
          )
        )
      ]
    )

    let failedVerify = #require(items[0].failedVerify)
    #require(failedVerify.command == "swift test --filter PlanSessionHistoryTests")
    #require(failedVerify.exitCodeText == "exit 65")
    #require(failedVerify.tail == "failure tail")
  }

  @Test
  func testPreservesCommitsNotesAndFeedback() throws {
    let commit = SessionCommit(
      sha: "abcdef123456",
      short: "abcdef1",
      subject: "Ship plan history"
    )
    let items = PlanSessionHistory.displayItems(
      for: [
        makeSession(
          1,
          startedAt: 1_000,
          commits: [commit],
          notes: ["first note", "second note"],
          feedback: "  useful handoff  "
        )
      ]
    )

    #require(items[0].commits == [commit])
    #require(items[0].notes == ["first note", "second note"])
    #require(items[0].feedback == "useful handoff")
  }

  @Test
  func testUsesLatestRuntimeRouteSummaryForHistoryItems() throws {
    let planSnapshot = SessionExecutionEnvironmentSnapshot(
      phase: "Plan",
      launchPlan: AgentExecutionLaunchPlan.host()
    )
    let verifySnapshot = SessionExecutionEnvironmentSnapshot(
      phase: "Verify",
      attempt: 2,
      launchPlan: AgentExecutionLaunchPlan.host(
        fallbackReason: "Shared VM unavailable: 2-guest cap."
      )
    )

    let items = PlanSessionHistory.displayItems(
      for: [
        makeSession(
          1,
          startedAt: 1_000,
          executionEnvironmentSnapshots: [planSnapshot, verifySnapshot]
        ),
        makeSession(
          2,
          startedAt: 2_000,
          executionEnvironmentSnapshots: [planSnapshot]
        ),
      ]
    )

    #require(items.map(\.sessionNumber) == [2, 1])
    #require(items[0].runtimeRouteSummary == planSnapshot.routeSummary)
    #require(items[1].runtimeRouteSummary == verifySnapshot.routeSummary)
    #require(items[1].runtimeRouteSummary?.contains("Verify attempt 2") == true)
    #require(
      items[1].runtimeRouteSummary?.contains("fallback Shared VM unavailable: 2-guest cap.") == true
    )
    #require(
      items[1].runtimeRouteSummary?.count ?? 0 <= SessionExecutionEnvironmentSnapshot.summaryLimit
    )
  }

  @Test
  func testBoundsPlanExcerpt() throws {
    let items = PlanSessionHistory.displayItems(
      for: [
        makeSession(
          1,
          startedAt: 1_000,
          plan: "Build \n a\t very detailed plan with many words and extra detail."
        )
      ],
      planExcerptLimit: 24
    )

    #require(items[0].planExcerpt == "Build a very detailed...")
    #require(items[0].planExcerpt?.count ?? 0 <= 24)
  }

  @Test
  func testDisplayDefaultsToRecentLimit() throws {
    let sessionCount = PlanSessionHistoryDisplay.defaultRecentLimit + 3
    let items = PlanSessionHistory.displayItems(
      for: (1...sessionCount).map { number in
        makeSession(number, startedAt: Double(number * 1_000))
      }
    )

    let display = PlanSessionHistoryDisplay(items: items)

    #require(display.totalCount == sessionCount)
    #require(display.visibleCount == PlanSessionHistoryDisplay.defaultRecentLimit)
    #require(display.hiddenCount == 3)
    #require(
      display.visibleItems.map(\.sessionNumber) ==
      Array(
        (sessionCount - PlanSessionHistoryDisplay.defaultRecentLimit + 1...sessionCount).reversed())
    )
    #require(display.countSummary == "Showing latest 8 of 11")
    #require(display.shouldOfferModeToggle)
    #require(display.filter == .all)
    #require(display.unfilteredTotalCount == sessionCount)
    #require(display.filterOptions.map(\.filter) == PlanSessionHistoryFilter.allCases)
    #require(display.filterOptions.map(\.count) == [sessionCount, 0, 0, 0, sessionCount, 0, 0])
  }

  @Test
  func testDisplayShowAllModeIncludesEveryRun() throws {
    let items = PlanSessionHistory.displayItems(
      for: (1...7).map { number in
        makeSession(number, startedAt: Double(number * 1_000))
      }
    )

    let display = PlanSessionHistoryDisplay(items: items, mode: .all, recentLimit: 4)

    #require(display.visibleItems.map(\.sessionNumber) == [7, 6, 5, 4, 3, 2, 1])
    #require(display.totalCount == 7)
    #require(display.visibleCount == 7)
    #require(display.hiddenCount == 0)
    #require(display.hiddenStatusSummary == nil)
    #require(display.countSummary == "Showing all 7")
    #require(display.shouldOfferModeToggle)
  }

  @Test
  func testDisplaySummarizesHiddenStatuses() throws {
    let items = PlanSessionHistory.displayItems(
      for: [
        makeSession(1, startedAt: 1_000, status: .awaitingApproval),
        makeSession(2, startedAt: 2_000, status: .succeeded),
        makeSession(3, startedAt: 3_000, status: .cancelled),
        makeSession(4, startedAt: 4_000, status: .failed),
        makeSession(5, startedAt: 5_000, status: .failed),
        makeSession(6, startedAt: 6_000, status: .succeeded),
      ]
    )

    let display = PlanSessionHistoryDisplay(items: items, recentLimit: 1)

    #require(display.visibleItems.map(\.sessionNumber) == [6])
    #require(display.hiddenCount == 5)
    #require(
      display.hiddenStatusSummary ==
      "2 failed, 1 cancelled, 1 succeeded, 1 awaiting approval"
    )
  }

  @Test
  func testDisplayHandlesNoHiddenAndEmptyStates() throws {
    let items = PlanSessionHistory.displayItems(
      for: [
        makeSession(1, startedAt: 1_000),
        makeSession(2, startedAt: 2_000),
      ]
    )

    let noHiddenDisplay = PlanSessionHistoryDisplay(items: items, recentLimit: 3)
    #require(noHiddenDisplay.totalCount == 2)
    #require(noHiddenDisplay.visibleCount == 2)
    #require(noHiddenDisplay.hiddenCount == 0)
    #require(noHiddenDisplay.hiddenStatusSummary == nil)
    #require(noHiddenDisplay.countSummary == "2 runs")
    #require(!noHiddenDisplay.shouldOfferModeToggle)

    let emptyDisplay = PlanSessionHistoryDisplay(items: [])
    #require(emptyDisplay.totalCount == 0)
    #require(emptyDisplay.visibleCount == 0)
    #require(emptyDisplay.hiddenCount == 0)
    #require(emptyDisplay.hiddenStatusSummary == nil)
    #require(emptyDisplay.countSummary == "0 runs")
    #require(!emptyDisplay.shouldOfferModeToggle)
  }

  @Test
  func testDisplayPreservesIncomingOrder() throws {
    let items = [
      makeHistoryItem(2, status: .failed),
      makeHistoryItem(5),
      makeHistoryItem(1, status: .failed),
      makeHistoryItem(4, status: .failed),
    ]

    let recentDisplay = PlanSessionHistoryDisplay(items: items, recentLimit: 2)
    #require(recentDisplay.visibleItems.map(\.sessionNumber) == [2, 5])

    let allDisplay = PlanSessionHistoryDisplay(items: items, mode: .all, recentLimit: 2)
    #require(allDisplay.visibleItems.map(\.sessionNumber) == [2, 5, 1, 4])

    let filteredRecentDisplay = PlanSessionHistoryDisplay(
      items: items,
      recentLimit: 2,
      filter: .failedRejected
    )
    #require(filteredRecentDisplay.visibleItems.map(\.sessionNumber) == [2, 1])

    let filteredAllDisplay = PlanSessionHistoryDisplay(
      items: items,
      mode: .all,
      recentLimit: 2,
      filter: .failedRejected
    )
    #require(filteredAllDisplay.visibleItems.map(\.sessionNumber) == [2, 1, 4])
  }

  @Test
  func testDisplayPreservesFailedVerifyMetadataForVisibleRows() throws {
    let items = PlanSessionHistory.displayItems(
      for: [
        makeSession(
          1,
          startedAt: 1_000,
          status: .failed,
          verify: "swift test",
          verifyOutput: VerifyOutput(
            command: "swift test --filter PlanSessionHistoryTests",
            exitCode: 65,
            tail: "failure tail"
          )
        )
      ]
    )

    let display = PlanSessionHistoryDisplay(items: items)

    let failedVerify = #require(display.visibleItems[0].failedVerify)
    #require(failedVerify.command == "swift test --filter PlanSessionHistoryTests")
    #require(failedVerify.exitCodeText == "exit 65")
    #require(failedVerify.tail == "failure tail")
  }

  @Test
  func testDisplayFiltersAttentionRunsFromRunCues() throws {
    let items = [
      makeHistoryItem(4),
      makeHistoryItem(3),
      makeHistoryItem(2),
      makeHistoryItem(1),
    ]
    let display = PlanSessionHistoryDisplay(
      items: items,
      mode: .all,
      filter: .attention,
      runCues: [
        4: makeRunCue(kind: .resumeDevelop, severity: .paused),
        2: makeRunCue(kind: .failedVerify),
      ]
    )

    #require(display.totalCount == 2)
    #require(display.visibleItems.map(\.sessionNumber) == [4, 2])
    #require(display.countSummary == "2 matching runs")
    #require(
      display.filterOptions.first { $0.filter == .attention }?.count == 2
    )
  }

  @Test
  func testDisplayGroupsFailedAndRejectedRuns() throws {
    let items = [
      makeHistoryItem(7+0),
      makeHistoryItem(6+0),
      makeHistoryItem(5+0),
      makeHistoryItem(4+0, status: .rejectedByPlan),
      makeHistoryItem(3+0, status: .failed),
      makeHistoryItem(2+0),
      makeHistoryItem(1+0),
    ]
    let display = PlanSessionHistoryDisplay(
      items: items,
      mode: .all,
      filter: .failedRejected,
      runCues: [
        7: makeRunCue(kind: .promotionFailed),
        6: makeRunCue(kind: .dirtyWorktree, severity: .warning),
        5: makeRunCue(kind: .failedVerify),
        2: makeRunCue(kind: .developFailed),
      ]
    )

    #require(display.visibleItems.map(\.sessionNumber) == [7, 6, 5, 4, 3, 2])
    #require(display.totalCount == 6)
  }

  @Test
  func testDisplayGroupsActiveAndPausedRuns() throws {
    let items = [
      makeHistoryItem(5+0),
      makeHistoryItem(4+0, status: .awaitingApproval),
      makeHistoryItem(3+0, status: .developing),
      makeHistoryItem(2+0, status: .planning),
      makeHistoryItem(1+0),
    ]
    let display = PlanSessionHistoryDisplay(
      items: items,
      mode: .all,
      filter: .activePaused,
      runCues: [
        5: makeRunCue(kind: .resumeDevelop, severity: .paused)
      ]
    )

    #require(display.visibleItems.map(\.sessionNumber) == [5, 4, 3, 2])
    #require(display.totalCount == 4)
  }

  @Test
  func testDisplayGroupsCompletedAndFinishedRuns() throws {
    let items = [
      makeHistoryItem(6+0, status: .succeeded),
      makeHistoryItem(5+0, status: .cancelled),
      makeHistoryItem(4+0, status: .skipped),
      makeHistoryItem(3+0, status: .failed),
      makeHistoryItem(2+0, status: .rejectedByPlan),
      makeHistoryItem(1+0, status: .awaitingApproval),
    ]
    let display = PlanSessionHistoryDisplay(
      items: items,
      mode: .all,
      filter: .completedFinished
    )

    #require(display.visibleItems.map(\.sessionNumber) == [6, 5, 4])
    #require(display.totalCount == 3)
  }

  @Test
  func testDisplaySummariesUseFilteredCounts() throws {
    let items = [
      makeHistoryItem(6+0),
      makeHistoryItem(5+0),
      makeHistoryItem(4+0),
      makeHistoryItem(3+0),
      makeHistoryItem(2+0),
      makeHistoryItem(1+0),
    ]
    let runCues = [
      6: makeRunCue(kind: .failedVerify),
      5: makeRunCue(kind: .developFailed),
      4: makeRunCue(kind: .resumeDevelop, severity: .paused),
    ]

    let recentDisplay = PlanSessionHistoryDisplay(
      items: items,
      recentLimit: 2,
      filter: .attention,
      runCues: runCues
    )
    #require(recentDisplay.visibleItems.map(\.sessionNumber) == [6, 5])
    #require(recentDisplay.totalCount == 3)
    #require(recentDisplay.hiddenCount == 1)
    #require(recentDisplay.countSummary == "Showing latest 2 of 3 matching")
    #require(recentDisplay.shouldOfferModeToggle)

    let allDisplay = PlanSessionHistoryDisplay(
      items: items,
      mode: .all,
      recentLimit: 2,
      filter: .attention,
      runCues: runCues
    )
    #require(allDisplay.countSummary == "Showing all 3 matching")

    let noHiddenDisplay = PlanSessionHistoryDisplay(
      items: items,
      recentLimit: 4,
      filter: .attention,
      runCues: runCues
    )
    #require(noHiddenDisplay.countSummary == "3 matching runs")

    let emptyFilteredDisplay = PlanSessionHistoryDisplay(
      items: items,
      filter: .failedRejected
    )
    #require(emptyFilteredDisplay.unfilteredTotalCount == 6)
    #require(emptyFilteredDisplay.totalCount == 0)
    #require(emptyFilteredDisplay.countSummary == "0 matching runs")
  }

  @Test
  func testDisplaySummarizesHiddenStatusesAfterFiltering() throws {
    let items = [
      makeHistoryItem(6+0, status: .failed),
      makeHistoryItem(5+0, status: .succeeded),
      makeHistoryItem(4+0, status: .rejectedByPlan),
      makeHistoryItem(3+0, status: .cancelled),
      makeHistoryItem(2+0, status: .skipped),
      makeHistoryItem(1+0, status: .awaitingApproval),
    ]

    let display = PlanSessionHistoryDisplay(
      items: items,
      recentLimit: 1,
      filter: .completedFinished
    )

    #require(display.visibleItems.map(\.sessionNumber) == [5])
    #require(display.hiddenCount == 2)
    #require(display.hiddenStatusSummary == "1 cancelled, 1 skipped")
  }

  private func makeHistoryItem(
    _ number: Int,
    status: SessionStatus = .succeeded
  ) -> PlanSessionHistoryItem {
    PlanSessionHistoryItem(
      sessionNumber: number,
      status: status,
      statusText: statusText(for: status),
      startedAt: Date(timeIntervalSince1970: Double(number)),
      planExcerpt: "Plan",
      verifyCommand: "swift test",
      feedback: nil,
      notes: [],
      commits: [],
      failedVerify: nil,
      runtimeRouteSummary: nil
    )
  }

  private func makeRunCue(
    kind: PlanReliabilityFeedback.Kind,
    severity: PlanReliabilityFeedback.Severity = .failure
  ) -> PlanReliabilityFeedback.RunCue {
    PlanReliabilityFeedback.RunCue(
      notice: PlanReliabilityFeedback.Notice(
        id: "\(kind.rawValue)-test",
        kind: kind,
        severity: severity,
        sessionNumber: 0,
        title: "Cue",
        detail: "Run needs attention.",
        actionLabel: "Review",
        metadata: nil,
        systemImage: "exclamationmark.triangle"
      )
    )
  }

  private func statusText(for status: SessionStatus) -> String {
    switch status {
    case .planning:
      return "Planning"
    case .awaitingApproval:
      return "Awaiting approval"
    case .developing:
      return "Developing"
    case .succeeded:
      return "Succeeded"
    case .failed:
      return "Failed"
    case .cancelled:
      return "Cancelled"
    case .rejectedByPlan:
      return "Rejected by plan"
    case .skipped:
      return "Skipped"
    }
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
    feedback: String? = nil,
    executionEnvironmentSnapshots: [SessionExecutionEnvironmentSnapshot] = []
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
      feedback: feedback,
      executionEnvironmentSnapshots: executionEnvironmentSnapshots
    )
  }

  private func profile(_ language: RepositoryLanguage) -> RepositoryLanguageProfile {
    var counts = RepositoryLanguageCounts()
    counts[language] = language == .unknown ? 0 : 1
    return RepositoryLanguageProfile(
      counts: counts,
      manifestHints: [],
      primaryLanguage: language,
      scannedFileCount: language == .unknown ? 0 : 1,
      scannedDirectoryCount: 1,
      wasTruncated: false
    )
  }

  private func makeRuntimeSnapshot(
    repoPrefix: String,
    phase: String = "Plan",
    vmReadiness: SharedCompassVMReadiness? = nil,
    sharedVMRouteFactory: (URL) -> SharedVMRoute? = { _ in nil }
  ) throws -> SessionExecutionEnvironmentSnapshot {
    let repoURL = try makeTemporaryDirectory(prefix: repoPrefix)
    let plan = AgentExecutionLaunchPlan.plan(
      repoURL: repoURL,
      vmReadiness: vmReadiness,
      sharedVMRouteFactory: sharedVMRouteFactory
    )
    return SessionExecutionEnvironmentSnapshot(phase: phase, launchPlan: plan)
  }

  deinit {
    // No persistent cleanup needed in test scope
  }

  private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.standardizedFileURL
  }

  private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try text.data(using: .utf8)?.write(to: url)
  }
}
