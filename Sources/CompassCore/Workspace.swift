import Foundation

public struct CompassWorkspace {
  public var repoURL: URL
  private var injectedStorageRootURL: URL?

  public init(repoURL: URL, storageRootURL: URL? = nil) {
    self.repoURL = repoURL
    self.injectedStorageRootURL = storageRootURL
  }

  public static func repoLocalStorageRootURL(for repoURL: URL) -> URL {
    repoURL.appending(path: ".compass", directoryHint: .isDirectory)
  }

  public var repoLocalCompassURL: URL { Self.repoLocalStorageRootURL(for: repoURL) }
  public var storageRootURL: URL { injectedStorageRootURL ?? repoLocalCompassURL }
  public var compassURL: URL { storageRootURL }
  public var stateURL: URL { compassURL.appending(path: "state.json") }
  public var stateBackupURL: URL { compassURL.appending(path: "state.json.bak") }
  public var draftsURL: URL { compassURL.appending(path: "drafts.md") }
  public var lessonsURL: URL { compassURL.appending(path: "lessons.md") }
  public var assumptionsURL: URL { compassURL.appending(path: "assumptions.json") }
  public var visionURL: URL { compassURL.appending(path: "COMPASS.md") }
  public var sessionsURL: URL { compassURL.appending(path: "sessions", directoryHint: .isDirectory) }
  public var sessionsRecordURL: URL { sessionRecordStore.activeRecordURL }
  public var sessionRecordStore: SessionRecordStore {
    SessionRecordStore(compassURL: compassURL)
  }
  public var isRepoLocalStorage: Bool {
    compassURL.standardizedFileURL.path == repoLocalCompassURL.standardizedFileURL.path
  }

  public static func isGitRepository(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appending(path: ".git").path)
  }

  public static func discover(from startURL: URL) -> URL? {
    var current = startURL.standardizedFileURL

    while true {
      if isGitRepository(current) {
        return current
      }

      let parent = current.deletingLastPathComponent()
      if parent.path == current.path { return nil }
      current = parent
    }
  }

  public func initialize() throws {
    let fm = FileManager.default
    try fm.createDirectory(at: compassURL, withIntermediateDirectories: true)
    try fm.createDirectory(at: sessionsURL, withIntermediateDirectories: true)

    try createFileIfMissing(stateURL, contents: Self.encodeState(.empty))
    try createFileIfMissing(draftsURL, contents: "")
    try createFileIfMissing(lessonsURL, contents: "")
    try createFileIfMissing(assumptionsURL, contents: AssumptionLedger.emptyJSON)
    try createFileIfMissing(visionURL, contents: "")
    try createFileIfMissing(sessionsRecordURL, contents: "")
    if isRepoLocalStorage {
      try ensureCompassIsIgnored()
    }
  }

  public func readState() throws -> PlanState {
    guard FileManager.default.fileExists(atPath: stateURL.path) else {
      return .empty
    }
    let data = try Data(contentsOf: stateURL)
    if data.isEmpty { return .empty }
    return try JSONDecoder().decode(PlanState.self, from: data)
  }

  public func writeState(_ state: PlanState) throws {
    try Self.encodeState(state).write(to: stateURL, atomically: true, encoding: .utf8)
  }

  public func backupStateFile() throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: stateURL.path) else { return }
    if fm.fileExists(atPath: stateBackupURL.path) {
      try fm.removeItem(at: stateBackupURL)
    }
    try fm.copyItem(at: stateURL, to: stateBackupURL)
  }

  public func readDrafts() -> String {
    (try? String(contentsOf: draftsURL, encoding: .utf8)) ?? ""
  }

  public func writeDrafts(_ text: String) throws {
    try text.write(to: draftsURL, atomically: true, encoding: .utf8)
  }

  public func appendDraft(_ text: String) throws {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    var existing = readDrafts()
    if existing.isEmpty || existing.hasSuffix("\n\n") {
      // No separator needed.
    } else if existing.hasSuffix("\n") {
      existing += "\n"
    } else {
      existing += "\n\n"
    }
    existing += "- \(trimmed)\n"
    try writeDrafts(existing)
  }

  public func snapshotAndClearDrafts() throws -> String {
    let fm = FileManager.default
    let snapshotURL = draftsURL.deletingLastPathComponent()
      .appending(path: "\(draftsURL.lastPathComponent).snapshot")

    do {
      if fm.fileExists(atPath: snapshotURL.path) {
        try fm.removeItem(at: snapshotURL)
      }
      try fm.moveItem(at: draftsURL, to: snapshotURL)
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
    {
      return ""
    }

    try writeDrafts("")
    defer { try? fm.removeItem(at: snapshotURL) }
    return (try? String(contentsOf: snapshotURL, encoding: .utf8)) ?? ""
  }

  public func readLessons() -> String {
    (try? String(contentsOf: lessonsURL, encoding: .utf8)) ?? ""
  }

  public func writeLessons(_ text: String) throws {
    try text.write(to: lessonsURL, atomically: true, encoding: .utf8)
  }

  /// Dry-run lesson edits against the current lessons file without writing.
  public func validateLessonEdits(_ edits: [LessonEdit]) throws {
    guard !edits.isEmpty else { return }
    var current = readLessons()
    for edit in edits {
      current = try applyingLessonEdit(edit, to: current)
    }
  }

  /// Validate `lessonEdits` embedded in a phase submit payload.
  public func validateSubmitResultLessonEdits(_ submitResultJSON: Data) throws {
    let payload = try JSONDecoder().decode(
      SubmitResultLessonEditsPayload.self,
      from: submitResultJSON
    )
    try validateLessonEdits(payload.lessonEdits)
  }

  @discardableResult
  public func applyLessonEdits(_ edits: [LessonEdit]) throws -> Int {
    guard !edits.isEmpty else { return 0 }
    var current = readLessons()
    var applied = 0
    for edit in edits {
      current = try applyingLessonEdit(edit, to: current)
      applied += 1
    }
    try writeLessons(current)
    return applied
  }

  private func applyingLessonEdit(_ edit: LessonEdit, to current: String) throws -> String {
    if edit.find.isEmpty {
      guard current.isEmpty else {
        throw CompassWorkspaceError.lessonEditFailed(
          "Empty `find` is only allowed when lessons.md is empty."
        )
      }
      return edit.replace
    }

    let matches =
      (current.count
        - current.replacingOccurrences(of: edit.find, with: "", options: .literal).count)
      / edit.find.count
    guard matches > 0 else {
      throw CompassWorkspaceError.lessonEditFailed(
        "Lesson edit `find` text was not found in lessons.md.")
    }
    guard matches == 1 || edit.replaceAll == true else {
      throw CompassWorkspaceError.lessonEditFailed(
        "Lesson edit `find` text matched \(matches) times. Include more context or set replaceAll=true."
      )
    }

    let updated: String
    if edit.replaceAll == true {
      updated = current.replacingOccurrences(of: edit.find, with: edit.replace)
    } else if let range = current.range(of: edit.find) {
      updated = current.replacingCharacters(in: range, with: edit.replace)
    } else {
      throw CompassWorkspaceError.lessonEditFailed(
        "Lesson edit `find` text was not found in lessons.md.")
    }
    return updated
  }

  public func readVision() -> String {
    (try? String(contentsOf: visionURL, encoding: .utf8)) ?? ""
  }

  public func writeVision(_ text: String) throws {
    try text.write(to: visionURL, atomically: true, encoding: .utf8)
  }

  public func readSessions(includeArchived: Bool = false) -> [SessionRecord] {
    let store = sessionRecordStore
    if includeArchived {
      return store.readAllSessions()
    }
    return store.readActiveSessions()
  }

  public func readArchivedSessions() -> [SessionRecord] {
    sessionRecordStore.readArchivedSessions()
  }

  public func hasArchivedSessions() -> Bool {
    sessionRecordStore.hasArchivedSessions()
  }

  public func maxSessionNumber() -> Int {
    sessionRecordStore.maxSessionNumber()
  }

  public func previousSessionFeedback(excluding session: Int, activeSessions: [SessionRecord]) -> String {
    sessionRecordStore.previousFeedback(excluding: session, activeSessions: activeSessions)
  }

  public func writeSessions(_ records: [SessionRecord]) throws {
    try sessionRecordStore.writeActiveSessions(records)
  }

  public func writeSessionArtifact(session: Int, name: String, contents: String) throws -> URL {
    try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
    let safeName =
      name
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
    let url = sessionsURL.appending(path: "\(session)-\(safeName)")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  public func sessionAuditDirectoryURL(session: Int) -> URL {
    sessionsURL.appending(
      path: Self.sessionAuditDirectoryName(session),
      directoryHint: .isDirectory
    )
  }

  public func sessionAuditManifestURL(session: Int) -> URL {
    sessionAuditDirectoryURL(session: session).appending(path: "manifest.json")
  }

  public func sessionAuditEventsURL(session: Int) -> URL {
    sessionAuditDirectoryURL(session: session).appending(path: "events.jsonl")
  }

  public func sessionAuditEventCount(session: Int) -> Int {
    let url = sessionAuditEventsURL(session: session)
    guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
      return 0
    }
    return text.split(whereSeparator: \.isNewline).count
  }

  public func readSessionAuditManifest(session: Int) -> SessionAuditManifest? {
    let url = sessionAuditManifestURL(session: session)
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    return try? JSONDecoder().decode(SessionAuditManifest.self, from: data)
  }

  public func writeSessionAuditManifest(_ manifest: SessionAuditManifest) throws {
    try FileManager.default.createDirectory(
      at: sessionAuditDirectoryURL(session: manifest.session),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    try data.write(to: sessionAuditManifestURL(session: manifest.session), options: .atomic)
  }

  public func updateSessionAuditManifest(
    session: Int,
    status: SessionStatus?,
    startedAt: Double?,
    endedAt: Double?
  ) throws {
    var manifest =
      readSessionAuditManifest(session: session)
      ?? SessionAuditManifest(
        session: session,
        status: status,
        startedAt: startedAt,
        endedAt: endedAt
      )
    manifest.update(status: status, startedAt: startedAt, endedAt: endedAt)
    try writeSessionAuditManifest(manifest)
  }

  public func appendSessionAuditEvent(_ event: SessionAuditEvent) throws {
    try FileManager.default.createDirectory(
      at: sessionAuditDirectoryURL(session: event.session),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(event)
    let url = sessionAuditEventsURL(session: event.session)
    if !FileManager.default.fileExists(atPath: url.path) {
      _ = FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    try handle.write(contentsOf: Data("\n".utf8))
  }

  public func writeSessionAuditArtifact(
    session: Int,
    name: String,
    kind: String,
    contents: String,
    note: String? = nil
  ) throws -> URL {
    try writeSessionAuditArtifactData(
      session: session,
      name: name,
      kind: kind,
      data: Data(contents.utf8),
      note: note
    )
  }

  public func writeSessionAuditArtifactData(
    session: Int,
    name: String,
    kind: String,
    data: Data,
    note: String? = nil
  ) throws -> URL {
    let directory = sessionAuditDirectoryURL(session: session)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let safeName = Self.safeSessionAuditFileName(name)
    let url = uniqueAuditArtifactURL(directory: directory, safeName: safeName)
    try data.write(to: url, options: .atomic)
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    let byteCount = (attributes?[.size] as? NSNumber)?.uint64Value ?? UInt64(data.count)
    let artifact = SessionAuditArtifact(
      path: sessionAuditRelativePath(session: session, fileName: url.lastPathComponent),
      kind: kind,
      byteCount: byteCount,
      note: note
    )
    var manifest =
      readSessionAuditManifest(session: session)
      ?? SessionAuditManifest(session: session)
    manifest.recordArtifact(artifact)
    try writeSessionAuditManifest(manifest)
    return url
  }

  public func sessionAuditRelativePath(session: Int, fileName: String) -> String {
    "sessions/\(Self.sessionAuditDirectoryName(session))/\(fileName)"
  }

  public static func encodeState(_ state: PlanState) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(state)
    return String(decoding: data, as: UTF8.self) + "\n"
  }

  private func uniqueAuditArtifactURL(directory: URL, safeName: String) -> URL {
    let first = directory.appending(path: safeName)
    guard FileManager.default.fileExists(atPath: first.path) else { return first }

    let nsName = safeName as NSString
    let base = nsName.deletingPathExtension
    let ext = nsName.pathExtension
    for index in 2...10_000 {
      let candidateName =
        ext.isEmpty
        ? "\(base)-\(index)"
        : "\(base)-\(index).\(ext)"
      let candidate = directory.appending(path: candidateName)
      if !FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
    }
    return directory.appending(path: "\(UUID().uuidString)-\(safeName)")
  }

  public static func sessionAuditDirectoryName(_ session: Int) -> String {
    String(format: "%06d", max(0, session))
  }

  public static func safeSessionAuditFileName(_ name: String) -> String {
    let invalid = CharacterSet(charactersIn: "/:\\")
      .union(.newlines)
      .union(.controlCharacters)
    let parts = name.components(separatedBy: invalid)
    let safe = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    return safe.isEmpty ? "artifact.txt" : safe
  }

  public static func encodeProposal(_ proposal: PlanProposal) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(proposal)
    return String(decoding: data, as: UTF8.self) + "\n"
  }

  private func createFileIfMissing(_ url: URL, contents: String) throws {
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func ensureCompassIsIgnored() throws {
    let gitignoreURL = repoURL.appending(path: ".gitignore")
    let marker = ".compass/"
    var text = (try? String(contentsOf: gitignoreURL, encoding: .utf8)) ?? ""
    let alreadyIgnored =
      text
      .split(whereSeparator: \.isNewline)
      .contains {
        let line = $0.trimmingCharacters(in: .whitespaces)
        return line == marker || line == ".compass"
      }
    guard !alreadyIgnored else { return }

    if !text.isEmpty && !text.hasSuffix("\n") {
      text += "\n"
    }
    text += "\(marker)\n"
    try text.write(to: gitignoreURL, atomically: true, encoding: .utf8)
  }
}

private struct SubmitResultLessonEditsPayload: Decodable {
  public var lessonEdits: [LessonEdit]

  public enum CodingKeys: String, CodingKey {
    case lessonEdits
    case lessonEditsSnake = "lesson_edits"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    lessonEdits =
      try FlexibleModelDecoder.decodeLessonEditsIfPresent(
        from: container,
        preferredKey: .lessonEdits,
        aliases: [.lessonEditsSnake]
      ) ?? []
  }
}

private enum CompassWorkspaceError: LocalizedError {
  case lessonEditFailed(String)

  public var errorDescription: String? {
    switch self {
    case .lessonEditFailed(let message):
      return message
    }
  }
}
