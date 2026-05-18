import Foundation
@testable import Compass
import XCTest

final class CinematicPlanCompassSceneFocusPlanTests: XCTestCase {
    func testBuildsDeterministicBoundedActiveDescriptor() throws {
        let longPlan = Array(
            repeating: "Thread a compact in-world plan compass plaque through RealityKit without mutating project state.",
            count: 6
        ).joined(separator: " ")
        let state = PlanState(
            completed: ["Mapped diagnostics", "Rendered plan overlay"],
            immediate: PlanNext(
                plan: longPlan,
                verify: "swift test --filter CinematicPlanCompassSceneFocusPlanTests",
                verifyTimeoutMs: 90_000,
                estimatedDifficulty: .high
            ),
            midTerm: "Queue plan focus polish",
            longTerm: "Make waiting time legible"
        )
        let planCompass = CinematicPlanCompassPlan(state: state)
        let focus = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: planCompass
        )
        let repeated = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: planCompass
        )
        let descriptor = try XCTUnwrap(focus.descriptor)

        XCTAssertEqual(focus, repeated)
        XCTAssertTrue(focus.isActive)
        XCTAssertEqual(descriptor.planIdentifier, planCompass.identifier)
        XCTAssertEqual(descriptor.planCopyIdentifier, planCompass.copyIdentifier)
        XCTAssertEqual(descriptor.planExportIdentifier, planCompass.exportIdentifier)
        XCTAssertEqual(descriptor.selectedSectionID, planCompass.immediate.id)
        XCTAssertEqual(descriptor.selectedSectionRouteIdentifier, "immediate")
        XCTAssertEqual(descriptor.selectedSectionRowIdentifier, planCompass.immediate.rowIdentifier)
        XCTAssertEqual(descriptor.selectedSectionCopyIdentifier, planCompass.immediate.copyIdentifier)
        XCTAssertEqual(descriptor.selectedSectionExportIdentifier, planCompass.immediate.exportIdentifier)
        XCTAssertEqual(descriptor.selectedSectionStateIdentifier, "active")
        XCTAssertFalse(descriptor.selectedSectionIsEmpty)
        XCTAssertFalse(descriptor.usesFallbackSection)
        XCTAssertEqual(descriptor.cameraShot, .castPrep)
        XCTAssertEqual(descriptor.lightFamily, .scan)
        XCTAssertEqual(descriptor.arenaEffect, .seal)
        XCTAssertInRange(descriptor.lookTarget.x, CinematicPlanCompassSceneFocusPlan.targetXRange)
        XCTAssertInRange(descriptor.lookTarget.y, CinematicPlanCompassSceneFocusPlan.targetYRange)
        XCTAssertInRange(descriptor.lookTarget.z, CinematicPlanCompassSceneFocusPlan.targetZRange)
        XCTAssertLessThanOrEqual(descriptor.identifier.count, CinematicPlanCompassSceneFocusPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(descriptor.plaqueTitle.count, CinematicPlanCompassSceneFocusPlan.plaqueTitleMaxCharacters)
        XCTAssertLessThanOrEqual(descriptor.plaqueDetail.count, CinematicPlanCompassSceneFocusPlan.plaqueDetailMaxCharacters)
        XCTAssertLessThanOrEqual(descriptor.plaqueStatus.count, CinematicPlanCompassSceneFocusPlan.plaqueStatusMaxCharacters)
        XCTAssertLessThanOrEqual(descriptor.ringCopy.count, CinematicPlanCompassSceneFocusPlan.ringCopyMaxCharacters)
        XCTAssertEqual(descriptor.triadIdentifiers.count, 3)
        XCTAssertEqual(descriptor.diagnosticsRowIdentifier, "plan-compass-focus")
        XCTAssertTrue(descriptor.diagnosticsIdentifier.contains("route:immediate"))
    }

    func testPlanOverlayActivationGatesFocusWithoutDroppingCandidateDeterminism() throws {
        let planCompass = CinematicPlanCompassPlan(state: .empty)
        let inactive = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: false,
            planCompassPlan: planCompass
        )
        let active = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: planCompass
        )

        XCTAssertFalse(inactive.isActive)
        XCTAssertNil(inactive.descriptor)
        XCTAssertEqual(inactive.identifier, "plan-compass-focus.none")
        XCTAssertTrue(active.isActive)
        XCTAssertEqual(active.descriptor?.selectedSectionStateIdentifier, "empty")
    }

    func testEmptyImmediateMidTermAndLongTermFallbackTargeting() throws {
        let midTermState = PlanState(
            completed: [],
            immediate: nil,
            midTerm: "Queue the plan compass fallback route",
            longTerm: "Long-term route"
        )
        let longTermState = PlanState(
            completed: [],
            immediate: nil,
            midTerm: "",
            longTerm: "Long-term destination route"
        )
        let emptyState = PlanState.empty

        let mid = try XCTUnwrap(focusDescriptor(for: midTermState))
        let long = try XCTUnwrap(focusDescriptor(for: longTermState))
        let empty = try XCTUnwrap(focusDescriptor(for: emptyState))

        XCTAssertEqual(mid.selectedSectionRouteIdentifier, "mid-term")
        XCTAssertTrue(mid.usesFallbackSection)
        XCTAssertEqual(mid.cameraShot, .wide)
        XCTAssertEqual(mid.lightFamily, .insight)
        XCTAssertEqual(mid.arenaEffect, .activityPulse)

        XCTAssertEqual(long.selectedSectionRouteIdentifier, "long-term")
        XCTAssertTrue(long.usesFallbackSection)
        XCTAssertEqual(long.cameraShot, .overhead)
        XCTAssertEqual(long.lightFamily, .verify)
        XCTAssertEqual(long.arenaEffect, .historyChains)

        XCTAssertEqual(empty.selectedSectionRouteIdentifier, "immediate")
        XCTAssertTrue(empty.selectedSectionIsEmpty)
        XCTAssertFalse(empty.usesFallbackSection)
        XCTAssertEqual(empty.cameraShot, .home)
        XCTAssertEqual(empty.lightFamily, .lifecycle)
        XCTAssertEqual(empty.arenaEffect, .activityPulse)
        XCTAssertNotEqual(mid.lookTarget, long.lookTarget)
        XCTAssertNotEqual(long.lookTarget, empty.lookTarget)
    }

    func testExplicitSelectedRouteOverridesFallbackAcrossActiveAndEmptySections() throws {
        let state = PlanState(
            completed: [],
            immediate: nil,
            midTerm: "Focus an explicitly selected mid-term route",
            longTerm: ""
        )
        let planCompass = CinematicPlanCompassPlan(state: state)
        let mid = try XCTUnwrap(
            CinematicPlanCompassSceneFocusPlanner.plan(
                isPlanOverlaySelected: true,
                planCompassPlan: planCompass,
                selectedKind: .midTerm
            ).descriptor
        )
        let emptyLong = try XCTUnwrap(
            CinematicPlanCompassSceneFocusPlanner.plan(
                isPlanOverlaySelected: true,
                planCompassPlan: planCompass,
                selectedKind: .longTerm
            ).descriptor
        )

        XCTAssertEqual(mid.selectedSectionRouteIdentifier, "mid-term")
        XCTAssertEqual(mid.selectedSectionRowIdentifier, planCompass.midTerm.rowIdentifier)
        XCTAssertEqual(mid.selectedSectionCopyIdentifier, planCompass.midTerm.copyIdentifier)
        XCTAssertEqual(mid.selectedSectionExportIdentifier, planCompass.midTerm.exportIdentifier)
        XCTAssertFalse(mid.selectedSectionIsEmpty)
        XCTAssertFalse(mid.usesFallbackSection)
        XCTAssertEqual(mid.cameraShot, .wide)

        XCTAssertEqual(emptyLong.selectedSectionRouteIdentifier, "long-term")
        XCTAssertEqual(emptyLong.selectedSectionRowIdentifier, planCompass.longTerm.rowIdentifier)
        XCTAssertEqual(emptyLong.selectedSectionStateIdentifier, "empty")
        XCTAssertTrue(emptyLong.selectedSectionIsEmpty)
        XCTAssertFalse(emptyLong.usesFallbackSection)
        XCTAssertEqual(emptyLong.cameraShot, .home)
    }

    func testPlanningIsReadOnlyOverPlanState() throws {
        let state = PlanState(
            completed: ["Read-only"],
            immediate: PlanNext(plan: "Render focus", verify: "swift test"),
            midTerm: "Queue",
            longTerm: "Arc"
        )
        let planCompass = CinematicPlanCompassPlan(state: state)
        let before = planCompass

        _ = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: planCompass
        )

        XCTAssertEqual(planCompass, before)
    }

    private func focusDescriptor(
        for state: PlanState
    ) -> CinematicPlanCompassSceneFocusPlan.Descriptor? {
        CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: CinematicPlanCompassPlan(state: state)
        ).descriptor
    }
}

private func XCTAssertInRange<T: Comparable>(
    _ value: T,
    _ range: ClosedRange<T>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(value, range.lowerBound, file: file, line: line)
    XCTAssertLessThanOrEqual(value, range.upperBound, file: file, line: line)
}
