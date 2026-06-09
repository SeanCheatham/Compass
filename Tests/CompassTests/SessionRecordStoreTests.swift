import Foundation
import Testing

@testable import Compass

final class SessionRecordStoreTests {
  private var temporaryDirectories: [URL] = []

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  @Test func testWriteAndReadActiveJSONL() throws {
    let compassURL = try makeTemporaryDirectory(prefix: "SessionRecordStoreActive")
    let store = SessionRecordStore(compassURL: compassURL)
    let records = [makeRecord(1), makeRecord(2)]

    try store.writeActiveSessions(records)

    try #require(store.readActiveSessions() == records)
    try #require(FileManager.default.fileExists(atPath: store.activeRecordURL.path))
    let text = try String(contentsOf: store.activeRecordURL, encoding: .utf8)
    try #require(text.contains("\n"))
    try #require(!text.contains("[\n"))
  }

  @Test func testTokenSummaryPersistsAndOldRecordsDecode() throws {
    let compassURL = try makeTemporaryDirectory(prefix: "SessionRecordStoreTokens")
    let store = SessionRecordStore(compassURL: compassURL)
    var record = makeRecord(1)
    record.tokenSummary.record(
      SessionPhaseTokenUsage(
        phase: "plan",
        usage: AgentRunTokenUsage(
          inputTokens: 18_400,
          outputTokens: 2_100,
          totalTokens: 20_500,
          estimatedTokens: 0,
          streamedUsageAvailable: true,
          compactionCount: 1,
          summaryTokens: 900,
          retryCount: 1,
          durationMs: 12_000
        ),
        proofActionKind: "run_plan_proof",
        outcome: "accepted"
      )
    )

    try store.writeActiveSessions([record])

    let persisted = try #require(store.readActiveSessions().first)
    try #require(persisted.tokenSummary.totalTokens == 20_500)
    try #require(persisted.tokenSummary.compactionCount == 1)
    try #require(persisted.tokenSummary.latestProofActionKind == "run_plan_proof")

    let oldJSON = """
      {"session":2,"startedAt":1,"status":"succeeded","commits":[],"notes":[]}
      """
    let oldRecord = try JSONDecoder().decode(SessionRecord.self, from: Data(oldJSON.utf8))
    try #require(oldRecord.tokenSummary.isEmpty)
  }

  @Test func testRotationMovesOldestSessionsIntoArchive() throws {
    let compassURL = try makeTemporaryDirectory(prefix: "SessionRecordStoreRotate")
    let store = SessionRecordStore(compassURL: compassURL)
    var records: [SessionRecord] = []
    for number in 1...50 {
      records.append(makeLargeRecord(number))
    }

    try store.writeActiveSessions(records)

    try #require(store.hasArchivedSessions())
    try #require(store.activeSegmentAvailability() == .available)
    let active = store.readActiveSessions()
    let archived = store.readArchivedSessions()
    try #require(!active.isEmpty)
    try #require(!archived.isEmpty)
    try #require(active.count + archived.count == records.count)
    try #require(store.maxSessionNumber() == 50)
  }

  @Test func testPreviousFeedbackStreamsArchivedSessionsNewestFirst() throws {
    let compassURL = try makeTemporaryDirectory(prefix: "SessionRecordStoreFeedback")
    let store = SessionRecordStore(compassURL: compassURL)
    var older = makeRecord(1)
    older.feedback = "older feedback"
    older.endedAt = 1
    var newer = makeRecord(2)
    newer.feedback = "newer feedback"
    newer.endedAt = 2
    try store.writeActiveSessions([older, newer])

    let feedback = store.previousFeedback(
      excluding: 99,
      activeSessions: store.readActiveSessions()
    )
    try #require(feedback == "newer feedback")
  }

  @Test func testPreviousFeedbackUsesCompletionTimeBeforeStartTime() throws {
    let compassURL = try makeTemporaryDirectory(prefix: "SessionRecordStoreFeedbackEndedAt")
    let store = SessionRecordStore(compassURL: compassURL)
    var longRunning = makeRecord(1)
    longRunning.startedAt = 1_000
    longRunning.endedAt = 3_000
    longRunning.feedback = "completed later"
    var recentlyStarted = makeRecord(2)
    recentlyStarted.startedAt = 2_000
    recentlyStarted.endedAt = 2_100
    recentlyStarted.feedback = "started later"
    try store.writeActiveSessions([longRunning, recentlyStarted])

    let feedback = store.previousFeedback(
      excluding: 99,
      activeSessions: store.readActiveSessions()
    )
    try #require(feedback == "completed later")
  }

  private func makeLargeRecord(_ number: Int) -> SessionRecord {
    var record = makeRecord(number)
    record.notes = Array(repeating: String(repeating: "x", count: 400), count: 120)
    return record
  }

  private func makeRecord(_ number: Int) -> SessionRecord {
    var record = SessionRecord.started(number)
    record.status = .succeeded
    record.endedAt = Double(number)
    return record
  }

  private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "\(prefix)-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    temporaryDirectories.append(url)
    return url
  }
}
