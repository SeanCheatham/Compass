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

    func testDisplayDefaultsToRecentLimit() {
        let sessionCount = PlanSessionHistoryDisplay.defaultRecentLimit + 3
        let items = PlanSessionHistory.displayItems(
            for: (1...sessionCount).map { number in
                makeSession(number, startedAt: Double(number * 1_000))
            }
        )

        let display = PlanSessionHistoryDisplay(items: items)

        XCTAssertEqual(display.totalCount, sessionCount)
        XCTAssertEqual(display.visibleCount, PlanSessionHistoryDisplay.defaultRecentLimit)
        XCTAssertEqual(display.hiddenCount, 3)
        XCTAssertEqual(
            display.visibleItems.map(\.sessionNumber),
            Array((sessionCount - PlanSessionHistoryDisplay.defaultRecentLimit + 1...sessionCount).reversed())
        )
        XCTAssertEqual(display.countSummary, "Showing latest 8 of 11")
        XCTAssertTrue(display.shouldOfferModeToggle)
    }

    func testDisplayShowAllModeIncludesEveryRun() {
        let items = PlanSessionHistory.displayItems(
            for: (1...7).map { number in
                makeSession(number, startedAt: Double(number * 1_000))
            }
        )

        let display = PlanSessionHistoryDisplay(items: items, mode: .all, recentLimit: 4)

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [7, 6, 5, 4, 3, 2, 1])
        XCTAssertEqual(display.totalCount, 7)
        XCTAssertEqual(display.visibleCount, 7)
        XCTAssertEqual(display.hiddenCount, 0)
        XCTAssertNil(display.hiddenStatusSummary)
        XCTAssertEqual(display.countSummary, "Showing all 7")
        XCTAssertTrue(display.shouldOfferModeToggle)
    }

    func testDisplaySummarizesHiddenStatuses() {
        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(1, startedAt: 1_000, status: .awaitingApproval),
                makeSession(2, startedAt: 2_000, status: .succeeded),
                makeSession(3, startedAt: 3_000, status: .cancelled),
                makeSession(4, startedAt: 4_000, status: .failed),
                makeSession(5, startedAt: 5_000, status: .failed),
                makeSession(6, startedAt: 6_000, status: .succeeded)
            ]
        )

        let display = PlanSessionHistoryDisplay(items: items, recentLimit: 1)

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [6])
        XCTAssertEqual(display.hiddenCount, 5)
        XCTAssertEqual(
            display.hiddenStatusSummary,
            "2 failed, 1 cancelled, 1 succeeded, 1 awaiting approval"
        )
    }

    func testDisplayHandlesNoHiddenAndEmptyStates() {
        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(1, startedAt: 1_000),
                makeSession(2, startedAt: 2_000)
            ]
        )

        let noHiddenDisplay = PlanSessionHistoryDisplay(items: items, recentLimit: 3)
        XCTAssertEqual(noHiddenDisplay.totalCount, 2)
        XCTAssertEqual(noHiddenDisplay.visibleCount, 2)
        XCTAssertEqual(noHiddenDisplay.hiddenCount, 0)
        XCTAssertNil(noHiddenDisplay.hiddenStatusSummary)
        XCTAssertEqual(noHiddenDisplay.countSummary, "2 runs")
        XCTAssertFalse(noHiddenDisplay.shouldOfferModeToggle)

        let emptyDisplay = PlanSessionHistoryDisplay(items: [])
        XCTAssertEqual(emptyDisplay.totalCount, 0)
        XCTAssertEqual(emptyDisplay.visibleCount, 0)
        XCTAssertEqual(emptyDisplay.hiddenCount, 0)
        XCTAssertNil(emptyDisplay.hiddenStatusSummary)
        XCTAssertEqual(emptyDisplay.countSummary, "0 runs")
        XCTAssertFalse(emptyDisplay.shouldOfferModeToggle)
    }

    func testDisplayPreservesIncomingOrder() {
        let items = [
            makeHistoryItem(2),
            makeHistoryItem(5),
            makeHistoryItem(1)
        ]

        let recentDisplay = PlanSessionHistoryDisplay(items: items, recentLimit: 2)
        XCTAssertEqual(recentDisplay.visibleItems.map(\.sessionNumber), [2, 5])

        let allDisplay = PlanSessionHistoryDisplay(items: items, mode: .all, recentLimit: 2)
        XCTAssertEqual(allDisplay.visibleItems.map(\.sessionNumber), [2, 5, 1])
    }

    func testDisplayPreservesFailedVerifyMetadataForVisibleRows() throws {
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

        let display = PlanSessionHistoryDisplay(items: items)

        let failedVerify = try XCTUnwrap(display.visibleItems[0].failedVerify)
        XCTAssertEqual(failedVerify.command, "swift test --filter PlanSessionHistoryTests")
        XCTAssertEqual(failedVerify.exitCodeText, "exit 65")
        XCTAssertEqual(failedVerify.tail, "failure tail")
    }

    private func makeHistoryItem(_ number: Int) -> PlanSessionHistoryItem {
        PlanSessionHistoryItem(
            sessionNumber: number,
            status: .succeeded,
            statusText: "Succeeded",
            startedAt: Date(timeIntervalSince1970: Double(number)),
            planExcerpt: "Plan",
            verifyCommand: "swift test",
            feedback: nil,
            notes: [],
            commits: [],
            failedVerify: nil
        )
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
