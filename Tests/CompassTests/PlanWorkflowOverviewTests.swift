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
      overview.sections.map(\.timelineItemID) ==
      ["plan-immediate", "plan-mid-term", "plan-long-term"]
    )
    try #require(
      PlanWorkflowOverview.TimelineDestination.allCases.map(\.overviewKind) ==
      [.immediate, .midTerm, .longTerm]
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
      overview.midTerm.emptyMessage ==
      "No mid-term queue. Future planning has no staged direction yet.")
    try #require(
      overview.longTerm.emptyMessage ==
      "No long-term arc. Add the larger product direction when it becomes clear.")
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

  private func profile(_ language: RepositoryLanguage) -> RepositoryLanguageProfile {
    var counts = RepositoryLanguageCounts()
    counts[language] = 1
    return RepositoryLanguageProfile(
      counts: counts,
      manifestHints: [],
      primaryLanguage: language,
      scannedFileCount: 1,
      scannedDirectoryCount: 1,
      wasTruncated: false
    )
  }
}
