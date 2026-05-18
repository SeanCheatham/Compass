import Foundation
@testable import Compass
import XCTest

final class CinematicPlanCompassPlanTests: XCTestCase {
    func testBuildsDeterministicDescriptorsWithBoundedMetadataAndCopy() {
        let longDirection = Array(
            repeating: "Thread a polished plan compass through the cinematic overlay and diagnostics export.",
            count: 8
        ).joined(separator: " ")
        let state = PlanState(
            completed: ["Stabilized diagnostics", "Added overlay policy"],
            immediate: PlanNext(
                plan: " \(longDirection) ",
                verify: " swift test --filter CinematicPlanCompassPlanTests ",
                verifyTimeoutMs: 90_000,
                estimatedDifficulty: .high
            ),
            midTerm: "Queue: \(longDirection)",
            longTerm: "Arc: \(longDirection)"
        )

        let plan = CinematicPlanCompassPlan(state: state)
        let repeated = CinematicPlanCompassPlan(state: state)

        XCTAssertEqual(plan, repeated)
        XCTAssertEqual(plan.completedCount, 2)
        XCTAssertEqual(plan.completedLabel, "2 completed iterations")
        XCTAssertEqual(
            plan.sections.map(\.rowIdentifier),
            ["plan-compass-immediate", "plan-compass-mid-term", "plan-compass-long-term"]
        )
        XCTAssertEqual(plan.sections.map(\.directionLabel), [
            "Immediate direction",
            "Mid-term direction",
            "Long-term direction"
        ])
        XCTAssertTrue(plan.identifier.contains("completed:2"))
        XCTAssertTrue(plan.copyIdentifier.hasPrefix("plan-compass.copy|"))
        XCTAssertTrue(plan.exportIdentifier.hasPrefix("plan-compass.export|"))

        XCTAssertEqual(plan.immediate.verifyCommand, "swift test --filter CinematicPlanCompassPlanTests")
        XCTAssertEqual(plan.immediate.verifyTimeoutLabel, "Timeout 90s")
        XCTAssertEqual(plan.immediate.estimatedDifficultyLabel, "High")
        XCTAssertTrue(plan.immediate.metadataSummary.contains("difficulty high"))
        XCTAssertTrue(plan.immediate.metadataSummary.contains("verify Timeout 90s"))
        XCTAssertTrue(plan.immediate.metadataSummary.contains("command swift test --filter CinematicPlanCompassPlanTests"))

        for section in plan.sections {
            XCTAssertFalse(section.contentIdentifier.isEmpty)
            XCTAssertFalse(section.copyIdentifier.isEmpty)
            XCTAssertFalse(section.exportIdentifier.isEmpty)
            XCTAssertLessThanOrEqual(
                section.displayText.count,
                CinematicPlanCompassPlan.sectionExcerptMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                section.copyText.count,
                CinematicPlanCompassPlan.sectionCopyMaxCharacters
            )
            XCTAssertFalse(section.displayText.contains("diagnostics export. diagnostics export. diagnostics export."))
        }
        XCTAssertLessThanOrEqual(plan.copyText.count, CinematicPlanCompassPlan.copyTextMaxCharacters)
    }

    func testEmptyStateLabelsCoverImmediateMidTermAndLongTermFallbacks() {
        let plan = CinematicPlanCompassPlan(state: .empty)

        XCTAssertEqual(plan.completedLabel, "No completed iterations")
        XCTAssertEqual(plan.sections.map(\.stateIdentifier), ["empty", "empty", "empty"])
        XCTAssertEqual(plan.sections.map(\.emptyStateLabel), [
            "No immediate direction",
            "No mid-term direction",
            "No long-term direction"
        ])
        XCTAssertEqual(
            plan.immediate.displayText,
            "No immediate plan. The factory is ready for the next scoped implementation."
        )
        XCTAssertEqual(
            plan.midTerm.displayText,
            "No mid-term queue. Future planning has no staged direction yet."
        )
        XCTAssertEqual(
            plan.longTerm.displayText,
            "No long-term arc. Add the larger product direction when it becomes clear."
        )
        XCTAssertNil(plan.immediate.bodyExcerpt)
        XCTAssertNil(plan.midTerm.bodyExcerpt)
        XCTAssertNil(plan.longTerm.bodyExcerpt)
        XCTAssertTrue(plan.copyText.contains("No immediate plan"))
        XCTAssertTrue(plan.copyText.contains("No mid-term queue"))
        XCTAssertTrue(plan.copyText.contains("No long-term arc"))
    }
}
