import Foundation
@testable import Compass
import XCTest

final class CinematicPlanCompassHistoryTests: XCTestCase {
    func testRecentCompletedWaypointsAreBoundedWithStableOrdinalsAndTruncationMetadata() {
        let completed = (1...6).map {
            "Completed waypoint \($0) with enough implementation detail to prove copy bounds stay controlled."
        }
        let plan = CinematicPlanCompassPlan(state: makeState(completed: completed))
        let repeated = CinematicPlanCompassPlan(state: makeState(completed: completed))

        XCTAssertEqual(plan, repeated)
        XCTAssertEqual(plan.completedCount, 6)
        XCTAssertEqual(plan.completedWaypointCount, CinematicPlanCompassPlan.completedWaypointLimit)
        XCTAssertEqual(plan.hiddenCompletedWaypointCount, 2)
        XCTAssertEqual(plan.historyStateIdentifier, "truncated")
        XCTAssertEqual(plan.latestWaypointStateIdentifier, "latest")
        XCTAssertEqual(plan.completedWaypoints.map(\.ordinal), [3, 4, 5, 6])
        XCTAssertEqual(plan.completedWaypoints.map(\.ordinalLabel), ["#3", "#4", "#5", "#6"])
        XCTAssertEqual(plan.completedWaypoints.map(\.stateIdentifier), ["history", "history", "history", "latest"])
        XCTAssertEqual(plan.latestCompletedWaypoint?.ordinalLabel, "#6")
        XCTAssertTrue(plan.completedWaypointStripIdentifier.contains("hidden:2"))
        XCTAssertTrue(plan.identifier.contains("history:"))
        XCTAssertTrue(plan.copyText.contains("History state: truncated"))
        XCTAssertTrue(plan.copyText.contains("#6 latest"))

        for waypoint in plan.completedWaypoints {
            XCTAssertFalse(waypoint.contentIdentifier.isEmpty)
            XCTAssertTrue(waypoint.copyIdentifier.hasPrefix("plan-compass.copy.waypoint"))
            XCTAssertTrue(waypoint.exportIdentifier.hasPrefix("plan-compass.export.waypoint"))
            XCTAssertLessThanOrEqual(
                waypoint.displayText.count,
                CinematicPlanCompassPlan.completedWaypointExcerptMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                waypoint.copyText.count,
                CinematicPlanCompassPlan.completedWaypointCopyMaxCharacters
            )
            XCTAssertTrue(waypoint.diagnosticsDetail.contains(waypoint.copyIdentifier))
            XCTAssertTrue(waypoint.diagnosticsDetail.contains(waypoint.exportIdentifier))
        }
    }

    func testEmptyCompletedHistoryUsesEmptyStateWithoutSyntheticWaypoints() {
        let plan = CinematicPlanCompassPlan(state: .empty)

        XCTAssertEqual(plan.completedWaypointCount, 0)
        XCTAssertEqual(plan.completedWaypoints, [])
        XCTAssertNil(plan.latestCompletedWaypoint)
        XCTAssertEqual(plan.hiddenCompletedWaypointCount, 0)
        XCTAssertEqual(plan.historyStateIdentifier, "empty")
        XCTAssertEqual(plan.latestWaypointStateIdentifier, "none")
        XCTAssertTrue(plan.completedWaypointStripIdentifier.contains("state:empty"))
        XCTAssertTrue(plan.completedWaypointCopyText.contains("Completed history: none"))
        XCTAssertTrue(plan.copyText.contains("History state: empty"))
    }

    func testSceneFocusDescriptorCarriesWaypointCorrelationWithoutChangingRouteSelection() throws {
        let completed = (1...5).map { "Completed scene focus waypoint \($0)" }
        let plan = CinematicPlanCompassPlan(state: makeState(completed: completed, midTerm: "Focus mid route"))
        let focus = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: plan,
            selectedKind: .midTerm
        )
        let descriptor = try XCTUnwrap(focus.descriptor)

        XCTAssertEqual(descriptor.selectedSectionRouteIdentifier, "mid-term")
        XCTAssertEqual(descriptor.selectedSectionRowIdentifier, plan.midTerm.rowIdentifier)
        XCTAssertEqual(descriptor.planIdentifier, plan.identifier)
        XCTAssertEqual(descriptor.planCopyIdentifier, plan.copyIdentifier)
        XCTAssertEqual(descriptor.planExportIdentifier, plan.exportIdentifier)
        XCTAssertEqual(descriptor.completedWaypointCount, plan.completedWaypointCount)
        XCTAssertEqual(descriptor.hiddenCompletedWaypointCount, plan.hiddenCompletedWaypointCount)
        XCTAssertEqual(descriptor.waypointHistoryStateIdentifier, plan.historyStateIdentifier)
        XCTAssertEqual(descriptor.waypointLatestStateIdentifier, plan.latestWaypointStateIdentifier)
        XCTAssertEqual(descriptor.completedWaypointIdentifiers, plan.completedWaypoints.map(\.contentIdentifier))
        XCTAssertEqual(descriptor.completedWaypointCopyIdentifiers, plan.completedWaypoints.map(\.copyIdentifier))
        XCTAssertEqual(descriptor.completedWaypointExportIdentifiers, plan.completedWaypoints.map(\.exportIdentifier))
        XCTAssertEqual(descriptor.latestCompletedWaypointID, plan.latestCompletedWaypoint?.contentIdentifier)
        XCTAssertEqual(descriptor.latestCompletedWaypointOrdinalLabel, "#5")
        XCTAssertTrue(descriptor.waypointRailIdentifier.contains("waypoints"))
        XCTAssertTrue(descriptor.diagnosticsIdentifier.contains("waypoints:\(plan.completedWaypointCount)"))
    }

    private func makeState(
        completed: [String],
        midTerm: String = "Queue history"
    ) -> PlanState {
        PlanState(
            completed: completed,
            immediate: PlanNext(plan: "Render plan compass history", verify: "swift test"),
            midTerm: midTerm,
            longTerm: "Keep completed work visible"
        )
    }
}
