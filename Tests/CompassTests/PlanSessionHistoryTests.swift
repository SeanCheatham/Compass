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
        XCTAssertEqual(display.filter, .all)
        XCTAssertEqual(display.unfilteredTotalCount, sessionCount)
        XCTAssertEqual(display.filterOptions.map(\.filter), PlanSessionHistoryFilter.allCases)
        XCTAssertEqual(display.filterOptions.map(\.count), [sessionCount, 0, 0, 0, sessionCount])
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
            makeHistoryItem(2, status: .failed),
            makeHistoryItem(5),
            makeHistoryItem(1, status: .failed),
            makeHistoryItem(4, status: .failed)
        ]

        let recentDisplay = PlanSessionHistoryDisplay(items: items, recentLimit: 2)
        XCTAssertEqual(recentDisplay.visibleItems.map(\.sessionNumber), [2, 5])

        let allDisplay = PlanSessionHistoryDisplay(items: items, mode: .all, recentLimit: 2)
        XCTAssertEqual(allDisplay.visibleItems.map(\.sessionNumber), [2, 5, 1, 4])

        let filteredRecentDisplay = PlanSessionHistoryDisplay(
            items: items,
            recentLimit: 2,
            filter: .failedRejected
        )
        XCTAssertEqual(filteredRecentDisplay.visibleItems.map(\.sessionNumber), [2, 1])

        let filteredAllDisplay = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            recentLimit: 2,
            filter: .failedRejected
        )
        XCTAssertEqual(filteredAllDisplay.visibleItems.map(\.sessionNumber), [2, 1, 4])
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

    func testDisplayFiltersAttentionRunsFromRunCues() {
        let items = [
            makeHistoryItem(4),
            makeHistoryItem(3),
            makeHistoryItem(2),
            makeHistoryItem(1)
        ]
        let display = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            filter: .attention,
            runCues: [
                4: makeRunCue(kind: .resumeDevelop, severity: .paused),
                2: makeRunCue(kind: .failedVerify)
            ]
        )

        XCTAssertEqual(display.totalCount, 2)
        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [4, 2])
        XCTAssertEqual(display.countSummary, "2 matching runs")
        XCTAssertEqual(
            display.filterOptions.first { $0.filter == .attention }?.count,
            2
        )
    }

    func testDisplayGroupsFailedAndRejectedRuns() {
        let items = [
            makeHistoryItem(7),
            makeHistoryItem(6),
            makeHistoryItem(5),
            makeHistoryItem(4, status: .rejectedByPlan),
            makeHistoryItem(3, status: .failed),
            makeHistoryItem(2),
            makeHistoryItem(1)
        ]
        let display = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            filter: .failedRejected,
            runCues: [
                7: makeRunCue(kind: .promotionFailed),
                6: makeRunCue(kind: .dirtyWorktree, severity: .warning),
                5: makeRunCue(kind: .failedVerify),
                2: makeRunCue(kind: .developFailed)
            ]
        )

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [7, 6, 5, 4, 3, 2])
        XCTAssertEqual(display.totalCount, 6)
    }

    func testDisplayGroupsActiveAndPausedRuns() {
        let items = [
            makeHistoryItem(5),
            makeHistoryItem(4, status: .awaitingApproval),
            makeHistoryItem(3, status: .developing),
            makeHistoryItem(2, status: .planning),
            makeHistoryItem(1)
        ]
        let display = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            filter: .activePaused,
            runCues: [
                5: makeRunCue(kind: .resumeDevelop, severity: .paused)
            ]
        )

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [5, 4, 3, 2])
        XCTAssertEqual(display.totalCount, 4)
    }

    func testDisplayGroupsCompletedAndFinishedRuns() {
        let items = [
            makeHistoryItem(6, status: .succeeded),
            makeHistoryItem(5, status: .cancelled),
            makeHistoryItem(4, status: .skipped),
            makeHistoryItem(3, status: .failed),
            makeHistoryItem(2, status: .rejectedByPlan),
            makeHistoryItem(1, status: .awaitingApproval)
        ]
        let display = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            filter: .completedFinished
        )

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [6, 5, 4])
        XCTAssertEqual(display.totalCount, 3)
    }

    func testDisplaySummariesUseFilteredCounts() {
        let items = [
            makeHistoryItem(6),
            makeHistoryItem(5),
            makeHistoryItem(4),
            makeHistoryItem(3),
            makeHistoryItem(2),
            makeHistoryItem(1)
        ]
        let runCues = [
            6: makeRunCue(kind: .failedVerify),
            5: makeRunCue(kind: .developFailed),
            4: makeRunCue(kind: .resumeDevelop, severity: .paused)
        ]

        let recentDisplay = PlanSessionHistoryDisplay(
            items: items,
            recentLimit: 2,
            filter: .attention,
            runCues: runCues
        )
        XCTAssertEqual(recentDisplay.visibleItems.map(\.sessionNumber), [6, 5])
        XCTAssertEqual(recentDisplay.totalCount, 3)
        XCTAssertEqual(recentDisplay.hiddenCount, 1)
        XCTAssertEqual(recentDisplay.countSummary, "Showing latest 2 of 3 matching")
        XCTAssertTrue(recentDisplay.shouldOfferModeToggle)

        let allDisplay = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            recentLimit: 2,
            filter: .attention,
            runCues: runCues
        )
        XCTAssertEqual(allDisplay.countSummary, "Showing all 3 matching")

        let noHiddenDisplay = PlanSessionHistoryDisplay(
            items: items,
            recentLimit: 4,
            filter: .attention,
            runCues: runCues
        )
        XCTAssertEqual(noHiddenDisplay.countSummary, "3 matching runs")

        let emptyFilteredDisplay = PlanSessionHistoryDisplay(
            items: items,
            filter: .failedRejected
        )
        XCTAssertEqual(emptyFilteredDisplay.unfilteredTotalCount, 6)
        XCTAssertEqual(emptyFilteredDisplay.totalCount, 0)
        XCTAssertEqual(emptyFilteredDisplay.countSummary, "0 matching runs")
    }

    func testDisplaySummarizesHiddenStatusesAfterFiltering() {
        let items = [
            makeHistoryItem(6, status: .failed),
            makeHistoryItem(5, status: .succeeded),
            makeHistoryItem(4, status: .rejectedByPlan),
            makeHistoryItem(3, status: .cancelled),
            makeHistoryItem(2, status: .skipped),
            makeHistoryItem(1, status: .awaitingApproval)
        ]

        let display = PlanSessionHistoryDisplay(
            items: items,
            recentLimit: 1,
            filter: .completedFinished
        )

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [5])
        XCTAssertEqual(display.hiddenCount, 2)
        XCTAssertEqual(display.hiddenStatusSummary, "1 cancelled, 1 skipped")
    }

    private func makeHistoryItem(
        _ number: Int,
        status: SessionStatus = .succeeded
    ) -> PlanSessionHistoryItem {
        PlanSessionHistoryItem(
            sessionNumber: number,
            status: status,
            statusText: statusText(for: status),
            startedAt: Date(timeIntervalSince1970: Double(number)),
            planExcerpt: "Plan",
            verifyCommand: "swift test",
            feedback: nil,
            notes: [],
            commits: [],
            failedVerify: nil
        )
    }

    private func makeRunCue(
        kind: PlanReliabilityFeedback.Kind,
        severity: PlanReliabilityFeedback.Severity = .failure
    ) -> PlanReliabilityFeedback.RunCue {
        PlanReliabilityFeedback.RunCue(
            notice: PlanReliabilityFeedback.Notice(
                id: "\(kind.rawValue)-test",
                kind: kind,
                severity: severity,
                sessionNumber: 0,
                title: "Cue",
                detail: "Run needs attention.",
                actionLabel: "Review",
                metadata: nil,
                systemImage: "exclamationmark.triangle"
            )
        )
    }

    private func statusText(for status: SessionStatus) -> String {
        switch status {
        case .planning:
            return "Planning"
        case .awaitingApproval:
            return "Awaiting approval"
        case .developing:
            return "Developing"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .rejectedByPlan:
            return "Rejected by plan"
        case .skipped:
            return "Skipped"
        }
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
