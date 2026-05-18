import Foundation
@testable import Compass
import XCTest

final class CinematicPlanCompassVerifySealPlanTests: XCTestCase {
    func testBuildsDeterministicBoundedReadySealFromReadinessAndImmediateFocus() throws {
        let state = readyState
        let plan = CinematicPlanCompassPlan(state: state)
        let readiness = CinematicPlanCompassReadinessPlan(
            state: state,
            planCompassPlan: plan,
            reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: [])
        )
        let focus = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: plan,
            readinessPlan: readiness,
            selectedKind: .immediate
        )
        let repeatedFocus = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: plan,
            readinessPlan: readiness,
            selectedKind: .immediate
        )
        let focusDescriptor = try XCTUnwrap(focus.descriptor)
        let seal = try XCTUnwrap(focusDescriptor.verifySealDescriptor)
        let repeatedSeal = try XCTUnwrap(repeatedFocus.descriptor?.verifySealDescriptor)

        XCTAssertEqual(seal, repeatedSeal)
        XCTAssertEqual(seal.rowIdentifier, "plan-compass-verify-seal")
        XCTAssertEqual(seal.readinessIdentifier, readiness.identifier)
        XCTAssertEqual(seal.readinessStatusIdentifier, "ready")
        XCTAssertEqual(seal.focusDescriptorIdentifier, focusDescriptor.identifier)
        XCTAssertEqual(seal.focusDiagnosticsIdentifier, focusDescriptor.diagnosticsIdentifier)
        XCTAssertEqual(seal.focusRowIdentifier, "plan-compass-focus")
        XCTAssertEqual(seal.sourcePlanIdentifier, plan.identifier)
        XCTAssertEqual(seal.immediateContentIdentifier, plan.immediate.contentIdentifier)
        XCTAssertEqual(seal.selectedSectionRouteIdentifier, "immediate")
        XCTAssertEqual(seal.statusIdentifier, "ready")
        XCTAssertEqual(seal.treatmentIdentifier, "verify-seal.ready-ring")
        XCTAssertEqual(seal.warningStateIdentifier, "clear")
        XCTAssertEqual(seal.metadataStateIdentifier, "complete")
        XCTAssertEqual(seal.verifyCommandStateIdentifier, "available")
        XCTAssertEqual(seal.timeoutStateIdentifier, "available")
        XCTAssertEqual(seal.difficultyStateIdentifier, "available")
        XCTAssertEqual(seal.retryCueStateIdentifier, "clear")
        XCTAssertEqual(seal.completedCount, plan.completedCount)
        XCTAssertEqual(seal.completedLabel, plan.completedLabel)
        XCTAssertEqual(seal.tintIdentifier, "verify")
        XCTAssertTrue(seal.verifyCommandHashIdentifier.hasPrefix("verify:"))
        XCTAssertFalse(seal.verifyCommandHashIdentifier.contains("swift test"))
        XCTAssertTrue(seal.compactCopy.contains("Ready"))
        XCTAssertTrue(seal.segmentIdentifiers.contains("plan-compass-verify-seal.segment.ready"))
        XCTAssertLessThanOrEqual(seal.identifier.count, CinematicPlanCompassVerifySealPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(seal.copyIdentifier.count, CinematicPlanCompassVerifySealPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(seal.exportIdentifier.count, CinematicPlanCompassVerifySealPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(seal.diagnosticsIdentifier.count, CinematicPlanCompassVerifySealPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(seal.displayTitle.count, CinematicPlanCompassVerifySealPlan.displayTitleMaxCharacters)
        XCTAssertLessThanOrEqual(seal.displayDetail.count, CinematicPlanCompassVerifySealPlan.displayDetailMaxCharacters)
        XCTAssertLessThanOrEqual(seal.compactCopy.count, CinematicPlanCompassVerifySealPlan.compactCopyMaxCharacters)
        XCTAssertLessThanOrEqual(
            seal.diagnosticsDetail.count,
            CinematicPlanCompassVerifySealPlan.diagnosticsDetailMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            seal.segmentIdentifiers.count,
            CinematicPlanCompassVerifySealPlan.segmentIdentifierLimit
        )
    }

    func testSealCoversAllReadinessStatusTreatmentsAndDisplayCopy() throws {
        let cases: [(String, PlanState, [SessionRecord], String, String)] = [
            ("ready", readyState, [], "verify-seal.ready-ring", "Ready"),
            ("no-immediate", noImmediateState, [], "verify-seal.empty-target", "No immediate plan"),
            ("missing-metadata", missingMetadataState, [], "verify-seal.metadata-segments", "Metadata needed"),
            (
                "retry-cue",
                retryState,
                [makeFailedVerifySession()],
                "verify-seal.retry-braces",
                "Retry cue"
            )
        ]

        for (status, state, sessions, treatment, copyFragment) in cases {
            let plan = CinematicPlanCompassPlan(state: state)
            let readiness = CinematicPlanCompassReadinessPlan(
                state: state,
                planCompassPlan: plan,
                reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: sessions)
            )
            let focus = CinematicPlanCompassSceneFocusPlanner.plan(
                isPlanOverlaySelected: true,
                planCompassPlan: plan,
                readinessPlan: readiness,
                selectedKind: .immediate
            )
            let seal = try XCTUnwrap(
                focus.descriptor?.verifySealDescriptor,
                "missing seal for \(status)"
            )

            XCTAssertEqual(seal.statusIdentifier, status)
            XCTAssertEqual(seal.treatmentIdentifier, treatment)
            XCTAssertEqual(seal.warningStateIdentifier, readiness.warningStateIdentifier)
            XCTAssertEqual(seal.metadataStateIdentifier, readiness.metadataStateIdentifier)
            XCTAssertEqual(seal.verifyCommandStateIdentifier, readiness.verifyCommandStateIdentifier)
            XCTAssertEqual(seal.timeoutStateIdentifier, readiness.timeoutStateIdentifier)
            XCTAssertEqual(seal.difficultyStateIdentifier, readiness.difficultyStateIdentifier)
            XCTAssertEqual(seal.retryCueStateIdentifier, readiness.retryCueStateIdentifier)
            XCTAssertTrue(seal.compactCopy.contains(copyFragment))
            XCTAssertFalse(seal.segmentIdentifiers.isEmpty)
        }
    }

    func testSealThreadsThroughImmediateFocusOnly() throws {
        let state = readyState
        let plan = CinematicPlanCompassPlan(state: state)
        let readiness = CinematicPlanCompassReadinessPlan(
            state: state,
            planCompassPlan: plan,
            reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: [])
        )

        let immediate = try XCTUnwrap(
            CinematicPlanCompassSceneFocusPlanner.plan(
                isPlanOverlaySelected: true,
                planCompassPlan: plan,
                readinessPlan: readiness,
                selectedKind: .immediate
            ).descriptor
        )
        let midTerm = try XCTUnwrap(
            CinematicPlanCompassSceneFocusPlanner.plan(
                isPlanOverlaySelected: true,
                planCompassPlan: plan,
                readinessPlan: readiness,
                selectedKind: .midTerm
            ).descriptor
        )
        let longTerm = try XCTUnwrap(
            CinematicPlanCompassSceneFocusPlanner.plan(
                isPlanOverlaySelected: true,
                planCompassPlan: plan,
                readinessPlan: readiness,
                selectedKind: .longTerm
            ).descriptor
        )

        XCTAssertNotNil(immediate.verifySealDescriptor)
        XCTAssertNil(midTerm.verifySealDescriptor)
        XCTAssertNil(longTerm.verifySealDescriptor)
        XCTAssertNil(midTerm.readinessIdentifier)
        XCTAssertNil(longTerm.readinessIdentifier)
        XCTAssertEqual(midTerm.selectedSectionRouteIdentifier, "mid-term")
        XCTAssertEqual(longTerm.selectedSectionRouteIdentifier, "long-term")
    }

    func testDiagnosticsExportAndSmokeExposeSealWithoutMutatingInputs() throws {
        let state = readyState
        let plan = CinematicPlanCompassPlan(state: state)
        let readiness = CinematicPlanCompassReadinessPlan(
            state: state,
            planCompassPlan: plan,
            reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: [])
        )
        let focus = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: plan,
            readinessPlan: readiness,
            selectedKind: .immediate
        )
        let stateBefore = state
        let planBefore = plan
        let readinessBefore = readiness
        let focusBefore = focus

        let report = CinematicDiagnostics.report(
            repoName: "Verify Seal Diagnostics",
            phase: LoopPhase.planning.rawValue,
            immediateTitle: state.immediate?.plan ?? "",
            completedCount: state.completed.count,
            planCompassPlan: plan,
            planCompassReadinessPlan: readiness,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(),
            influenceSettings: CinematicInfluenceSettings(),
            isRunning: false,
            hasExplicitUserFocus: true,
            planCompassSceneFocusPlan: focus
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport.representative()
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "plan-compass-verify-seal" })
        let smokeCheck = try XCTUnwrap(
            summary.visualSmoke.checks.first { $0.id == "plan-compass-verify-seal" }
        )

        XCTAssertEqual(state, stateBefore)
        XCTAssertEqual(plan, planBefore)
        XCTAssertEqual(readiness, readinessBefore)
        XCTAssertEqual(focus, focusBefore)
        XCTAssertTrue(report.planCompassVerifySeal.isVisible)
        XCTAssertEqual(report.planCompassVerifySeal.readinessIdentifier, readiness.identifier)
        XCTAssertEqual(report.planCompassVerifySeal.focusDescriptorIdentifier, focus.descriptor?.identifier)
        XCTAssertEqual(report.planCompassVerifySeal.statusIdentifier, "ready")
        XCTAssertEqual(row.label, "Verify seal")
        XCTAssertLessThanOrEqual(row.detail.count, CinematicDiagnosticsSummary.detailMaxCharacters)
        XCTAssertTrue(summary.exportText.contains("Verify seal"))
        XCTAssertTrue(summary.exportText.contains("plan-compass-verify-seal"))
        XCTAssertEqual(smokeCheck.status, .pass)
        XCTAssertTrue(smokeCheck.detail.contains("ready"))
        XCTAssertTrue(smokeCheck.detail.contains("retry-cue"))
        XCTAssertTrue(smokeCheck.detail.contains("missing-metadata"))
        XCTAssertTrue(smokeCheck.detail.contains("no-immediate"))
        XCTAssertTrue(smokeCheck.detail.contains("correlated"))
        XCTAssertTrue(smokeCheck.detail.contains("bounded"))
    }

    private var readyState: PlanState {
        PlanState(
            completed: ["Mapped readiness descriptors", "Rendered readiness strip"],
            immediate: PlanNext(
                plan: "Expose the next Develop pass readiness",
                verify: "swift test --filter CinematicPlanCompassVerifySealPlanTests",
                verifyTimeoutMs: 120_000,
                estimatedDifficulty: .medium
            ),
            midTerm: "Keep Plan Compass readiness in diagnostics",
            longTerm: "Make autonomous factory state legible"
        )
    }

    private var noImmediateState: PlanState {
        PlanState(completed: [], immediate: nil, midTerm: "Queue plan selection", longTerm: "")
    }

    private var missingMetadataState: PlanState {
        PlanState(
            completed: ["Captured partial metadata"],
            immediate: PlanNext(
                plan: "Fill in missing readiness metadata",
                verify: "swift test --filter CinematicPlanCompassVerifySealPlanTests"
            ),
            midTerm: "",
            longTerm: ""
        )
    }

    private var retryState: PlanState {
        PlanState(
            completed: ["Observed failed verify"],
            immediate: PlanNext(
                plan: "Retry after a failed verify cue",
                verify: "swift test --filter CinematicPlanCompassVerifySealPlanTests",
                verifyTimeoutMs: 90_000,
                estimatedDifficulty: .high
            ),
            midTerm: "",
            longTerm: ""
        )
    }

    private func makeFailedVerifySession() -> SessionRecord {
        SessionRecord(
            session: 9,
            startedAt: 9_000,
            endedAt: 9_500,
            plan: "Expose seal",
            verify: "swift test --filter CinematicPlanCompassVerifySealPlanTests",
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: .failed,
            notes: [],
            verifyOutput: VerifyOutput(
                command: "swift test --filter CinematicPlanCompassVerifySealPlanTests",
                exitCode: 65,
                tail: "Seal verify failed"
            ),
            feedback: nil
        )
    }

    private func languageProfile(primaryLanguage: RepositoryLanguage) -> RepositoryLanguageProfile {
        var counts = RepositoryLanguageCounts()
        counts[primaryLanguage] = 4
        return RepositoryLanguageProfile(
            counts: counts,
            manifestHints: [.packageSwift],
            primaryLanguage: primaryLanguage,
            scannedFileCount: 4,
            scannedDirectoryCount: 2,
            wasTruncated: false
        )
    }

    private func activityProfile() -> RepositoryActivityProfile {
        RepositoryActivityProfile(
            isAvailable: true,
            worktreeChanges: RepositoryWorktreeChangeCounts(),
            recentSessionCount: 1,
            recentSucceededCount: 1,
            recentFailedCount: 0,
            recentCommitCount: 1,
            lastTerminalStatus: .succeeded,
            lastSuccessfulSession: 1,
            lastFailedSession: nil,
            successStreak: 1,
            failureStreak: 0,
            recoveredFromFailure: false
        )
    }
}
