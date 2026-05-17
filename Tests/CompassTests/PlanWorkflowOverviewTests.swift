import Foundation
@testable import Compass
import XCTest

final class PlanWorkflowOverviewTests: XCTestCase {
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

        XCTAssertEqual(overview.sections.map(\.kind), [.immediate, .midTerm, .longTerm])
        XCTAssertEqual(overview.immediate.body, "Build the overview\n\n- Keep completed summaries selectable")
        XCTAssertEqual(overview.midTerm.body, "- Queue the next planning polish")
        XCTAssertEqual(overview.longTerm.body, "Make waiting time easier to understand.")
        XCTAssertFalse(overview.immediate.isEmpty)
    }

    func testOverviewKindsMapToStableTimelineDestinations() {
        XCTAssertEqual(PlanWorkflowOverview.Kind.immediate.timelineItemID, "plan-immediate")
        XCTAssertEqual(PlanWorkflowOverview.Kind.midTerm.timelineItemID, "plan-mid-term")
        XCTAssertEqual(PlanWorkflowOverview.Kind.longTerm.timelineItemID, "plan-long-term")

        XCTAssertEqual(PlanWorkflowOverview.Kind(timelineItemID: "plan-immediate"), .immediate)
        XCTAssertEqual(PlanWorkflowOverview.Kind(timelineItemID: "plan-mid-term"), .midTerm)
        XCTAssertEqual(PlanWorkflowOverview.Kind(timelineItemID: "plan-long-term"), .longTerm)
        XCTAssertNil(PlanWorkflowOverview.Kind(timelineItemID: "plan-history-0"))
    }

    func testSectionTimelineDestinationsFollowOverviewOrder() {
        let overview = PlanWorkflowOverview(
            state: makeState(
                completed: ["Past work"],
                midTerm: "Queue",
                longTerm: "Arc"
            )
        )

        XCTAssertEqual(overview.sections.map(\.kind), [.immediate, .midTerm, .longTerm])
        XCTAssertEqual(
            overview.sections.map(\.timelineItemID),
            ["plan-immediate", "plan-mid-term", "plan-long-term"]
        )
        XCTAssertEqual(
            PlanWorkflowOverview.TimelineDestination.allCases.map(\.overviewKind),
            [.immediate, .midTerm, .longTerm]
        )
    }

    func testNoImmediateStateKeepsQueueAndArcVisible() {
        let overview = PlanWorkflowOverview(
            state: makeState(
                completed: ["Everything shipped"],
                immediate: nil,
                midTerm: "- Later work",
                longTerm: "Long arc"
            )
        )

        XCTAssertTrue(overview.immediate.isEmpty)
        XCTAssertEqual(overview.immediate.body, "")
        XCTAssertNil(overview.immediate.excerpt)
        XCTAssertNil(overview.immediate.verifyCommand)
        XCTAssertNil(overview.immediate.estimatedDifficulty)
        XCTAssertEqual(overview.midTerm.excerpt, "- Later work")
        XCTAssertEqual(overview.longTerm.excerpt, "Long arc")
    }

    func testEmptyQueueAndArcExposeSpecificEmptyMessages() {
        let overview = PlanWorkflowOverview(
            state: makeState(
                immediate: nil,
                midTerm: " \n ",
                longTerm: "\t"
            )
        )

        XCTAssertTrue(overview.midTerm.isEmpty)
        XCTAssertTrue(overview.longTerm.isEmpty)
        XCTAssertEqual(overview.midTerm.emptyMessage, "No mid-term queue. Future planning has no staged direction yet.")
        XCTAssertEqual(overview.longTerm.emptyMessage, "No long-term arc. Add the larger product direction when it becomes clear.")
    }

    func testNormalizesMarkdownWhitespace() {
        let overview = PlanWorkflowOverview(
            state: makeState(
                midTerm: " \tFirst\t\titem  \r\n\r\n\r\n  - Queue\t two  \r Continued    text \n\n",
                longTerm: "  Arc\t\twith   spacing  "
            )
        )

        XCTAssertEqual(overview.midTerm.body, "First item\n\n- Queue two\nContinued text")
        XCTAssertEqual(overview.longTerm.body, "Arc with spacing")
    }

    func testBoundsDenseExcerpts() {
        let overview = PlanWorkflowOverview(
            state: makeState(
                longTerm: "Alpha beta gamma delta epsilon zeta eta theta iota"
            ),
            excerptLimit: 25
        )

        XCTAssertEqual(overview.longTerm.excerpt, "Alpha beta gamma delta...")
        XCTAssertLessThanOrEqual(overview.longTerm.excerpt?.count ?? 0, 25)
    }

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

        XCTAssertEqual(overview.immediate.verifyCommand, "swift test --filter PlanWorkflowOverviewTests")
        XCTAssertEqual(overview.immediate.estimatedDifficulty, .high)
        XCTAssertEqual(overview.immediate.estimatedDifficultyLabel, "High")
    }

    func testPreservesCompletedCountMetadata() {
        let overview = PlanWorkflowOverview(
            state: makeState(completed: ["one", "two", "three"])
        )

        XCTAssertEqual(overview.completedCount, 3)
        XCTAssertEqual(overview.sections.map(\.completedCount), [3, 3, 3])
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
}
