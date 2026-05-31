import Foundation

struct SessionRecordStore: Equatable {
  static let maxSegmentBytes: UInt64 = 2 * 1024 * 1024
  static let activeFileName = "sessions.jsonl"
  static let archiveDirectoryName = "sessions-archive"
  static let archiveSegmentPrefix = "sessions-"
  static let archiveSegmentSuffix = ".jsonl"

  var compassURL: URL
  var fileManager: FileManager

  init(compassURL: URL, fileManager: FileManager = .default) {
    self.compassURL = compassURL.standardizedFileURL
    self.fileManager = fileManager
  }

  var activeRecordURL: URL {
    compassURL.appending(path: Self.activeFileName)
  }

  var archiveDirectoryURL: URL {
    compassURL.appending(path: Self.archiveDirectoryName, directoryHint: .isDirectory)
  }

  func hasSessionsRecord() -> Bool {
    fileExists(activeRecordURL)
  }

  func hasArchivedSessions() -> Bool {
    !archiveSegmentURLs().isEmpty
  }

  func readActiveSessions() -> [SessionRecord] {
    guard fileExists(activeRecordURL) else { return [] }
    return (try? decodeJSONLFile(at: activeRecordURL)) ?? []
  }

  func readArchivedSessions() -> [SessionRecord] {
    var merged: [SessionRecord] = []
    for url in archiveSegmentURLs() {
      _ = try? streamDecodeJSONLFile(at: url, into: &merged)
    }
    return deduplicatedSortedRecords(merged)
  }

  func readAllSessions() -> [SessionRecord] {
    deduplicatedSortedRecords(readArchivedSessions() + readActiveSessions())
  }

  func writeActiveSessions(_ records: [SessionRecord]) throws {
    try fileManager.createDirectory(at: compassURL, withIntermediateDirectories: true)
    var remaining = deduplicatedSortedRecords(records)
    while remaining.count > 1,
      encodedJSONLByteCount(for: remaining) > Self.maxSegmentBytes
    {
      let overflowCount = overflowSessionCount(for: remaining)
      guard overflowCount > 0, overflowCount < remaining.count else { break }
      let archived = Array(remaining.prefix(overflowCount))
      remaining.removeFirst(overflowCount)
      try appendArchiveSegment(archived)
    }
    try writeJSONL(remaining, to: activeRecordURL)
  }

  func maxSessionNumber() -> Int {
    var maxNumber = 0
    if fileExists(activeRecordURL) {
      maxNumber = max(maxNumber, (try? maxSessionNumber(inJSONLFile: activeRecordURL)) ?? 0)
    }
    for url in archiveSegmentURLs() {
      maxNumber = max(maxNumber, (try? maxSessionNumber(inJSONLFile: url)) ?? 0)
    }
    return maxNumber
  }

  func previousFeedback(excluding session: Int, activeSessions: [SessionRecord]) -> String {
    if let feedback = newestFeedback(in: activeSessions, excluding: session) {
      return feedback
    }
    for url in archiveSegmentURLs().reversed() {
      var found: String?
      do {
        try streamJSONLFile(at: url) { record in
          guard record.session != session,
            record.endedAt != nil,
            let trimmed = record.feedback?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
          else { return }
          found = trimmed
          throw StreamSearchStop()
        }
      } catch is StreamSearchStop {
        if let found { return found }
      } catch {
        continue
      }
      if let found { return found }
    }
    return ""
  }

  func activeSegmentAvailability() -> RepositoryActivitySourceSnapshot.SourceAvailability {
    availability(forPrimaryRecordAt: activeRecordURL)
  }

  func validatePrimaryRecord() throws {
    let availability = activeSegmentAvailability()
    switch availability {
    case .available:
      return
    case .sessionsRecordMissing:
      throw SessionRecordStoreError.missingRecord
    case .sessionsRecordOversized:
      throw SessionRecordStoreError.oversizedRecord
    case .sessionsRecordUnreadable:
      throw SessionRecordStoreError.unreadableRecord
    case .noRepository, .notScanned, .storageRootMissing:
      throw SessionRecordStoreError.unreadableRecord
    }
  }

  private func availability(
    forPrimaryRecordAt url: URL
  ) -> RepositoryActivitySourceSnapshot.SourceAvailability {
    guard directoryExists(compassURL) else {
      return .storageRootMissing
    }
    guard fileExists(url) else {
      return .sessionsRecordMissing
    }

    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
      let size = attributes[.size] as? NSNumber
    else {
      return .sessionsRecordUnreadable
    }
    guard size.uint64Value <= Self.maxSegmentBytes else {
      return .sessionsRecordOversized
    }
    guard (try? validateRecordFile(at: url)) == true else {
      return .sessionsRecordUnreadable
    }
    return .available
  }

  private func validateRecordFile(at url: URL) throws -> Bool {
    try streamJSONLFile(at: url) { _ in }
    return true
  }

  private func overflowSessionCount(for records: [SessionRecord]) -> Int {
    guard records.count > 1 else { return 0 }
    var removable = 0
    for count in 1..<records.count {
      let candidate = Array(records.dropFirst(count))
      if encodedJSONLByteCount(for: candidate) <= Self.maxSegmentBytes {
        removable = count
        break
      }
    }
    return removable
  }

  private func appendArchiveSegment(_ records: [SessionRecord]) throws {
    guard !records.isEmpty else { return }
    try fileManager.createDirectory(at: archiveDirectoryURL, withIntermediateDirectories: true)
    let nextIndex = (archiveSegmentURLs().compactMap { archiveIndex(from: $0) }.max() ?? 0) + 1
    let url = archiveDirectoryURL.appending(path: archiveFilename(for: nextIndex))
    try writeJSONL(records, to: url)
  }

  private func archiveFilename(for index: Int) -> String {
    String(format: "\(Self.archiveSegmentPrefix)%06d\(Self.archiveSegmentSuffix)", index)
  }

  private func archiveIndex(from url: URL) -> Int? {
    let name = url.lastPathComponent
    guard name.hasPrefix(Self.archiveSegmentPrefix),
      name.hasSuffix(Self.archiveSegmentSuffix)
    else { return nil }
    let start = name.index(name.startIndex, offsetBy: Self.archiveSegmentPrefix.count)
    let end = name.index(name.endIndex, offsetBy: -Self.archiveSegmentSuffix.count)
    return Int(name[start..<end])
  }

  private func archiveSegmentURLs() -> [URL] {
    guard directoryExists(archiveDirectoryURL),
      let contents = try? fileManager.contentsOfDirectory(
        at: archiveDirectoryURL,
        includingPropertiesForKeys: nil
      )
    else { return [] }
    return
      contents
      .filter { archiveIndex(from: $0) != nil }
      .sorted {
        (archiveIndex(from: $0) ?? 0) < (archiveIndex(from: $1) ?? 0)
      }
  }

  private func decodeJSONLFile(at url: URL) throws -> [SessionRecord] {
    var records: [SessionRecord] = []
    try streamDecodeJSONLFile(at: url, into: &records)
    return records
  }

  @discardableResult
  private func streamDecodeJSONLFile(at url: URL, into records: inout [SessionRecord]) throws
    -> [SessionRecord]
  {
    try streamJSONLFile(at: url) { record in
      records.append(record)
    }
    return records
  }

  private func streamJSONLFile(
    at url: URL,
    visitor: (SessionRecord) throws -> Void
  ) throws {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var buffer = ""
    let decoder = JSONDecoder()
    while true {
      let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
      if chunk.isEmpty {
        break
      }
      buffer += String(decoding: chunk, as: UTF8.self)
      while let newlineRange = buffer.range(of: "\n") {
        let line = String(buffer[..<newlineRange.lowerBound])
        buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
        try decodeJSONLLine(line, decoder: decoder, visitor: visitor)
      }
    }
    if !buffer.isEmpty {
      try decodeJSONLLine(buffer, decoder: decoder, visitor: visitor)
    }
  }

  private func decodeJSONLLine(
    _ line: String,
    decoder: JSONDecoder,
    visitor: (SessionRecord) throws -> Void
  ) throws {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let record = try decoder.decode(SessionRecord.self, from: Data(trimmed.utf8))
    try visitor(record)
  }

  private func maxSessionNumber(inJSONLFile url: URL) throws -> Int {
    var maxNumber = 0
    try streamJSONLFile(at: url) { record in
      maxNumber = max(maxNumber, record.session)
    }
    return maxNumber
  }

  private func writeJSONL(_ records: [SessionRecord], to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let lines =
      try records.map { record -> String in
        let data = try encoder.encode(record)
        return String(decoding: data, as: UTF8.self)
      }
    let text =
      lines.isEmpty
      ? ""
      : lines.joined(separator: "\n") + "\n"
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  private func encodedJSONLByteCount(for records: [SessionRecord]) -> UInt64 {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var total: UInt64 = 0
    for record in records {
      guard let data = try? encoder.encode(record) else { continue }
      total += UInt64(data.count) + 1
    }
    return total
  }

  private func deduplicatedSortedRecords(_ records: [SessionRecord]) -> [SessionRecord] {
    var bySession: [Int: SessionRecord] = [:]
    for record in records {
      bySession[record.session] = record
    }
    return bySession.values.sorted { lhs, rhs in
      if lhs.session == rhs.session {
        return lhs.startedAt < rhs.startedAt
      }
      return lhs.session < rhs.session
    }
  }

  private func newestFeedback(
    in sessions: [SessionRecord],
    excluding session: Int
  ) -> String? {
    sessions
      .filter { $0.session != session && $0.endedAt != nil }
      .sorted { $0.startedAt > $1.startedAt }
      .compactMap { $0.feedback?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
  }

  private func fileExists(_ url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && !isDirectory.boolValue
  }

  private func directoryExists(_ url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }
}

enum SessionRecordStoreError: Error, Equatable {
  case missingRecord
  case oversizedRecord
  case unreadableRecord
}

private struct StreamSearchStop: Error {}
