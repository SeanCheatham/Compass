import Foundation
@testable import Compass
import XCTest

final class CinematicRecoveryCuePlanTests: XCTestCase {
    func testSelectsNewestActionableCueAndIgnoresNewerNonActionableCue() {
        let plan = CinematicRecoveryCuePlanner.plan(
            recentRunCues: [
                8: runCue(kind: .failedVerify, severity: .failure),
                10: runCue(kind: .resumeDevelop, severity: .paused),
                9: runCue(kind: .dirtyWorktree, severity: .warning)
            ],
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )

        XCTAssertEqual(plan.selectedCue?.sessionNumber, 9)
        XCTAssertEqual(plan.selectedCue?.kind, .dirtyWorktree)
        XCTAssertEqual(plan.selectedKindIdentifier, "dirtyWorktree")
        XCTAssertEqual(plan.visualDescriptor?.treatmentIdentifier, "dirty-cleanup")
        XCTAssertEqual(plan.visualDescriptor?.lightFamily, .edit)
        XCTAssertEqual(plan.visualDescriptor?.symbolIdentifier, "edit-amber-cleanup")
        XCTAssertFalse(plan.visualDescriptor?.shouldShakeCamera ?? true)
    }

    func testDistinctActionableVisualDescriptorsStayBounded() throws {
        let settings = CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity)
        let verify = try XCTUnwrap(
            CinematicRecoveryCuePlanner.plan(
                recentRunCues: [3: runCue(kind: .failedVerify, severity: .failure)],
                influenceSettings: settings
            ).visualDescriptor
        )
        let dirty = try XCTUnwrap(
            CinematicRecoveryCuePlanner.plan(
                recentRunCues: [4: runCue(kind: .dirtyWorktree, severity: .warning)],
                influenceSettings: settings
            ).visualDescriptor
        )
        let promotion = try XCTUnwrap(
            CinematicRecoveryCuePlanner.plan(
                recentRunCues: [5: runCue(kind: .promotionFailed, severity: .failure)],
                influenceSettings: settings
            ).visualDescriptor
        )

        XCTAssertEqual(verify.lightFamily, .failure)
        XCTAssertEqual(dirty.lightFamily, .edit)
        XCTAssertEqual(promotion.lightFamily, .git)
        let mutation = try XCTUnwrap(
            CinematicRecoveryCuePlanner.plan(
                recentRunCues: [6: runCue(kind: .mutationTestingRecovery, severity: .failure)],
                influenceSettings: settings
            ).visualDescriptor
        )

        XCTAssertEqual(Set([verify.symbolIdentifier, dirty.symbolIdentifier, mutation.symbolIdentifier, promotion.symbolIdentifier]).count, 4)
        XCTAssertGreaterThan(verify.fractureOpacity, dirty.fractureOpacity)
        XCTAssertGreaterThan(dirty.healingOpacity, verify.healingOpacity)
        XCTAssertGreaterThan(promotion.fractureSpread, verify.fractureSpread)
        XCTAssertTrue(verify.shouldShakeCamera)
        XCTAssertFalse(dirty.shouldShakeCamera)
        XCTAssertTrue(promotion.shouldShakeCamera)

        XCTAssertEqual(mutation.treatmentIdentifier, "mutation-recovery")
        XCTAssertEqual(mutation.lightFamily, .verify)
        XCTAssertEqual(mutation.symbolIdentifier, "mutation-red-testtube")
        XCTAssertTrue(mutation.shouldShakeCamera)

        for descriptor in [verify, dirty, mutation, promotion] {
            XCTAssertInRange(descriptor.intensity, CinematicRecoveryCuePlan.intensityRange)
            XCTAssertInRange(descriptor.phaseLightIntensity, CinematicRecoveryCuePlan.phaseLightIntensityRange)
            XCTAssertInRange(descriptor.fractureOpacity, CinematicRecoveryCuePlan.fractureOpacityRange)
            XCTAssertInRange(descriptor.fractureSpread, CinematicRecoveryCuePlan.fractureSpreadRange)
            XCTAssertInRange(descriptor.healingOpacity, CinematicRecoveryCuePlan.healingOpacityRange)
            XCTAssertInRange(descriptor.cameraShakeScale, CinematicTuning.cameraShakeScaleRange)
            XCTAssertInRange(descriptor.cameraShakeDuration, CinematicStageEffectPlan.cameraShakeDurationRange)
            XCTAssertFalse(descriptor.identifier.isEmpty)
        }
    }

    func testRepresentativePlansAreDeterministicAndCoverAllCueKinds() {
        let first = CinematicRecoveryCuePlanner.representativePlans()
        let repeated = CinematicRecoveryCuePlanner.representativePlans()

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(
            first.map(\.selectedKindIdentifier),
            ["none", "failedVerify", "dirtyWorktree", "mutationTestingRecovery", "promotionFailed"]
        )
        XCTAssertEqual(
            first.map { $0.visualDescriptor?.treatmentIdentifier ?? "none" },
            ["none", "verify-failure", "dirty-cleanup", "mutation-recovery", "promotion-branch"]
        )
    }
}

private func runCue(
    kind: PlanReliabilityFeedback.Kind,
    severity: PlanReliabilityFeedback.Severity
) -> PlanReliabilityFeedback.RunCue {
    PlanReliabilityFeedback.RunCue(
        notice: PlanReliabilityFeedback.Notice(
            id: "\(kind.rawValue)-test",
            kind: kind,
            severity: severity,
            sessionNumber: 0,
            title: "\(kind.rawValue) title",
            detail: "\(kind.rawValue) detail",
            actionLabel: "\(kind.rawValue) action",
            metadata: nil,
            systemImage: systemImage(for: kind)
        )
    )
}

private func systemImage(for kind: PlanReliabilityFeedback.Kind) -> String {
    switch kind {
    case .failedVerify:
        return "checkmark.seal.fill"
    case .mutationTestingRecovery:
        return "testtube.2"
    case .dirtyWorktree:
        return "pencil.and.outline"
    case .promotionFailed:
        return "arrow.triangle.branch"
    case .rejectedPlan, .developBlocked, .developFailed, .resumeDevelop:
        return "questionmark"
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
