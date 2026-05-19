import Foundation
@testable import Compass
import XCTest

final class LiveActivitySummaryTests: XCTestCase {
    func testFreezesClusterAtLifecycleBoundaryAfterMinimumRows() throws {
        let lines = [
            makeLine(offset: 0, text: "Planning started"),
            makeLine(offset: 0.3, text: "Reading files", kind: .command, status: .completed),
            makeLine(offset: 0.6, text: "Checking tests", kind: .command, status: .completed),
            makeLine(offset: 0.9, text: "Reviewing output", kind: .agentMessage),
            makeLine(
                offset: 1.2,
                text: "Develop completed",
                kind: .lifecycle,
                status: .completed
            ),
            makeLine(offset: 1.5, text: "Next live row")
        ]

        let plan = LiveActivitySummaryPlanner.plan(
            lines: lines,
            now: date(2),
            quietGap: 2.0
        )

        XCTAssertEqual(plan.frozenClusters.count, 1)
        let cluster = try XCTUnwrap(plan.frozenClusters.first)
        XCTAssertEqual(cluster.lines.map(\.id), Array(lines.prefix(5)).map(\.id))
        XCTAssertEqual(cluster.freezeReason, .lifecycleBoundary)
        XCTAssertEqual(plan.items.last, .line(lines[5]))
    }

    func testFreezesClusterAtQuietGapAfterMinimumRows() throws {
        let lines = [
            makeLine(offset: 0, text: "Read package"),
            makeLine(offset: 0.2, text: "Inspect source", kind: .command, status: .completed),
            makeLine(offset: 0.4, text: "Inspect tests", kind: .command, status: .completed),
            makeLine(offset: 0.6, text: "Patch summary", kind: .agentMessage),
            makeLine(offset: 0.8, text: "Render row"),
            makeLine(offset: 3.4, text: "Resume activity")
        ]

        let plan = LiveActivitySummaryPlanner.plan(
            lines: lines,
            now: date(3.5),
            quietGap: 2.0
        )

        XCTAssertEqual(plan.frozenClusters.count, 1)
        let cluster = try XCTUnwrap(plan.frozenClusters.first)
        XCTAssertEqual(cluster.lines.map(\.id), Array(lines.prefix(5)).map(\.id))
        XCTAssertEqual(cluster.freezeReason, .quietGap)
        XCTAssertEqual(plan.items.last, .line(lines[5]))
    }

    func testRunningRowsRemainUnfrozen() {
        let lines = [
            makeLine(offset: 0, text: "Read package"),
            makeLine(offset: 0.2, text: "Inspect source", kind: .command, status: .completed),
            makeLine(offset: 0.4, text: "Inspect tests", kind: .command, status: .completed),
            makeLine(offset: 0.6, text: "Patch summary", kind: .agentMessage),
            makeLine(offset: 0.8, text: "Running verify", kind: .command, status: .running)
        ]

        let plan = LiveActivitySummaryPlanner.plan(
            lines: lines,
            now: date(4),
            quietGap: 2.0
        )

        XCTAssertTrue(plan.frozenClusters.isEmpty)
        XCTAssertEqual(plan.items, lines.map(LiveActivitySummaryItem.line))
    }

    func testClusterKeyIsStableForUnchangedRows() throws {
        let lines = completedBatch()

        let first = LiveActivitySummaryPlanner.plan(lines: lines, now: date(4))
        let second = LiveActivitySummaryPlanner.plan(lines: lines, now: date(4))

        XCTAssertEqual(first.frozenClusters.first?.key, second.frozenClusters.first?.key)
    }

    func testClusterKeyChangesWhenRunningRowCompletesInPlace() {
        var running = completedBatch()
        running[4].status = .running
        running[4].text = "Running verify"
        let runningCluster = LiveActivityCluster(
            lines: running,
            freezeReason: .quietGap
        )

        var completed = running
        completed[4].status = .completed
        completed[4].text = "Verify completed"
        let completedCluster = LiveActivityCluster(
            lines: completed,
            freezeReason: .quietGap
        )

        XCTAssertEqual(running[4].id, completed[4].id)
        XCTAssertNotEqual(runningCluster.key, completedCluster.key)
    }

    func testParserAcceptsPlainGeneratedTitle() throws {
        let cluster = LiveActivityCluster(lines: completedBatch(), freezeReason: .quietGap)

        let summary = try XCTUnwrap(
            LiveActivitySummaryService.parseGeneratedTitle(
                "Title: Verify output reviewed",
                cluster: cluster
            )
        )

        XCTAssertEqual(summary.title, "Verify output reviewed")
        XCTAssertEqual(summary.source, .generated)
    }

    func testParserRejectsMarkdownJSONURLsAndLongTitles() {
        let cluster = LiveActivityCluster(lines: completedBatch(), freezeReason: .quietGap)

        XCTAssertNil(
            LiveActivitySummaryService.parseGeneratedTitle(
                "```Verify output reviewed```",
                cluster: cluster
            )
        )
        XCTAssertNil(
            LiveActivitySummaryService.parseGeneratedTitle(
                #"{"title":"Verify output reviewed"}"#,
                cluster: cluster
            )
        )
        XCTAssertNil(
            LiveActivitySummaryService.parseGeneratedTitle(
                "Review https://example.com output",
                cluster: cluster
            )
        )
        XCTAssertNil(
            LiveActivitySummaryService.parseGeneratedTitle(
                "One two three four five six seven eight nine ten eleven twelve thirteen",
                cluster: cluster
            )
        )
    }

    func testParserRejectsInventedFilenamesNumbersAndOutcomes() {
        let cluster = LiveActivityCluster(lines: completedBatch(), freezeReason: .quietGap)

        XCTAssertNil(
            LiveActivitySummaryService.parseGeneratedTitle(
                "README.md reviewed",
                cluster: cluster
            )
        )
        XCTAssertNil(
            LiveActivitySummaryService.parseGeneratedTitle(
                "12 tests reviewed",
                cluster: cluster
            )
        )
        XCTAssertNil(
            LiveActivitySummaryService.parseGeneratedTitle(
                "Twelve tests reviewed",
                cluster: cluster
            )
        )
        XCTAssertNil(
            LiveActivitySummaryService.parseGeneratedTitle(
                "All tests passed",
                cluster: cluster
            )
        )
    }

    func testParserAllowsFilenamesNumbersAndOutcomesPresentInInputs() throws {
        let lines = [
            makeLine(offset: 0, text: "Edit README.md"),
            makeLine(offset: 0.2, text: "Run 12 tests", kind: .command, status: .completed),
            makeLine(offset: 0.4, text: "Tests passed", level: .success, status: .completed),
            makeLine(offset: 0.6, text: "Review output"),
            makeLine(offset: 0.8, text: "Develop completed", kind: .lifecycle, status: .completed)
        ]
        let cluster = LiveActivityCluster(lines: lines, freezeReason: .lifecycleBoundary)

        let summary = try XCTUnwrap(
            LiveActivitySummaryService.parseGeneratedTitle(
                "README.md and 12 tests passed",
                cluster: cluster
            )
        )

        XCTAssertEqual(summary.title, "README.md and 12 tests passed")
    }

    func testDeterministicFallbackTitleIsBoundedAndStable() {
        let cluster = LiveActivityCluster(lines: completedBatch(), freezeReason: .quietGap)

        let summary = LiveActivitySummaryService.deterministicSummary(for: cluster)
        let repeated = LiveActivitySummaryService.deterministicSummary(for: cluster)

        XCTAssertEqual(summary, repeated)
        XCTAssertEqual(summary.source, .deterministic)
        XCTAssertLessThanOrEqual(summary.title.split(whereSeparator: \.isWhitespace).count, 12)
        XCTAssertLessThanOrEqual(summary.title.count, LiveActivitySummaryService.titleMaxCharacters)
        XCTAssertTrue(summary.title.contains("Verify completed"))
    }

    func testPlansOnlyMissingNonInFlightSummariesAndPrunesStaleKeys() {
        let first = LiveActivityCluster(lines: completedBatch(seed: 0), freezeReason: .quietGap)
        let second = LiveActivityCluster(lines: completedBatch(seed: 10), freezeReason: .quietGap)
        let third = LiveActivityCluster(lines: completedBatch(seed: 20), freezeReason: .quietGap)

        let plan = LiveActivitySummaryCachePlanner.plan(
            clusters: [first, second, third],
            cachedKeys: [first.key, "stale-cache"],
            inFlightKeys: [second.key, "stale-flight"]
        )

        XCTAssertEqual(plan.requestedClusters.map(\.key), [third.key])
        XCTAssertEqual(plan.staleCacheKeys, ["stale-cache"])
        XCTAssertEqual(plan.staleInFlightKeys, ["stale-flight"])
    }
}

private func completedBatch(seed: Int = 0) -> [LiveLine] {
    [
        makeLine(offset: Double(seed) + 0, text: "Read package"),
        makeLine(
            offset: Double(seed) + 0.2,
            text: "Inspect source",
            kind: .command,
            status: .completed
        ),
        makeLine(
            offset: Double(seed) + 0.4,
            text: "Inspect tests",
            kind: .command,
            status: .completed
        ),
        makeLine(offset: Double(seed) + 0.6, text: "Review output", kind: .agentMessage),
        makeLine(
            offset: Double(seed) + 0.8,
            text: "Verify completed",
            kind: .command,
            status: .completed
        )
    ]
}

private func makeLine(
    offset: TimeInterval,
    text: String,
    detail: String? = nil,
    level: LiveLine.Level = .info,
    kind: LiveLine.Kind = .message,
    status: LiveLine.Status = .none
) -> LiveLine {
    var line = LiveLine(
        level: level,
        text: text,
        detail: detail,
        kind: kind,
        status: status
    )
    line.id = UUID(uuidString: uuidString(for: offset, text: text)) ?? UUID()
    line.date = date(offset)
    if status == .completed || status == .failed {
        line.completedAt = date(offset + 0.1)
    }
    return line
}

private func date(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000 + offset)
}

private func uuidString(for offset: TimeInterval, text: String) -> String {
    let value = UInt64(abs(Int(offset * 1000)) + text.utf8.reduce(0) { $0 + Int($1) })
    return String(format: "00000000-0000-0000-0000-%012llx", value)
}
