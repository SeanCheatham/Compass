import Foundation
@testable import Compass
import XCTest

final class CinematicTimelineSceneFocusPlanTests: XCTestCase {
    func testDeterministicIdentifiersAndOrdinaryMappingsAreBounded() throws {
        let beats: [(CinematicSessionTimelinePlan.Beat.Moment, CinematicTimelineSceneFocusPlan.Descriptor.Kind)] = [
            (.plan, .plan),
            (.develop, .develop),
            (.verify, .verify),
            (.outcome, .outcome)
        ]

        for (moment, expectedKind) in beats {
            let beat = makeBeat(moment: moment, style: moment == .outcome ? .success : .neutral)
            let first = CinematicTimelineSceneFocusPlanner.plan(
                selectedBeat: beat,
                commitConstellationPlan: .empty,
                recoveryCuePlan: .none
            )
            let repeated = CinematicTimelineSceneFocusPlanner.plan(
                selectedBeat: beat,
                commitConstellationPlan: .empty,
                recoveryCuePlan: .none
            )
            let descriptor = try XCTUnwrap(first.descriptor)

            XCTAssertEqual(first, repeated)
            XCTAssertEqual(first.selectedBeatID, beat.stableID)
            XCTAssertEqual(descriptor.kind, expectedKind)
            XCTAssertLessThanOrEqual(first.identifier.count, CinematicTimelineSceneFocusPlan.identifierMaxCharacters)
            XCTAssertLessThanOrEqual(descriptor.identifier.count, CinematicTimelineSceneFocusPlan.identifierMaxCharacters)
            XCTAssertLessThanOrEqual(descriptor.label.count, CinematicTimelineSceneFocusPlan.labelMaxCharacters)
            XCTAssertInRange(descriptor.lookTarget.x, CinematicTimelineSceneFocusPlan.targetXRange)
            XCTAssertInRange(descriptor.lookTarget.y, CinematicTimelineSceneFocusPlan.targetYRange)
            XCTAssertInRange(descriptor.lookTarget.z, CinematicTimelineSceneFocusPlan.targetZRange)
            XCTAssertFalse(descriptor.usesFallbackTarget)
        }
    }

    func testCommitBeatFocusesMatchingConstellationNode() throws {
        let constellationPlan = CinematicTimelineSceneFocusPlanner.representativeCommitConstellationPlan()
        let node = try XCTUnwrap(constellationPlan.nodes.first)
        let beat = makeBeat(
            stableID: "session-61-commit-\(node.commitIdentifier)",
            moment: .commit,
            label: node.label,
            style: .commit
        )

        let focusPlan = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: beat,
            commitConstellationPlan: constellationPlan,
            recoveryCuePlan: .none
        )
        let descriptor = try XCTUnwrap(focusPlan.descriptor)

        XCTAssertEqual(descriptor.kind, .commit)
        XCTAssertEqual(descriptor.cameraShot, .commitConstellation)
        XCTAssertEqual(descriptor.lookTarget, node.position)
        XCTAssertEqual(descriptor.commitNodeIdentifier, node.stableID)
        XCTAssertEqual(descriptor.lightFamily, .git)
        XCTAssertEqual(descriptor.arenaEffect, .historyChains)
        XCTAssertFalse(descriptor.usesFallbackTarget)
        XCTAssertTrue(descriptor.identifier.contains(node.stableID))
    }

    func testCommitBeatFallsBackWhenConstellationNodeIsUnavailable() throws {
        let constellationPlan = CinematicTimelineSceneFocusPlanner.representativeCommitConstellationPlan()
        let newestNode = try XCTUnwrap(constellationPlan.nodes.first)
        let missingBeat = makeBeat(
            stableID: "session-61-commit-missingdeadbeef",
            moment: .commit,
            style: .commit
        )

        let focusPlan = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: missingBeat,
            commitConstellationPlan: constellationPlan,
            recoveryCuePlan: .none
        )
        let descriptor = try XCTUnwrap(focusPlan.descriptor)

        XCTAssertEqual(descriptor.kind, .commit)
        XCTAssertEqual(descriptor.cameraShot, .commitConstellation)
        XCTAssertEqual(descriptor.lookTarget, newestNode.position)
        XCTAssertNil(descriptor.commitNodeIdentifier)
        XCTAssertTrue(descriptor.usesFallbackTarget)

        let emptyFocus = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: missingBeat,
            commitConstellationPlan: .empty,
            recoveryCuePlan: .none
        )
        let emptyDescriptor = try XCTUnwrap(emptyFocus.descriptor)
        XCTAssertEqual(emptyDescriptor.cameraShot, .home)
        XCTAssertEqual(emptyDescriptor.lookTarget, CinematicCommitConstellationPlan.fallbackFocusLookTarget)
        XCTAssertTrue(emptyDescriptor.usesFallbackTarget)
    }

    func testRecoveryAttentionBeatReusesSelectedRecoveryCueVisualTreatment() throws {
        for recoveryCuePlan in CinematicRecoveryCuePlanner.representativePlans()
            where recoveryCuePlan.hasActionableCue {
            let selectedCue = try XCTUnwrap(recoveryCuePlan.selectedCue)
            let visualDescriptor = try XCTUnwrap(recoveryCuePlan.visualDescriptor)
            let beat = makeBeat(
                stableID: "session-\(selectedCue.sessionNumber)-attention",
                moment: selectedCue.kind == .failedVerify ? .verify : .develop,
                label: selectedCue.label,
                style: selectedCue.severity == .warning ? .warning : .failure,
                systemImage: selectedCue.systemImage,
                attentionLabel: selectedCue.label,
                attentionDetail: selectedCue.detail
            )

            let focusPlan = CinematicTimelineSceneFocusPlanner.plan(
                selectedBeat: beat,
                commitConstellationPlan: .empty,
                recoveryCuePlan: recoveryCuePlan
            )
            let descriptor = try XCTUnwrap(focusPlan.descriptor)

            XCTAssertEqual(descriptor.kind, .recovery)
            XCTAssertEqual(descriptor.lightFamily, visualDescriptor.lightFamily)
            XCTAssertEqual(descriptor.arenaEffect, visualDescriptor.arenaEffect)
            XCTAssertEqual(descriptor.phaseLightIntensity, visualDescriptor.phaseLightIntensity)
            XCTAssertEqual(descriptor.recoveryTreatmentIdentifier, visualDescriptor.treatmentIdentifier)
            XCTAssertEqual(descriptor.recoveryVisualIdentifier, visualDescriptor.identifier)
            XCTAssertEqual(descriptor.cameraShot, visualDescriptor.shouldShakeCamera ? .failure : .castPrep)
            XCTAssertFalse(descriptor.usesFallbackTarget)
        }
    }

    func testFailedVerifyWithoutRecoveryCueGetsFailureMapping() throws {
        let beat = makeBeat(
            stableID: "session-12-verify",
            moment: .verify,
            style: .failure,
            systemImage: "checkmark.seal.fill"
        )

        let focusPlan = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: beat,
            commitConstellationPlan: .empty,
            recoveryCuePlan: .none
        )
        let descriptor = try XCTUnwrap(focusPlan.descriptor)

        XCTAssertEqual(descriptor.kind, .failedVerify)
        XCTAssertEqual(descriptor.cameraShot, .failure)
        XCTAssertEqual(descriptor.lightFamily, .failure)
        XCTAssertEqual(descriptor.arenaEffect, .charge)
        XCTAssertEqual(descriptor.recoveryTreatmentIdentifier, "verify-failure")
    }

    func testStaleSelectionUsesTimelineNormalizedBeatAndNilSelectionProducesNoFocus() throws {
        let original = CinematicSessionTimelinePlan(
            sessions: [
                makeSession(
                    2,
                    commits: [
                        SessionCommit(
                            sha: "feedface1234567890",
                            short: "feedfac",
                            subject: "Original commit"
                        )
                    ]
                )
            ]
        )
        let staleCommitBeatID = try XCTUnwrap(original.beats.first { $0.moment == .commit }?.stableID)
        let normalized = CinematicSessionTimelinePlan(
            sessions: [makeSession(2, commits: [])],
            selectedBeatID: staleCommitBeatID
        )

        let focusPlan = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: normalized.selectedBeat,
            commitConstellationPlan: .empty,
            recoveryCuePlan: .none
        )

        XCTAssertEqual(normalized.selectedBeatID, "session-2-outcome")
        XCTAssertEqual(focusPlan.selectedBeatID, "session-2-outcome")
        XCTAssertEqual(try XCTUnwrap(focusPlan.descriptor).kind, .outcome)
        XCTAssertEqual(
            CinematicTimelineSceneFocusPlanner.plan(
                selectedBeat: nil,
                commitConstellationPlan: .empty,
                recoveryCuePlan: .none
            ),
            .none
        )
    }

    private func makeBeat(
        stableID: String? = nil,
        moment: CinematicSessionTimelinePlan.Beat.Moment,
        label: String? = nil,
        style: CinematicSessionTimelinePlan.Beat.Style = .neutral,
        systemImage: String = "circle",
        attentionLabel: String? = nil,
        attentionDetail: String? = nil
    ) -> CinematicSessionTimelinePlan.Beat {
        let sessionNumber = 12
        let stableID = stableID ?? "session-\(sessionNumber)-\(moment.rawValue)"
        let label = label ?? "\(moment.shortTitle) #\(sessionNumber)"
        return CinematicSessionTimelinePlan.Beat(
            stableID: stableID,
            sessionNumber: sessionNumber,
            moment: moment,
            title: label,
            label: label,
            detail: "Focus \(moment.shortTitle)",
            metadata: "#\(sessionNumber)",
            timestamp: Date(timeIntervalSince1970: 12_000),
            chronologyIndex: 0,
            position: 0.5,
            style: style,
            systemImage: systemImage,
            attentionLabel: attentionLabel,
            attentionDetail: attentionDetail
        )
    }

    private func makeSession(
        _ number: Int,
        commits: [SessionCommit]
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Double(number * 1_000),
            endedAt: Double(number * 1_000 + 500),
            plan: "Timeline focus",
            verify: "swift test",
            beforeSha: nil,
            afterSha: nil,
            commits: commits,
            status: .succeeded,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
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
