import Foundation
import Testing

@testable import Compass

struct PlanWorkflowOverviewTests {
  @Test
  func testBuildsPopulatedOverviewSections() {
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

    #require(overview.sections.map(\.kind) == [.immediate, .midTerm, .longTerm])
    #require(
      overview.immediate.body == "Build the overview\n\n- Keep completed summaries selectable")
    #require(overview.midTerm.body == "- Queue the next planning polish")
    #require(overview.longTerm.body == "Make waiting time easier to understand.")
    #require(!overview.immediate.isEmpty)
  }

  @Test
  func testOverviewKindsMapToStableTimelineDestinations() {
    #require(PlanWorkflowOverview.Kind.immediate.timelineItemID == "plan-immediate")
    #require(PlanWorkflowOverview.Kind.midTerm.timelineItemID == "plan-mid-term")
    #require(PlanWorkflowOverview.Kind.longTerm.timelineItemID == "plan-long-term")

    #require(PlanWorkflowOverview.Kind(timelineItemID: "plan-immediate") == .immediate)
    #require(PlanWorkflowOverview.Kind(timelineItemID: "plan-mid-term") == .midTerm)
    #require(PlanWorkflowOverview.Kind(timelineItemID: "plan-long-term") == .longTerm)
    #require(PlanWorkflowOverview.Kind(timelineItemID: "plan-history-0") == nil)
  }

  @Test
  func testSectionTimelineDestinationsFollowOverviewOrder() {
    let overview = PlanWorkflowOverview(
      state: makeState(
        completed: ["Past work"],
        midTerm: "Queue",
        longTerm: "Arc"
      )
    )

    #require(overview.sections.map(\.kind) == [.immediate, .midTerm, .longTerm])
    #require(
      overview.sections.map(\.timelineItemID) ==
      ["plan-immediate", "plan-mid-term", "plan-long-term"]
    )
    #require(
      PlanWorkflowOverview.TimelineDestination.allCases.map(\.overviewKind) ==
      [.immediate, .midTerm, .longTerm]
    )
  }

  @Test
  func testNoImmediateStateKeepsQueueAndArcVisible() {
    let overview = PlanWorkflowOverview(
      state: makeState(
        completed: ["Everything shipped"],
        immediate: nil,
        midTerm: "- Later work",
        longTerm: "Long arc"
      )
    )

    #require(overview.immediate.isEmpty)
    #require(overview.immediate.body == "")
    #require(overview.immediate.excerpt == nil)
    #require(overview.immediate.verifyCommand == nil)
    #require(overview.immediate.verifyTimeoutLabel == nil)
    #require(overview.immediate.estimatedDifficulty == nil)
    #require(overview.midTerm.excerpt == "- Later work")
    #require(overview.longTerm.excerpt == "Long arc")
  }

  @Test
  func testEmptyQueueAndArcExposeSpecificEmptyMessages() {
    let overview = PlanWorkflowOverview(
      state: makeState(
        immediate: nil,
        midTerm: " \n ",
        longTerm: "\t"
      )
    )

    #require(overview.midTerm.isEmpty)
    #require(overview.longTerm.isEmpty)
    #require(
      overview.midTerm.emptyMessage ==
      "No mid-term queue. Future planning has no staged direction yet.")
    #require(
      overview.longTerm.emptyMessage ==
      "No long-term arc. Add the larger product direction when it becomes clear.")
  }

  @Test
  func testNormalizesMarkdownWhitespace() {
    let overview = PlanWorkflowOverview(
      state: makeState(
        midTerm: " \tFirst\t\titem  \r\n\r\n\r\n  - Queue\t two  \r Continued    text \n\n",
        longTerm: "  Arc\t\twith   spacing  "
      )
    )

    #require(overview.midTerm.body == "First item\n\n- Queue two\nContinued text")
    #require(overview.longTerm.body == "Arc with spacing")
  }

  @Test
  func testBoundsDenseExcerpts() {
    let overview = PlanWorkflowOverview(
      state: makeState(
        longTerm: "Alpha beta gamma delta epsilon zeta eta theta iota"
      ),
      excerptLimit: 25
    )

    #require(overview.longTerm.excerpt == "Alpha beta gamma delta...")
    #require(overview.longTerm.excerpt?.count ?? 0 <= 25)
  }

  @Test
  func testPreservesVerifyAndDifficultyMetadata() {
    let overview = PlanWorkflowOverview(
      state: makeState(
        immediate: PlanNext(
          plan: "Implement the slice",
          verify: " swift test --filter PlanWorkflowOverviewTests ",
          estimatedDifficulty: .high
        )
      )
    )

    #require(
      overview.immediate.verifyCommand == "swift test --filter PlanWorkflowOverviewTests")
    #require(overview.immediate.estimatedDifficulty == .high)
    #require(overview.immediate.estimatedDifficultyLabel == "High")
  }

  @Test
  func testVerifyTimeoutMetadataFormatsExplicitSeconds() {
    let metadata = PlanVerifyMetadata(timeoutMs: 90_000)

    #require(metadata.label == "Timeout 90s")
  }

  @Test
  func testVerifyTimeoutMetadataFormatsExplicitMinutes() {
    let metadata = PlanVerifyMetadata(timeoutMs: 600_000)

    #require(metadata.label == "Timeout 10m")
  }

  @Test
  func testVerifyTimeoutMetadataLabelsDefaultTimeout() {
    let metadata = PlanVerifyMetadata(timeoutMs: nil)

    #require(metadata.label == "Default timeout 10m")
  }

  @Test
  func testSectionPropagatesVerifyTimeoutMetadataOnlyForImmediatePlan() {
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

    #require(overview.immediate.verifyTimeoutLabel == "Timeout 90s")
    #require(overview.sections.map(\.verifyTimeoutLabel) == ["Timeout 90s", nil, nil])
  }

  @Test
  func testSectionPropagatesDefaultVerifyTimeoutMetadataForImmediatePlan() {
    let overview = PlanWorkflowOverview(
      state: makeState(
        immediate: PlanNext(
          plan: "Implement the slice",
          verify: "swift test --filter PlanWorkflowOverviewTests",
          estimatedDifficulty: .low
        )
      )
    )

    #require(overview.immediate.verifyTimeoutLabel == "Default timeout 10m")
  }

  @Test
  func testPreservesCompletedCountMetadata() {
    let overview = PlanWorkflowOverview(
      state: makeState(completed: ["one", "two", "three"])
    )

    #require(overview.completedCount == 3)
    #require(overview.sections.map(\.completedCount) == [3, 3, 3])
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
