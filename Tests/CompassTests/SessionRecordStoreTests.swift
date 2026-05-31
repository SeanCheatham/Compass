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
