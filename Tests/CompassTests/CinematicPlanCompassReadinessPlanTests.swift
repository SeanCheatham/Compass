import Foundation
@testable import Compass
import XCTest

final class CinematicPlanCompassReadinessPlanTests: XCTestCase {
    func testBuildsDeterministicBoundedReadyDescriptor() {
        let state = readyState
        let plan = CinematicPlanCompassPlan(state: state)
        let feedback = PlanReliabilityFeedback(state: state, sessions: [])
        let readiness = CinematicPlanCompassReadinessPlan(
            state: state,
            planCompassPlan: plan,
            reliabilityFeedback: feedback
        )
        let repeated = CinematicPlanCompassReadinessPlan(
            state: state,
            planCompassPlan: plan,
            reliabilityFeedback: feedback
        )

        XCTAssertEqual(readiness, repeated)
        XCTAssertEqual(readiness.rowIdentifier, "plan-compass-readiness")
        XCTAssertEqual(readiness.sourcePlanIdentifier, plan.identifier)
        XCTAssertEqual(readiness.sourceImmediateContentIdentifier, plan.immediate.contentIdentifier)
        XCTAssertEqual(readiness.statusIdentifier, "ready")
        XCTAssertEqual(readiness.warningStateIdentifier, "clear")
        XCTAssertEqual(readiness.metadataStateIdentifier, "complete")
        XCTAssertEqual(readiness.verifyCommandStateIdentifier, "available")
        XCTAssertEqual(readiness.timeoutStateIdentifier, "available")
        XCTAssertEqual(readiness.difficultyStateIdentifier, "available")
        XCTAssertEqual(readiness.retryCueStateIdentifier, "clear")
        XCTAssertEqual(readiness.verifyCommand, "swift test --filter CinematicPlanCompassReadinessPlanTests")
        XCTAssertEqual(readiness.verifyTimeoutLabel, "Timeout 2m")
        XCTAssertEqual(readiness.estimatedDifficultyLabel, "Medium")
        XCTAssertTrue(readiness.verifyCommandLabel.contains("CinematicPlanCompassReadinessPlanTests"))
        XCTAssertTrue(readiness.focusRingCopy.contains("Ready for Develop"))
        XCTAssertTrue(readiness.focusRingCopy.contains("swift test"))
        XCTAssertTrue(readiness.copyIdentifier.hasPrefix("plan-compass-readiness.copy"))
        XCTAssertTrue(readiness.exportIdentifier.hasPrefix("plan-compass-readiness.export"))
        XCTAssertLessThanOrEqual(readiness.identifier.count, CinematicPlanCompassReadinessPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(readiness.label.count, CinematicPlanCompassReadinessPlan.labelMaxCharacters)
        XCTAssertLessThanOrEqual(readiness.detailText.count, CinematicPlanCompassReadinessPlan.detailMaxCharacters)
        XCTAssertLessThanOrEqual(readiness.focusRingCopy.count, CinematicPlanCompassReadinessPlan.focusRingCopyMaxCharacters)
        XCTAssertLessThanOrEqual(readiness.copyText.count, CinematicPlanCompassReadinessPlan.copyTextMaxCharacters)
        XCTAssertLessThanOrEqual(
            readiness.diagnosticsDetail.count,
            CinematicPlanCompassReadinessPlan.diagnosticsDetailMaxCharacters
        )
    }

    func testWarningStatesCoverNoImmediateMissingMetadataAndRetryCues() {
        let noImmediateState = PlanState(completed: [], immediate: nil, midTerm: "", longTerm: "")
        let noImmediatePlan = CinematicPlanCompassPlan(state: noImmediateState)
        let noImmediate = CinematicPlanCompassReadinessPlan(
            state: noImmediateState,
            planCompassPlan: noImmediatePlan,
            reliabilityFeedback: PlanReliabilityFeedback(state: noImmediateState, sessions: [])
        )

        XCTAssertEqual(noImmediate.statusIdentifier, "no-immediate")
        XCTAssertEqual(noImmediate.warningStateIdentifier, "warning")
        XCTAssertEqual(noImmediate.metadataStateIdentifier, "none")
        XCTAssertEqual(noImmediate.warningIdentifiers, ["plan-compass-readiness.no-immediate"])
        XCTAssertNil(noImmediate.verifyCommand)

        let missingMetadataState = PlanState(
            completed: ["Captured partial metadata"],
            immediate: PlanNext(
                plan: "Fill in missing readiness metadata",
                verify: "swift test --filter CinematicPlanCompassReadinessPlanTests"
            ),
            midTerm: "",
            longTerm: ""
        )
        let missingMetadataPlan = CinematicPlanCompassPlan(state: missingMetadataState)
        let missingMetadata = CinematicPlanCompassReadinessPlan(
            state: missingMetadataState,
            planCompassPlan: missingMetadataPlan,
            reliabilityFeedback: PlanReliabilityFeedback(state: missingMetadataState, sessions: [])
        )

        XCTAssertEqual(missingMetadata.statusIdentifier, "missing-metadata")
        XCTAssertEqual(missingMetadata.warningStateIdentifier, "warning")
        XCTAssertEqual(missingMetadata.metadataStateIdentifier, "missing")
        XCTAssertEqual(missingMetadata.timeoutStateIdentifier, "missing")
        XCTAssertEqual(missingMetadata.difficultyStateIdentifier, "missing")
        XCTAssertTrue(missingMetadata.warningIdentifiers.contains("plan-compass-readiness.missing-timeout"))
        XCTAssertTrue(missingMetadata.warningIdentifiers.contains("plan-compass-readiness.missing-difficulty"))
        XCTAssertEqual(missingMetadata.verifyTimeoutLabel, "Default timeout 10m")

        let retryState = readyState
        let retryPlan = CinematicPlanCompassPlan(state: retryState)
        let retryFeedback = PlanReliabilityFeedback(
            state: retryState,
            sessions: [makeFailedVerifySession()]
        )
        let retry = CinematicPlanCompassReadinessPlan(
            state: retryState,
            planCompassPlan: retryPlan,
            reliabilityFeedback: retryFeedback
        )

        XCTAssertEqual(retry.statusIdentifier, "retry-cue")
        XCTAssertEqual(retry.warningStateIdentifier, "warning")
        XCTAssertEqual(retry.retryCueStateIdentifier, "active")
        XCTAssertEqual(retry.metadataStateIdentifier, "complete")
        XCTAssertTrue(retry.warningIdentifiers.contains("plan-compass-readiness.retry-cue"))
        XCTAssertTrue(retry.retryCueIdentifiers.contains("notice.failedVerify.7"))
        XCTAssertTrue(retry.retryCueIdentifiers.contains("run.failedVerify.7"))
    }

    func testImmediateFocusDescriptorIncludesReadinessStatusAndVerifyCommand() throws {
        let state = readyState
        let plan = CinematicPlanCompassPlan(state: state)
        let readiness = CinematicPlanCompassReadinessPlan(
            state: state,
            planCompassPlan: plan,
            reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: [])
        )
        let immediateFocus = try XCTUnwrap(
            CinematicPlanCompassSceneFocusPlanner.plan(
                isPlanOverlaySelected: true,
                planCompassPlan: plan,
                readinessPlan: readiness,
                selectedKind: .immediate
            ).descriptor
        )
        let midTermFocus = try XCTUnwrap(
            CinematicPlanCompassSceneFocusPlanner.plan(
                isPlanOverlaySelected: true,
                planCompassPlan: plan,
                readinessPlan: readiness,
                selectedKind: .midTerm
            ).descriptor
        )

        XCTAssertEqual(immediateFocus.readinessIdentifier, readiness.identifier)
        XCTAssertEqual(immediateFocus.readinessStatusIdentifier, "ready")
        XCTAssertEqual(immediateFocus.readinessWarningStateIdentifier, "clear")
        XCTAssertEqual(immediateFocus.readinessVerifyCommand, readiness.verifyCommand)
        XCTAssertEqual(immediateFocus.verifySealDescriptor?.readinessIdentifier, readiness.identifier)
        XCTAssertEqual(immediateFocus.verifySealDescriptor?.statusIdentifier, "ready")
        XCTAssertTrue(immediateFocus.plaqueStatus.contains("Ready for Develop"))
        XCTAssertEqual(immediateFocus.ringCopy, readiness.focusRingCopy)
        XCTAssertTrue(immediateFocus.ringCopy.contains("swift test"))
        XCTAssertLessThanOrEqual(immediateFocus.ringCopy.count, CinematicPlanCompassSceneFocusPlan.ringCopyMaxCharacters)

        XCTAssertNil(midTermFocus.readinessIdentifier)
        XCTAssertNil(midTermFocus.readinessStatusIdentifier)
        XCTAssertNil(midTermFocus.verifySealDescriptor)
        XCTAssertFalse(midTermFocus.ringCopy.contains("Ready for Develop"))
    }

    private var readyState: PlanState {
        PlanState(
            completed: ["Mapped readiness descriptors", "Rendered readiness strip"],
            immediate: PlanNext(
                plan: "Expose the next Develop pass readiness",
                verify: "swift test --filter CinematicPlanCompassReadinessPlanTests",
                verifyTimeoutMs: 120_000,
                estimatedDifficulty: .medium
            ),
            midTerm: "Keep Plan Compass readiness in diagnostics",
            longTerm: "Make autonomous factory state legible"
        )
    }

    private func makeFailedVerifySession() -> SessionRecord {
        SessionRecord(
            session: 7,
            startedAt: 7_000,
            endedAt: 7_500,
            plan: "Expose readiness",
            verify: "swift test --filter CinematicPlanCompassReadinessPlanTests",
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: .failed,
            notes: [],
            verifyOutput: VerifyOutput(
                command: "swift test --filter CinematicPlanCompassReadinessPlanTests",
                exitCode: 65,
                tail: "Readiness verify failed"
            ),
            feedback: nil
        )
    }
}
