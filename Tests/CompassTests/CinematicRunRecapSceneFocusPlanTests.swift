import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapSceneFocusPlanTests: XCTestCase {
    func testPlanIsNoneUntilRecapOverlayHasAvailableRecap() throws {
        let session = makeSession(1, status: .succeeded, endedAt: 1_500)
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let recapPlan = makeRecapPlan(session: session, commitPlan: commitPlan)
        let timelinePlan = CinematicSessionTimelinePlan(sessions: [session])

        XCTAssertEqual(
            CinematicRunRecapSceneFocusPlanner.plan(
                isRecapOverlaySelected: false,
                recapPlan: recapPlan,
                commitConstellationPlan: commitPlan,
                timelinePlan: timelinePlan
            ),
            .none
        )

        let runningRecap = CinematicRunRecapPlanner.plan(
            state: recapState(),
            sessions: [session],
            isRunning: true,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        XCTAssertEqual(
            CinematicRunRecapSceneFocusPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: runningRecap,
                commitConstellationPlan: commitPlan,
                timelinePlan: timelinePlan
            ),
            .none
        )

        let focusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitPlan,
            timelinePlan: timelinePlan
        )
        let descriptor = try XCTUnwrap(focusPlan.descriptor)

        XCTAssertTrue(focusPlan.isActive)
        XCTAssertEqual(descriptor.recapIdentifier, recapPlan.identifier)
        XCTAssertEqual(descriptor.terminalBeatID, "session-1-outcome")
        XCTAssertEqual(descriptor.terminalStatusIdentifier, "succeeded")
        XCTAssertEqual(descriptor.terminalStyleIdentifier, "success")
    }

    func testTerminalStylesChooseRecapTreatment() throws {
        let cases: [(SessionStatus, String, CinematicCameraShot, CinematicStageLightFamily, CinematicStageArenaEffect)] = [
            (.succeeded, "success", .victory, .verify, .victory),
            (.failed, "failure", .failure, .failure, .charge),
            (.cancelled, "warning", .wide, .pressure, .activityPulse)
        ]

        for (status, expectedStyle, expectedShot, expectedLight, expectedEffect) in cases {
            let session = makeSession(2, status: status, endedAt: 2_500)
            let recapPlan = makeRecapPlan(session: session, commitPlan: .empty)
            let focusPlan = CinematicRunRecapSceneFocusPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: recapPlan,
                commitConstellationPlan: .empty,
                timelinePlan: CinematicSessionTimelinePlan(sessions: [session])
            )
            let descriptor = try XCTUnwrap(focusPlan.descriptor)

            XCTAssertEqual(descriptor.terminalStatusIdentifier, status.rawValue)
            XCTAssertEqual(descriptor.terminalStyleIdentifier, expectedStyle)
            XCTAssertEqual(descriptor.cameraShot, expectedShot)
            XCTAssertEqual(descriptor.lightFamily, expectedLight)
            XCTAssertEqual(descriptor.arenaEffect, expectedEffect)
            XCTAssertRecapFocusInRange(descriptor.lookTarget)
        }
    }

    func testNewestCommitNodeIsTargetedAndEmptyConstellationFallsBack() throws {
        let session = makeSession(
            3,
            commits: [
                SessionCommit(sha: "1111111111111111", short: "1111111", subject: "Older recap commit"),
                SessionCommit(sha: "2222222222222222", short: "2222222", subject: "Newest recap commit")
            ],
            endedAt: 3_500
        )
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let newestNode = try XCTUnwrap(commitPlan.nodes.first)
        let recapPlan = makeRecapPlan(session: session, commitPlan: commitPlan)
        let timelinePlan = CinematicSessionTimelinePlan(sessions: [session])

        let focused = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitPlan,
            timelinePlan: timelinePlan
        )
        let descriptor = try XCTUnwrap(focused.descriptor)

        XCTAssertEqual(descriptor.commitNodeIdentifier, newestNode.stableID)
        XCTAssertEqual(descriptor.lookTarget, newestNode.position)
        XCTAssertNil(descriptor.fallbackTargetIdentifier)
        XCTAssertFalse(descriptor.usesFallbackTarget)
        XCTAssertTrue(descriptor.identifier.contains(newestNode.stableID))

        let fallback = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: makeRecapPlan(session: session, commitPlan: .empty),
            commitConstellationPlan: .empty,
            timelinePlan: timelinePlan
        )
        let fallbackDescriptor = try XCTUnwrap(fallback.descriptor)

        XCTAssertNil(fallbackDescriptor.commitNodeIdentifier)
        XCTAssertEqual(fallbackDescriptor.lookTarget, CinematicCommitConstellationPlan.fallbackFocusLookTarget)
        XCTAssertEqual(fallbackDescriptor.fallbackTargetIdentifier, "commit-constellation-focus.empty")
        XCTAssertTrue(fallbackDescriptor.usesFallbackTarget)
    }

    func testIdentifiersAreStableBoundedAndReflectDrivingInputs() throws {
        let session = makeSession(4, status: .succeeded, endedAt: 4_500)
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let recapPlan = makeRecapPlan(session: session, commitPlan: commitPlan)
        let timelinePlan = CinematicSessionTimelinePlan(sessions: [session])

        let first = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitPlan,
            timelinePlan: timelinePlan
        )
        let repeated = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitPlan,
            timelinePlan: timelinePlan
        )
        let failedSession = makeSession(4, status: .failed, endedAt: 4_500)
        let changed = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: makeRecapPlan(session: failedSession, commitPlan: .empty),
            commitConstellationPlan: .empty,
            timelinePlan: CinematicSessionTimelinePlan(sessions: [failedSession])
        )

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.identifier, repeated.identifier)
        XCTAssertNotEqual(first.identifier, changed.identifier)
        XCTAssertLessThanOrEqual(first.identifier.count, CinematicRunRecapSceneFocusPlan.identifierMaxCharacters)
        let descriptor = try XCTUnwrap(first.descriptor)
        XCTAssertLessThanOrEqual(
            descriptor.identifier.count,
            CinematicRunRecapSceneFocusPlan.identifierMaxCharacters
        )
    }

    func testRecapFocusDoesNotMutateTimelineFocusPlanning() throws {
        let session = makeSession(
            5,
            commits: [
                SessionCommit(sha: "abcdef1234567890", short: "abcdef1", subject: "Preserve timeline focus")
            ],
            endedAt: 5_500
        )
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let timelineBefore = CinematicSessionTimelinePlan(
            sessions: [session],
            selectedBeatID: "session-5-plan"
        )
        let timelineFocusBefore = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: timelineBefore.selectedBeat,
            commitConstellationPlan: commitPlan,
            recoveryCuePlan: .none
        )

        _ = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: makeRecapPlan(session: session, commitPlan: commitPlan),
            commitConstellationPlan: commitPlan,
            timelinePlan: timelineBefore
        )

        let timelineAfter = CinematicSessionTimelinePlan(
            sessions: [session],
            selectedBeatID: "session-5-plan"
        )
        let timelineFocusAfter = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: timelineAfter.selectedBeat,
            commitConstellationPlan: commitPlan,
            recoveryCuePlan: .none
        )

        XCTAssertEqual(timelineAfter, timelineBefore)
        XCTAssertEqual(timelineAfter.selectedBeatID, "session-5-plan")
        XCTAssertEqual(timelineFocusAfter, timelineFocusBefore)
    }

    private func makeRecapPlan(
        session: SessionRecord,
        commitPlan: CinematicCommitConstellationPlan
    ) -> CinematicRunRecapPlan {
        CinematicRunRecapPlanner.plan(
            state: recapState(),
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
    }

    private func recapState() -> PlanState {
        PlanState(
            completed: ["Completed recap focus"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
    }

    private func makeSession(
        _ number: Int,
        status: SessionStatus = .succeeded,
        commits: [SessionCommit] = [],
        endedAt: Double?
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Double(number * 1_000),
            endedAt: endedAt,
            plan: "Stage recap focus",
            verify: "swift test --filter CinematicRunRecapSceneFocusPlanTests",
            beforeSha: nil,
            afterSha: nil,
            commits: commits,
            status: status,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
    }
}

private func XCTAssertRecapFocusInRange(
    _ value: SIMD3<Float>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(value.x, CinematicRunRecapSceneFocusPlan.targetXRange.lowerBound, file: file, line: line)
    XCTAssertLessThanOrEqual(value.x, CinematicRunRecapSceneFocusPlan.targetXRange.upperBound, file: file, line: line)
    XCTAssertGreaterThanOrEqual(value.y, CinematicRunRecapSceneFocusPlan.targetYRange.lowerBound, file: file, line: line)
    XCTAssertLessThanOrEqual(value.y, CinematicRunRecapSceneFocusPlan.targetYRange.upperBound, file: file, line: line)
    XCTAssertGreaterThanOrEqual(value.z, CinematicRunRecapSceneFocusPlan.targetZRange.lowerBound, file: file, line: line)
    XCTAssertLessThanOrEqual(value.z, CinematicRunRecapSceneFocusPlan.targetZRange.upperBound, file: file, line: line)
}
