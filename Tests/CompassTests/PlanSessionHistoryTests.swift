import Foundation
@testable import Compass
import XCTest

final class PlanSessionHistoryTests: XCTestCase {
    func testOrdersSessionsReverseChronologically() {
        let sessions = [
            makeSession(1, startedAt: 1_000),
            makeSession(3, startedAt: 2_000),
            makeSession(2, startedAt: 3_000),
            makeSession(4, startedAt: 3_000)
        ]

        let items = PlanSessionHistory.displayItems(for: sessions)

        XCTAssertEqual(items.map(\.sessionNumber), [4, 2, 3, 1])
    }

    func testHandlesEmptyAndPlanlessSessions() {
        XCTAssertEqual(PlanSessionHistory.displayItems(for: []), [])

        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(
                    1,
                    startedAt: 1_000,
                    plan: nil,
                    verify: "   ",
                    feedback: "\n"
                )
            ]
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].planExcerpt)
        XCTAssertNil(items[0].verifyCommand)
        XCTAssertNil(items[0].feedback)
        XCTAssertEqual(items[0].statusText, "Succeeded")
    }

    func testPreservesFailedVerifyMetadata() throws {
        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(
                    1,
                    startedAt: 1_000,
                    status: .failed,
                    verify: "swift test",
                    verifyOutput: VerifyOutput(
                        command: "swift test --filter PlanSessionHistoryTests",
                        exitCode: 65,
                        tail: "failure tail"
                    )
                )
            ]
        )

        let failedVerify = try XCTUnwrap(items[0].failedVerify)
        XCTAssertEqual(failedVerify.command, "swift test --filter PlanSessionHistoryTests")
        XCTAssertEqual(failedVerify.exitCodeText, "exit 65")
        XCTAssertEqual(failedVerify.tail, "failure tail")
    }

    func testPreservesCommitsNotesAndFeedback() {
        let commit = SessionCommit(
            sha: "abcdef123456",
            short: "abcdef1",
            subject: "Ship plan history"
        )
        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(
                    1,
                    startedAt: 1_000,
                    commits: [commit],
                    notes: ["first note", "second note"],
                    feedback: "  useful handoff  "
                )
            ]
        )

        XCTAssertEqual(items[0].commits, [commit])
        XCTAssertEqual(items[0].notes, ["first note", "second note"])
        XCTAssertEqual(items[0].feedback, "useful handoff")
    }

    func testBoundsPlanExcerpt() {
        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(
                    1,
                    startedAt: 1_000,
                    plan: "Build \n a\t very detailed plan with many words and extra detail."
                )
            ],
            planExcerptLimit: 24
        )

        XCTAssertEqual(items[0].planExcerpt, "Build a very detailed...")
        XCTAssertLessThanOrEqual(items[0].planExcerpt?.count ?? 0, 24)
    }

    private func makeSession(
        _ number: Int,
        startedAt: Double,
        status: SessionStatus = .succeeded,
        plan: String? = "Plan",
        verify: String? = "swift test",
        commits: [SessionCommit] = [],
        notes: [String] = [],
        verifyOutput: VerifyOutput? = nil,
        feedback: String? = nil
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: startedAt,
            endedAt: startedAt + 500,
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
}
