import Foundation
@testable import Compass
import XCTest

final class CinematicSessionTimelinePlanTests: XCTestCase {
    func testOrdersBeatsChronologicallyInsideSessions() {
        let sessions = [
            makeSession(3, startedAt: 3_000),
            makeSession(1, startedAt: 1_000),
            makeSession(2, startedAt: 2_000)
        ]

        let plan = CinematicSessionTimelinePlan(sessions: sessions)

        XCTAssertEqual(
            plan.beats.map { "\($0.sessionNumber)-\($0.moment.rawValue)" },
            [
                "1-plan", "1-develop", "1-verify", "1-outcome",
                "2-plan", "2-develop", "2-verify", "2-outcome",
                "3-plan", "3-develop", "3-verify", "3-outcome"
            ]
        )
        XCTAssertEqual(plan.beats.map(\.chronologyIndex), Array(0..<plan.beats.count))
        XCTAssertEqual(plan.beats.first?.position, 0)
        XCTAssertEqual(plan.beats.last?.position, 1)
    }

    func testBoundsToRecentSessionsAndMaximumBeatCount() {
        let sessions = (1...7).map { number in
            makeSession(number, startedAt: Double(number * 1_000))
        }

        let recentPlan = CinematicSessionTimelinePlan(
            sessions: sessions,
            recentSessionLimit: 3,
            maximumBeatCount: 100
        )

        XCTAssertEqual(Set(recentPlan.beats.map(\.sessionNumber)), Set([5, 6, 7]))
        XCTAssertEqual(recentPlan.sessionCount, 3)
        XCTAssertEqual(recentPlan.beats.count, 12)
        XCTAssertEqual(recentPlan.countLabel, "12 beats · 3 runs")

        let beatBoundedPlan = CinematicSessionTimelinePlan(
            sessions: sessions,
            recentSessionLimit: 3,
            maximumBeatCount: 5
        )

        XCTAssertLessThanOrEqual(beatBoundedPlan.beats.count, 5)
        XCTAssertTrue(Set(beatBoundedPlan.beats.map(\.sessionNumber)).isSubset(of: Set([5, 6, 7])))
        XCTAssertFalse(beatBoundedPlan.beats.contains { $0.sessionNumber == 4 })
    }

    func testEmptyStateHasNoSelectionOrBeats() {
        let plan = CinematicSessionTimelinePlan(
            sessions: [],
            selectedBeatID: "session-1-plan"
        )

        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.identifier, "session-timeline.empty")
        XCTAssertEqual(plan.beats, [])
        XCTAssertNil(plan.selectedBeatID)
        XCTAssertNil(plan.selectedBeat)
        XCTAssertEqual(plan.countLabel, "0 beats")
    }

    func testFailedVerifyCueStylesVerifyAndOutcomeBeatsForAttention() throws {
        let cue = makeRunCue(
            kind: .failedVerify,
            severity: .failure,
            label: "Retry Develop",
            detail: "Expected true but got false",
            systemImage: "checkmark.seal.fill"
        )
        let session = makeSession(
            4,
            status: .failed,
            verifyOutput: VerifyOutput(
                command: "swift test --filter CinematicSessionTimelinePlanTests",
                exitCode: 65,
                tail: "Expected true but got false"
            )
        )

        let plan = CinematicSessionTimelinePlan(
            sessions: [session],
            runCues: [4: cue]
        )

        let verifyBeat = try XCTUnwrap(plan.beats.first { $0.moment == .verify })
        XCTAssertEqual(verifyBeat.style, .failure)
        XCTAssertEqual(verifyBeat.systemImage, "checkmark.seal.fill")
        XCTAssertEqual(verifyBeat.attentionLabel, "Retry Develop")
        XCTAssertEqual(verifyBeat.detail, "Expected true but got false")
        XCTAssertEqual(
            verifyBeat.metadata,
            "swift test --filter CinematicSessionTimelinePlanTests · exit 65"
        )

        let outcomeBeat = try XCTUnwrap(plan.beats.first { $0.moment == .outcome })
        XCTAssertEqual(outcomeBeat.style, .failure)
        XCTAssertEqual(outcomeBeat.systemImage, "checkmark.seal.fill")
        XCTAssertEqual(outcomeBeat.attentionDetail, "Expected true but got false")
    }

    func testDirtyWorktreeCueTargetsDevelopAndOutcomeBeats() throws {
        let cue = makeRunCue(
            kind: .dirtyWorktree,
            severity: .warning,
            label: "Clean Worktree",
            detail: "2 pending changes",
            systemImage: "pencil.and.outline"
        )
        let session = makeSession(5, status: .failed)

        let plan = CinematicSessionTimelinePlan(
            sessions: [session],
            runCues: [5: cue]
        )

        let developBeat = try XCTUnwrap(plan.beats.first { $0.moment == .develop })
        XCTAssertEqual(developBeat.style, .warning)
        XCTAssertEqual(developBeat.systemImage, "pencil.and.outline")
        XCTAssertEqual(developBeat.attentionLabel, "Clean Worktree")
        XCTAssertEqual(developBeat.detail, "2 pending changes")

        let verifyBeat = try XCTUnwrap(plan.beats.first { $0.moment == .verify })
        XCTAssertEqual(verifyBeat.style, .neutral)
        XCTAssertEqual(verifyBeat.systemImage, "checkmark.seal")

        let outcomeBeat = try XCTUnwrap(plan.beats.first { $0.moment == .outcome })
        XCTAssertEqual(outcomeBeat.style, .warning)
        XCTAssertEqual(outcomeBeat.systemImage, "pencil.and.outline")
    }

    func testPromotionFailureCueTargetsOutcomeBeatOnly() throws {
        let cue = makeRunCue(
            kind: .promotionFailed,
            severity: .failure,
            label: "Resolve Promotion",
            detail: "Failed to promote Develop sandbox branch compass/dev-123.",
            systemImage: "arrow.triangle.branch"
        )
        let session = makeSession(6, status: .failed)

        let plan = CinematicSessionTimelinePlan(
            sessions: [session],
            runCues: [6: cue]
        )

        let developBeat = try XCTUnwrap(plan.beats.first { $0.moment == .develop })
        XCTAssertEqual(developBeat.style, .neutral)
        XCTAssertEqual(developBeat.systemImage, "hammer")

        let verifyBeat = try XCTUnwrap(plan.beats.first { $0.moment == .verify })
        XCTAssertEqual(verifyBeat.style, .neutral)
        XCTAssertEqual(verifyBeat.systemImage, "checkmark.seal")

        let outcomeBeat = try XCTUnwrap(plan.beats.first { $0.moment == .outcome })
        XCTAssertEqual(outcomeBeat.style, .failure)
        XCTAssertEqual(outcomeBeat.systemImage, "arrow.triangle.branch")
        XCTAssertEqual(outcomeBeat.attentionLabel, "Resolve Promotion")
        XCTAssertEqual(outcomeBeat.detail, "Failed to promote Develop sandbox branch compass/dev-123.")
    }

    func testCommitBeatLabelsUseBoundedDisplaySubjectAndStableCommitID() throws {
        let commit = SessionCommit(
            sha: "abcdef1234567890abcdef",
            short: "abc1234",
            subject: "Add timeline scrubber with `marked` subject text and https://example.com/docs that should not leak"
        )
        let session = makeSession(8, commits: [commit])

        let plan = CinematicSessionTimelinePlan(sessions: [session])
        let commitBeat = try XCTUnwrap(plan.beats.first { $0.moment == .commit })

        XCTAssertEqual(commitBeat.stableID, "session-8-commit-abcdef1234567890")
        XCTAssertEqual(commitBeat.title, "Commit abc1234")
        XCTAssertTrue(commitBeat.label.hasPrefix("abc1234 Add timeline scrubber"))
        XCTAssertFalse(commitBeat.label.contains("https://"))
        XCTAssertFalse(commitBeat.label.contains("`"))
        XCTAssertLessThanOrEqual(commitBeat.detail.count, CinematicCommitContext.subjectMaxCharacters)
        XCTAssertEqual(commitBeat.style, .commit)
    }

    func testStableSelectionFallsBackWithinSessionThenNewestBeat() throws {
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
        let originalCommitID = try XCTUnwrap(original.beats.first { $0.moment == .commit }?.stableID)

        let sameSessionChanged = CinematicSessionTimelinePlan(
            sessions: [makeSession(2, commits: [])],
            selectedBeatID: originalCommitID
        )

        XCTAssertEqual(sameSessionChanged.selectedBeatID, "session-2-outcome")
        XCTAssertEqual(sameSessionChanged.selectedBeat?.moment, .outcome)

        let sessionRemoved = CinematicSessionTimelinePlan(
            sessions: [makeSession(3, startedAt: 3_000)],
            selectedBeatID: originalCommitID
        )

        XCTAssertEqual(sessionRemoved.selectedBeatID, sessionRemoved.beats.last?.stableID)
        XCTAssertEqual(sessionRemoved.selectedBeat?.sessionNumber, 3)
    }

    private func makeSession(
        _ number: Int,
        startedAt: Double? = nil,
        endedAt: Double? = nil,
        status: SessionStatus = .succeeded,
        plan: String? = "Implement timeline scrubber",
        verify: String? = "swift test --filter CinematicSessionTimelinePlanTests",
        commits: [SessionCommit] = [],
        notes: [String] = [],
        verifyOutput: VerifyOutput? = nil,
        feedback: String? = nil
    ) -> SessionRecord {
        let start = startedAt ?? Double(number * 1_000)
        return SessionRecord(
            session: number,
            startedAt: start,
            endedAt: endedAt ?? start + 500,
            plan: plan,
            verify: verify,
            beforeSha: nil,
            afterSha: nil,
            commits: commits,
            status: status,
            notes: notes,
            verifyOutput: verifyOutput,
            feedback: feedback
        )
    }

    private func makeRunCue(
        kind: PlanReliabilityFeedback.Kind,
        severity: PlanReliabilityFeedback.Severity,
        label: String,
        detail: String,
        systemImage: String
    ) -> PlanReliabilityFeedback.RunCue {
        PlanReliabilityFeedback.RunCue(
            notice: PlanReliabilityFeedback.Notice(
                id: "\(kind.rawValue)-test",
                kind: kind,
                severity: severity,
                sessionNumber: 0,
                title: label,
                detail: detail,
                actionLabel: label,
                metadata: nil,
                systemImage: systemImage
            )
        )
    }
}
