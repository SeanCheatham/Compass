import Foundation
import XCTest

@testable import Compass

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
      makeLine(offset: 1.5, text: "Next live row"),
    ]

    let plan = LiveActivitySummaryPlanner.plan(
      lines: lines,
      now: date(2)
    )

    XCTAssertEqual(plan.frozenClusters.count, 1)
    let cluster = try XCTUnwrap(plan.frozenClusters.first)
    XCTAssertEqual(cluster.lines.map(\.id), Array(lines.prefix(5)).map(\.id))
    XCTAssertEqual(cluster.freezeReason, .lifecycleBoundary)
    XCTAssertEqual(plan.items.last, .line(lines[5]))
  }

  func testFreezesClusterAtQuietGap() throws {
    let lines = [
      makeLine(offset: 0, text: "Read package"),
      makeLine(offset: 0.2, text: "Inspect source", kind: .command, status: .completed),
      makeLine(offset: 0.4, text: "Inspect tests", kind: .command, status: .completed),
      makeLine(offset: 0.6, text: "Patch summary", kind: .agentMessage),
      makeLine(offset: 0.8, text: "Render row"),
      makeLine(offset: 45, text: "Resume activity"),
    ]

    let plan = LiveActivitySummaryPlanner.plan(
      lines: lines,
      now: date(46)
    )

    XCTAssertEqual(plan.frozenClusters.count, 1)
    let cluster = try XCTUnwrap(plan.frozenClusters.first)
    XCTAssertEqual(cluster.lines.map(\.id), Array(lines.prefix(5)).map(\.id))
    XCTAssertEqual(cluster.freezeReason, .quietGap)
    XCTAssertEqual(plan.items.last, .line(lines[5]))
  }

  func testFreezesClusterAfterElapsedSinceStartUnderSustainedActivity() throws {
    let lines = [
      makeLine(offset: 0, text: "Read package"),
      makeLine(offset: 1, text: "Inspect source", kind: .command, status: .completed),
      makeLine(offset: 5, text: "Inspect tests", kind: .command, status: .completed),
      makeLine(offset: 18, text: "Patch summary", kind: .agentMessage),
      makeLine(offset: 31, text: "Continuing", kind: .command, status: .completed),
      makeLine(offset: 33, text: "Next step", kind: .command, status: .completed),
    ]

    let plan = LiveActivitySummaryPlanner.plan(
      lines: lines,
      now: date(34)
    )

    XCTAssertEqual(plan.frozenClusters.count, 1)
    let cluster = try XCTUnwrap(plan.frozenClusters.first)
    XCTAssertEqual(cluster.lines.map(\.id), Array(lines.prefix(4)).map(\.id))
    XCTAssertEqual(cluster.freezeReason, .elapsedSinceStart)
  }

  func testDoesNotFreezeBelowElapsedThreshold() {
    let lines = [
      makeLine(offset: 0, text: "Read package"),
      makeLine(offset: 1, text: "Inspect source", kind: .command, status: .completed),
      makeLine(offset: 2, text: "Inspect tests", kind: .command, status: .completed),
      makeLine(offset: 3, text: "Patch summary", kind: .agentMessage),
      makeLine(offset: 4, text: "Render row"),
    ]

    let plan = LiveActivitySummaryPlanner.plan(
      lines: lines,
      now: date(10)
    )

    XCTAssertTrue(plan.frozenClusters.isEmpty)
  }

  func testRunningLifecycleMarkersDoNotBlockFreezing() throws {
    let lines = [
      makeLine(offset: 0, text: "Agent iteration 1", kind: .lifecycle, status: .running),
      makeLine(offset: 1, text: "Inspect source", kind: .command, status: .completed),
      makeLine(offset: 2, text: "Inspect tests", kind: .command, status: .completed),
      makeLine(offset: 3, text: "Patch summary", kind: .agentMessage),
      makeLine(offset: 40, text: "Resume activity"),
    ]

    let plan = LiveActivitySummaryPlanner.plan(
      lines: lines,
      now: date(41)
    )

    XCTAssertEqual(plan.frozenClusters.count, 1)
    let cluster = try XCTUnwrap(plan.frozenClusters.first)
    XCTAssertEqual(cluster.lines.map(\.id), Array(lines.prefix(4)).map(\.id))
  }

  func testRunningCommandRowsBlockFreezing() {
    let lines = [
      makeLine(offset: 0, text: "Read package"),
      makeLine(offset: 1, text: "Inspect source", kind: .command, status: .completed),
      makeLine(offset: 2, text: "Inspect tests", kind: .command, status: .completed),
      makeLine(offset: 3, text: "Patch summary", kind: .agentMessage),
      makeLine(offset: 4, text: "Running verify", kind: .command, status: .running),
    ]

    let plan = LiveActivitySummaryPlanner.plan(
      lines: lines,
      now: date(50)
    )

    XCTAssertTrue(plan.frozenClusters.isEmpty)
    XCTAssertEqual(plan.items, lines.map(LiveActivitySummaryItem.line))
  }

  func testClusterKeyIsStableForUnchangedRows() throws {
    let lines = completedBatch()

    let first = LiveActivitySummaryPlanner.plan(lines: lines, now: date(40))
    let second = LiveActivitySummaryPlanner.plan(lines: lines, now: date(40))

    XCTAssertEqual(first.frozenClusters.first?.key, second.frozenClusters.first?.key)
  }

  func testClusterKeyChangesWhenRunningRowCompletesInPlace() {
    var running = completedBatch()
    running[2].status = .running
    running[2].text = "Running verify"
    let runningCluster = LiveActivityCluster(
      lines: running,
      freezeReason: .quietGap
    )

    var completed = running
    completed[2].status = .completed
    completed[2].text = "Verify completed"
    let completedCluster = LiveActivityCluster(
      lines: completed,
      freezeReason: .quietGap
    )

    XCTAssertEqual(running[2].id, completed[2].id)
    XCTAssertNotEqual(runningCluster.key, completedCluster.key)
  }

  func testParserAcceptsTwoSentenceProse() throws {
    let cluster = LiveActivityCluster(lines: completedBatch(), freezeReason: .quietGap)

    let summary = try XCTUnwrap(
      LiveActivitySummaryService.parseGeneratedSummary(
        "The agent inspected the source and tests, then reviewed the output. No failures were reported.",
        cluster: cluster
      )
    )

    XCTAssertTrue(summary.text.hasPrefix("The agent"))
    XCTAssertEqual(summary.source, .generated)
  }

  func testParserStripsSummaryLabel() throws {
    let cluster = LiveActivityCluster(lines: completedBatch(), freezeReason: .quietGap)

    let summary = try XCTUnwrap(
      LiveActivitySummaryService.parseGeneratedSummary(
        "Summary: The agent inspected the source and tests. The review wrapped up cleanly.",
        cluster: cluster
      )
    )

    XCTAssertFalse(summary.text.lowercased().hasPrefix("summary:"))
  }

  func testParserCollapsesMultilineProseIntoOneLine() throws {
    let cluster = LiveActivityCluster(lines: completedBatch(), freezeReason: .quietGap)

    let summary = try XCTUnwrap(
      LiveActivitySummaryService.parseGeneratedSummary(
        "The agent inspected the source and tests.\nThe review wrapped up cleanly.",
        cluster: cluster
      )
    )

    XCTAssertFalse(summary.text.contains("\n"))
  }

  func testParserRejectsMarkdownJSONURLsAndOverlongOutput() {
    let cluster = LiveActivityCluster(lines: completedBatch(), freezeReason: .quietGap)

    XCTAssertNil(
      LiveActivitySummaryService.parseGeneratedSummary(
        "```The agent inspected the source.```",
        cluster: cluster
      )
    )
    XCTAssertNil(
      LiveActivitySummaryService.parseGeneratedSummary(
        #"{"summary":"The agent inspected the source."}"#,
        cluster: cluster
      )
    )
    XCTAssertNil(
      LiveActivitySummaryService.parseGeneratedSummary(
        "The agent reviewed https://example.com output.",
        cluster: cluster
      )
    )
    XCTAssertNil(
      LiveActivitySummaryService.parseGeneratedSummary(
        String(repeating: "word ", count: 200),
        cluster: cluster
      )
    )
  }

  func testParserAllowsNumbersFilenamesAndOutcomeWords() throws {
    let cluster = LiveActivityCluster(lines: completedBatch(), freezeReason: .quietGap)

    let summary = try XCTUnwrap(
      LiveActivitySummaryService.parseGeneratedSummary(
        "The agent ran 12 commands across README.md and the test suite. All checks passed.",
        cluster: cluster
      )
    )

    XCTAssertTrue(summary.text.contains("12 commands"))
    XCTAssertTrue(summary.text.contains("passed"))
  }

  func testDeterministicFallbackDescribesCountsAndIsStable() {
    let cluster = LiveActivityCluster(lines: completedBatch(), freezeReason: .quietGap)

    let summary = LiveActivitySummaryService.deterministicSummary(for: cluster)
    let repeated = LiveActivitySummaryService.deterministicSummary(for: cluster)

    XCTAssertEqual(summary, repeated)
    XCTAssertEqual(summary.source, .deterministic)
    XCTAssertTrue(summary.text.hasPrefix("The agent"))
    XCTAssertTrue(summary.text.contains("2 commands"))
    XCTAssertTrue(summary.text.contains("1 agent note"))
    XCTAssertLessThanOrEqual(
      summary.text.count,
      LiveActivitySummaryService.summaryMaxCharacters
    )
  }

  func testDeterministicFallbackReportsFailures() {
    var lines = completedBatch()
    lines[1].status = .failed
    let cluster = LiveActivityCluster(lines: lines, freezeReason: .quietGap)

    let summary = LiveActivitySummaryService.deterministicSummary(for: cluster)

    XCTAssertTrue(summary.text.contains("One failure reported"))
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
    makeLine(
      offset: Double(seed) + 0,
      text: "Inspect source",
      kind: .command,
      status: .completed
    ),
    makeLine(
      offset: Double(seed) + 0.2,
      text: "Inspect tests",
      kind: .command,
      status: .completed
    ),
    makeLine(offset: Double(seed) + 0.4, text: "Review output", kind: .agentMessage),
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
