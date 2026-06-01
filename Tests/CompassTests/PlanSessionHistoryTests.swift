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

    try #require(items.map(\.sessionNumber) == [4, 2, 3, 1])
  }

  @Test
  func testHandlesEmptyAndPlanlessSessions() throws {
    try #require(PlanSessionHistory.displayItems(for: []) == [])

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

    try #require(items.count == 1)
    try #require(items[0].planExcerpt == nil)
    try #require(items[0].verifyCommand == nil)
    try #require(items[0].feedback == nil)
    try #require(items[0].statusText == "Succeeded")
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

    let failedVerify = try #require(items[0].failedVerify)
    try #require(failedVerify.command == "swift test --filter PlanSessionHistoryTests")
    try #require(failedVerify.exitCodeText == "exit 65")
    try #require(failedVerify.tail == "failure tail")
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

    try #require(items[0].commits == [commit])
    try #require(items[0].notes == ["first note", "second note"])
    try #require(items[0].feedback == "useful handoff")
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

    try #require(items.map(\.sessionNumber) == [2, 1])
    try #require(items[0].runtimeRouteSummary == planSnapshot.routeSummary)
    try #require(items[1].runtimeRouteSummary == verifySnapshot.routeSummary)
    try #require(items[1].runtimeRouteSummary?.contains("Verify attempt 2") == true)
    try #require(
      items[1].runtimeRouteSummary?.contains("fallback Shared VM unavailable: 2-guest cap.") == true
    )
    try #require(
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

    try #require(items[0].planExcerpt == "Build a very detailed...")
    try #require(items[0].planExcerpt?.count ?? 0 <= 24)
  }

  @Test
  func testExtractsHandoffDigestFromFullPlanForHistoryRows() throws {
    let items = PlanSessionHistory.displayItems(
      for: [
        makeSession(
          1,
          startedAt: 1_000,
          plan: """
            ## Outcome
            Show a plain-language run summary in history.

            ## Why it matters
            Non-engineers can tell what happened without reading markdown.

            ## Acceptance checks
            - Run history shows the attempted outcome.
            - Run history keeps the verify command available.
            """,
          verify: "swift test --filter PlanSessionHistoryTests"
        )
      ],
      planExcerptLimit: 24
    )

    let digest = items[0].handoffDigest
    try #require(items[0].planExcerpt == "## Outcome Show a pla...")
    try #require(digest.status == .ready)
    try #require(digest.title == "Executable handoff")
    try #require(digest.outcome == "Show a plain-language run summary in history.")
    try #require(
      digest.whyItMatters == "Non-engineers can tell what happened without reading markdown."
    )
    try #require(
      digest.acceptanceChecks == [
        "Run history shows the attempted outcome.",
        "Run history keeps the verify command available.",
      ]
    )
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

    try #require(display.totalCount == sessionCount)
    try #require(display.visibleCount == PlanSessionHistoryDisplay.defaultRecentLimit)
    try #require(display.hiddenCount == 3)
    try #require(
      display.visibleItems.map(\.sessionNumber)
        == Array(
          (sessionCount - PlanSessionHistoryDisplay.defaultRecentLimit + 1...sessionCount)
            .reversed())
    )
    try #require(display.countSummary == "Showing latest 8 of 11")
    try #require(display.shouldOfferModeToggle)
    try #require(display.filter == .all)
    try #require(display.unfilteredTotalCount == sessionCount)
    try #require(display.filterOptions.map(\.filter) == PlanSessionHistoryFilter.allCases)
    try #require(display.filterOptions.map(\.count) == [sessionCount, 0, 0, 0, sessionCount, 0, 0])
  }

  @Test
  func testDisplayShowAllModeIncludesEveryRun() throws {
    let items = PlanSessionHistory.displayItems(
      for: (1...7).map { number in
        makeSession(number, startedAt: Double(number * 1_000))
      }
    )

    let display = PlanSessionHistoryDisplay(items: items, mode: .all, recentLimit: 4)

    try #require(display.visibleItems.map(\.sessionNumber) == [7, 6, 5, 4, 3, 2, 1])
    try #require(display.totalCount == 7)
    try #require(display.visibleCount == 7)
    try #require(display.hiddenCount == 0)
    try #require(display.hiddenStatusSummary == nil)
    try #require(display.countSummary == "Showing all 7")
    try #require(display.shouldOfferModeToggle)
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

    try #require(display.visibleItems.map(\.sessionNumber) == [6])
    try #require(display.hiddenCount == 5)
    try #require(
      display.hiddenStatusSummary == "2 failed, 1 cancelled, 1 succeeded, 1 awaiting approval"
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
    try #require(noHiddenDisplay.totalCount == 2)
    try #require(noHiddenDisplay.visibleCount == 2)
    try #require(noHiddenDisplay.hiddenCount == 0)
    try #require(noHiddenDisplay.hiddenStatusSummary == nil)
    try #require(noHiddenDisplay.countSummary == "2 runs")
    try #require(!noHiddenDisplay.shouldOfferModeToggle)

    let emptyDisplay = PlanSessionHistoryDisplay(items: [])
    try #require(emptyDisplay.totalCount == 0)
    try #require(emptyDisplay.visibleCount == 0)
    try #require(emptyDisplay.hiddenCount == 0)
    try #require(emptyDisplay.hiddenStatusSummary == nil)
    try #require(emptyDisplay.countSummary == "0 runs")
    try #require(!emptyDisplay.shouldOfferModeToggle)
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
    try #require(recentDisplay.visibleItems.map(\.sessionNumber) == [2, 5])

    let allDisplay = PlanSessionHistoryDisplay(items: items, mode: .all, recentLimit: 2)
    try #require(allDisplay.visibleItems.map(\.sessionNumber) == [2, 5, 1, 4])

    let filteredRecentDisplay = PlanSessionHistoryDisplay(
      items: items,
      recentLimit: 2,
      filter: .failedRejected
    )
    try #require(filteredRecentDisplay.visibleItems.map(\.sessionNumber) == [2, 1])

    let filteredAllDisplay = PlanSessionHistoryDisplay(
      items: items,
      mode: .all,
      recentLimit: 2,
      filter: .failedRejected
    )
    try #require(filteredAllDisplay.visibleItems.map(\.sessionNumber) == [2, 1, 4])
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

    let failedVerify = try #require(display.visibleItems[0].failedVerify)
    try #require(failedVerify.command == "swift test --filter PlanSessionHistoryTests")
    try #require(failedVerify.exitCodeText == "exit 65")
    try #require(failedVerify.tail == "failure tail")
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

    try #require(display.totalCount == 2)
    try #require(display.visibleItems.map(\.sessionNumber) == [4, 2])
    try #require(display.countSummary == "2 matching runs")
    try #require(
      display.filterOptions.first { $0.filter == .attention }?.count == 2
    )
  }

  @Test
  func testDisplayGroupsFailedAndRejectedRuns() throws {
    let items = [
      makeHistoryItem(7 + 0),
      makeHistoryItem(6 + 0),
      makeHistoryItem(5 + 0),
      makeHistoryItem(4 + 0, status: .rejectedByPlan),
      makeHistoryItem(3 + 0, status: .failed),
      makeHistoryItem(2 + 0),
      makeHistoryItem(1 + 0),
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

    try #require(display.visibleItems.map(\.sessionNumber) == [7, 6, 5, 4, 3, 2])
    try #require(display.totalCount == 6)
  }

  @Test
  func testDisplayGroupsActiveAndPausedRuns() throws {
    let items = [
      makeHistoryItem(5 + 0),
      makeHistoryItem(4 + 0, status: .awaitingApproval),
      makeHistoryItem(3 + 0, status: .developing),
      makeHistoryItem(2 + 0, status: .planning),
      makeHistoryItem(1 + 0),
    ]
    let display = PlanSessionHistoryDisplay(
      items: items,
      mode: .all,
      filter: .activePaused,
      runCues: [
        5: makeRunCue(kind: .resumeDevelop, severity: .paused)
      ]
    )

    try #require(display.visibleItems.map(\.sessionNumber) == [5, 4, 3, 2])
    try #require(display.totalCount == 4)
  }

  @Test
  func testDisplayGroupsCompletedAndFinishedRuns() throws {
    let items = [
      makeHistoryItem(6 + 0, status: .succeeded),
      makeHistoryItem(5 + 0, status: .cancelled),
      makeHistoryItem(4 + 0, status: .skipped),
      makeHistoryItem(3 + 0, status: .failed),
      makeHistoryItem(2 + 0, status: .rejectedByPlan),
      makeHistoryItem(1 + 0, status: .awaitingApproval),
    ]
    let display = PlanSessionHistoryDisplay(
      items: items,
      mode: .all,
      filter: .completedFinished
    )

    try #require(display.visibleItems.map(\.sessionNumber) == [6, 5, 4])
    try #require(display.totalCount == 3)
  }

  @Test
  func testDisplaySummariesUseFilteredCounts() throws {
    let items = [
      makeHistoryItem(6 + 0),
      makeHistoryItem(5 + 0),
      makeHistoryItem(4 + 0),
      makeHistoryItem(3 + 0),
      makeHistoryItem(2 + 0),
      makeHistoryItem(1 + 0),
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
    try #require(recentDisplay.visibleItems.map(\.sessionNumber) == [6, 5])
    try #require(recentDisplay.totalCount == 3)
    try #require(recentDisplay.hiddenCount == 1)
    try #require(recentDisplay.countSummary == "Showing latest 2 of 3 matching")
    try #require(recentDisplay.shouldOfferModeToggle)

    let allDisplay = PlanSessionHistoryDisplay(
      items: items,
      mode: .all,
      recentLimit: 2,
      filter: .attention,
      runCues: runCues
    )
    try #require(allDisplay.countSummary == "Showing all 3 matching")

    let noHiddenDisplay = PlanSessionHistoryDisplay(
      items: items,
      recentLimit: 4,
      filter: .attention,
      runCues: runCues
    )
    try #require(noHiddenDisplay.countSummary == "3 matching runs")

    let emptyFilteredDisplay = PlanSessionHistoryDisplay(
      items: items,
      filter: .failedRejected
    )
    try #require(emptyFilteredDisplay.unfilteredTotalCount == 6)
    try #require(emptyFilteredDisplay.totalCount == 0)
    try #require(emptyFilteredDisplay.countSummary == "0 matching runs")
  }

  @Test
  func testDisplaySummarizesHiddenStatusesAfterFiltering() throws {
    let items = [
      makeHistoryItem(6 + 0, status: .failed),
      makeHistoryItem(5 + 0, status: .succeeded),
      makeHistoryItem(4 + 0, status: .rejectedByPlan),
      makeHistoryItem(3 + 0, status: .cancelled),
      makeHistoryItem(2 + 0, status: .skipped),
      makeHistoryItem(1 + 0, status: .awaitingApproval),
    ]

    let display = PlanSessionHistoryDisplay(
      items: items,
      recentLimit: 1,
      filter: .completedFinished
    )

    try #require(display.visibleItems.map(\.sessionNumber) == [5])
    try #require(display.hiddenCount == 2)
    try #require(display.hiddenStatusSummary == "1 cancelled, 1 skipped")
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
