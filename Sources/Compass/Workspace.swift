import Foundation

struct CompassWorkspace {
  var repoURL: URL
  private var injectedStorageRootURL: URL?

  init(repoURL: URL, storageRootURL: URL? = nil) {
    self.repoURL = repoURL
    self.injectedStorageRootURL = storageRootURL
  }

  static func repoLocalStorageRootURL(for repoURL: URL) -> URL {
    repoURL.appending(path: ".compass", directoryHint: .isDirectory)
  }

  var repoLocalCompassURL: URL { Self.repoLocalStorageRootURL(for: repoURL) }
  var storageRootURL: URL { injectedStorageRootURL ?? repoLocalCompassURL }
  var compassURL: URL { storageRootURL }
  var stateURL: URL { compassURL.appending(path: "state.json") }
  var stateBackupURL: URL { compassURL.appending(path: "state.json.bak") }
  var draftsURL: URL { compassURL.appending(path: "drafts.md") }
  var lessonsURL: URL { compassURL.appending(path: "lessons.md") }
  var visionURL: URL { compassURL.appending(path: "COMPASS.md") }
  var sessionsURL: URL { compassURL.appending(path: "sessions", directoryHint: .isDirectory) }
  var sessionsRecordURL: URL { compassURL.appending(path: "sessions.json") }
  var isRepoLocalStorage: Bool {
    compassURL.standardizedFileURL.path == repoLocalCompassURL.standardizedFileURL.path
  }

  static func isGitRepository(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appending(path: ".git").path)
  }

  static func discover(from startURL: URL) -> URL? {
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

  static func normalizedURL(from path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
      .standardizedFileURL
  }

  func initialize() throws {
    let fm = FileManager.default
    try fm.createDirectory(at: compassURL, withIntermediateDirectories: true)
    try fm.createDirectory(at: sessionsURL, withIntermediateDirectories: true)

    try createFileIfMissing(stateURL, contents: Self.encodeState(.empty))
    try createFileIfMissing(draftsURL, contents: "")
    try createFileIfMissing(lessonsURL, contents: "")
    try createFileIfMissing(visionURL, contents: "")
    try createFileIfMissing(sessionsRecordURL, contents: "[]\n")
    if isRepoLocalStorage {
      try ensureCompassIsIgnored()
    }
  }

  func readState() throws -> PlanState {
    guard FileManager.default.fileExists(atPath: stateURL.path) else {
      return .empty
    }
    let data = try Data(contentsOf: stateURL)
    if data.isEmpty { return .empty }
    return try JSONDecoder().decode(PlanState.self, from: data)
  }

  func writeState(_ state: PlanState) throws {
    try Self.encodeState(state).write(to: stateURL, atomically: true, encoding: .utf8)
  }

  func backupStateFile() throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: stateURL.path) else { return }
    if fm.fileExists(atPath: stateBackupURL.path) {
      try fm.removeItem(at: stateBackupURL)
    }
    try fm.copyItem(at: stateURL, to: stateBackupURL)
  }

  func readDrafts() -> String {
    (try? String(contentsOf: draftsURL, encoding: .utf8)) ?? ""
  }

  func writeDrafts(_ text: String) throws {
    try text.write(to: draftsURL, atomically: true, encoding: .utf8)
  }

  func appendDraft(_ text: String) throws {
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

  func snapshotAndClearDrafts() throws -> String {
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

  func readLessons() -> String {
    (try? String(contentsOf: lessonsURL, encoding: .utf8)) ?? ""
  }

  func writeLessons(_ text: String) throws {
    try text.write(to: lessonsURL, atomically: true, encoding: .utf8)
  }

  /// Dry-run lesson edits against the current lessons file without writing.
  func validateLessonEdits(_ edits: [LessonEdit]) throws {
    guard !edits.isEmpty else { return }
    var current = readLessons()
    for edit in edits {
      current = try applyingLessonEdit(edit, to: current)
    }
  }

  /// Validate `lessonEdits` embedded in a phase's `submit_result` payload.
  func validateSubmitResultLessonEdits(_ submitResultJSON: Data) throws {
    struct Payload: Decodable {
      var lessonEdits: [LessonEdit]
    }
    let payload = try JSONDecoder().decode(Payload.self, from: submitResultJSON)
    try validateLessonEdits(payload.lessonEdits)
  }

  @discardableResult
  func applyLessonEdits(_ edits: [LessonEdit]) throws -> Int {
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

    let matches = current.nonOverlappingOccurrences(of: edit.find)
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

  func readVision() -> String {
    (try? String(contentsOf: visionURL, encoding: .utf8)) ?? ""
  }

  func writeVision(_ text: String) throws {
    try text.write(to: visionURL, atomically: true, encoding: .utf8)
  }

  func readSessions() -> [SessionRecord] {
    guard let data = try? Data(contentsOf: sessionsRecordURL), !data.isEmpty else {
      return []
    }
    return (try? JSONDecoder().decode([SessionRecord].self, from: data)) ?? []
  }

  func writeSessions(_ records: [SessionRecord]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(records)
    let text = String(decoding: data, as: UTF8.self) + "\n"
    try text.write(to: sessionsRecordURL, atomically: true, encoding: .utf8)
  }

  func writeSessionArtifact(session: Int, name: String, contents: String) throws -> URL {
    try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
    let safeName =
      name
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
    let url = sessionsURL.appending(path: "\(session)-\(safeName)")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  static func encodeState(_ state: PlanState) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(state)
    return String(decoding: data, as: UTF8.self) + "\n"
  }

  static func encodeProposal(_ proposal: PlanProposal) throws -> String {
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

struct CompassWorkspaceStorageAssessment: Equatable {
  static let maxProjectIdentifierLength = 64
  static let labelLimit = 34
  static let detailLimit = 180
  static let recommendationLimit = 140
  static let repairActionLabelLimit = 24
  static let repairActionHelpLimit = 140

  var repoURL: URL
  var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots
  var projectStorageIdentifier: String
  var currentApplicationSupportCandidateURL: URL
  var facts: Facts
  var issues: [Issue]
  var primaryIssue: Issue
  var repairAction: RepairAction?

  var kind: Kind { primaryIssue.kind }
  var severity: Severity { primaryIssue.severity }
  var label: String { primaryIssue.label }
  var detail: String { primaryIssue.detail }
  var recommendation: String { primaryIssue.recommendation }
  var systemImage: String { primaryIssue.systemImage }
  var isHealthy: Bool { issues.isEmpty }

  init(
    repoURL: URL,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots =
      KnownProjectStore.productionApplicationSupportRoots(),
    fileManager: FileManager = .default
  ) {
    let standardizedRepoURL = repoURL.standardizedFileURL
    let identifier = Self.projectStorageIdentifier(for: standardizedRepoURL)
    let currentCandidateURL = Self.currentApplicationSupportCandidateURL(
      for: standardizedRepoURL,
      applicationSupportRoots: applicationSupportRoots,
      identifier: identifier
    )
    let facts = Self.collectFacts(
      repoURL: standardizedRepoURL,
      currentCandidateURL: currentCandidateURL,
      fileManager: fileManager
    )
    self.init(
      repoURL: standardizedRepoURL,
      applicationSupportRoots: applicationSupportRoots,
      projectStorageIdentifier: identifier,
      currentApplicationSupportCandidateURL: currentCandidateURL,
      facts: facts
    )
  }

  init(
    repoURL: URL,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots,
    projectStorageIdentifier: String? = nil,
    currentApplicationSupportCandidateURL: URL? = nil,
    facts: Facts
  ) {
    let standardizedRepoURL = repoURL.standardizedFileURL
    let identifier =
      projectStorageIdentifier ?? Self.projectStorageIdentifier(for: standardizedRepoURL)
    let currentCandidateURL =
      currentApplicationSupportCandidateURL
      ?? Self.currentApplicationSupportCandidateURL(
        for: standardizedRepoURL,
        applicationSupportRoots: applicationSupportRoots,
        identifier: identifier
      )

    self.repoURL = standardizedRepoURL
    self.applicationSupportRoots = applicationSupportRoots
    self.projectStorageIdentifier = Self.boundedIdentifier(identifier)
    self.currentApplicationSupportCandidateURL = currentCandidateURL
    self.facts = facts

    let derivedIssues = Self.issues(
      facts: facts,
      repoURL: standardizedRepoURL,
      currentCandidateURL: currentCandidateURL
    )
    issues = derivedIssues
    primaryIssue = derivedIssues.first ?? Self.healthyIssue(repoURL: standardizedRepoURL)
    repairAction = Self.repairAction(for: derivedIssues)
  }

  static func projectStorageIdentifier(for repoURL: URL) -> String {
    let slugLimit = max(8, maxProjectIdentifierLength - 17)
    let fallback = repoURL.lastPathComponent.isEmpty ? "project" : repoURL.lastPathComponent
    let slug = sanitizedSlug(from: fallback, limit: slugLimit)
    let hash = stableHash(repoURL.standardizedFileURL.path)
    return boundedIdentifier("\(slug)-\(hash.prefix(16))")
  }

  static func currentApplicationSupportCandidateURL(
    for repoURL: URL,
    applicationSupportRoots roots: KnownProjectStore.ApplicationSupportRoots,
    identifier: String? = nil
  ) -> URL {
    KnownProjectStore.directoryURL(in: roots.current)
      .appending(path: "Projects", directoryHint: .isDirectory)
      .appending(
        path: identifier ?? projectStorageIdentifier(for: repoURL), directoryHint: .isDirectory)
  }

  struct Facts: Equatable {
    var compassDirectoryExists: Bool
    var presentCoreFiles: Set<CoreFile>
    var sessionsDirectoryExists: Bool
    var gitignoreContents: String?
    var currentApplicationSupportCandidateExists: Bool

    var missingCoreFiles: [CoreFile] {
      CoreFile.allCases.filter { !presentCoreFiles.contains($0) }
    }

    var gitignoreCoversCompass: Bool {
      CompassWorkspaceStorageAssessment.gitignoreCoversCompass(gitignoreContents)
    }
  }

  enum CoreFile: String, CaseIterable, Hashable, Equatable {
    case state = "state.json"
    case drafts = "drafts.md"
    case lessons = "lessons.md"
    case vision = "COMPASS.md"
    case sessionsRecord = "sessions.json"

    var relativePath: String { rawValue }
  }

  enum Kind: String, Equatable {
    case repoLocalHealthy
    case missingWorkspace
    case incompleteCoreFiles
    case currentApplicationSupportCandidateExists
    case unignoredCompass
  }

  enum Severity: String, Equatable {
    case healthy
    case info
    case warning
    case failure
  }

  struct Issue: Identifiable, Equatable {
    var kind: Kind
    var severity: Severity
    var label: String
    var detail: String
    var recommendation: String
    var systemImage: String

    var id: String { kind.rawValue }
  }

  enum RepairKind: String, Equatable {
    case initializeRepoLocalWorkspace
  }

  struct RepairAction: Identifiable, Equatable {
    var kind: RepairKind
    var issueKind: Kind
    var label: String
    var helpText: String
    var systemImage: String

    var id: String { "\(kind.rawValue)-\(issueKind.rawValue)" }
  }

  private static func collectFacts(
    repoURL: URL,
    currentCandidateURL: URL,
    fileManager: FileManager
  ) -> Facts {
    let workspace = CompassWorkspace(repoURL: repoURL)
    let compassDirectoryExists = directoryExists(workspace.compassURL, fileManager: fileManager)
    let presentCoreFiles = Set(
      CoreFile.allCases.filter { coreFile in
        fileExists(url(for: coreFile, in: workspace), fileManager: fileManager)
      })
    let sessionsDirectoryExists = directoryExists(workspace.sessionsURL, fileManager: fileManager)
    let gitignoreURL = repoURL.appending(path: ".gitignore")

    return Facts(
      compassDirectoryExists: compassDirectoryExists,
      presentCoreFiles: presentCoreFiles,
      sessionsDirectoryExists: sessionsDirectoryExists,
      gitignoreContents: try? String(contentsOf: gitignoreURL, encoding: .utf8),
      currentApplicationSupportCandidateExists: fileManager.fileExists(
        atPath: currentCandidateURL.path)
    )
  }

  private static func issues(
    facts: Facts,
    repoURL: URL,
    currentCandidateURL: URL
  ) -> [Issue] {
    var issues: [Issue] = []

    if !facts.compassDirectoryExists {
      issues.append(
        issue(
          kind: .missingWorkspace,
          severity: .warning,
          label: "Workspace missing",
          detail:
            "Repo-local .compass/ has not been initialized for \(boundedPath(repoURL.path, limit: 96)).",
          recommendation: "Initialize the Compass workspace before running Plan or Develop.",
          systemImage: "folder.badge.questionmark"
        )
      )
    } else {
      let missingItems =
        facts.missingCoreFiles.map(\.relativePath)
        + (facts.sessionsDirectoryExists ? [] : ["sessions/"])
      if !missingItems.isEmpty {
        issues.append(
          issue(
            kind: .incompleteCoreFiles,
            severity: .failure,
            label: "Workspace incomplete",
            detail: ".compass/ is present but missing \(missingItems.joined(separator: ", ")).",
            recommendation:
              "Reinitialize the workspace to restore the repo-local storage skeleton.",
            systemImage: "exclamationmark.triangle.fill"
          )
        )
      }
    }

    if facts.currentApplicationSupportCandidateExists {
      issues.append(
        issue(
          kind: .currentApplicationSupportCandidateExists,
          severity: .warning,
          label: "Support path occupied",
          detail:
            "Future storage candidate already exists at \(boundedPath(currentCandidateURL.path, limit: 112)).",
          recommendation:
            "Keep repo-local storage for now; inspect that directory before any migration or mirroring work.",
          systemImage: "externaldrive.badge.exclamationmark"
        )
      )
    }

    if facts.compassDirectoryExists,
      facts.missingCoreFiles.isEmpty,
      facts.sessionsDirectoryExists,
      !facts.gitignoreCoversCompass
    {
      issues.append(
        issue(
          kind: .unignoredCompass,
          severity: .warning,
          label: ".compass unignored",
          detail: ".compass/ exists but is not covered by the repository .gitignore.",
          recommendation: "Add .compass/ to .gitignore before committing from this repository.",
          systemImage: "eye.fill"
        )
      )
    }

    return issues
  }

  private static func healthyIssue(repoURL: URL) -> Issue {
    issue(
      kind: .repoLocalHealthy,
      severity: .healthy,
      label: "Repo-local healthy",
      detail: ".compass/ has the expected core files, session storage, and .gitignore coverage.",
      recommendation:
        "No storage action needed for \(boundedPath(repoURL.lastPathComponent, limit: 48)).",
      systemImage: "checkmark.seal.fill"
    )
  }

  private static func repairAction(for issues: [Issue]) -> RepairAction? {
    for issue in issues {
      switch issue.kind {
      case .missingWorkspace:
        return repairAction(
          issueKind: issue.kind,
          helpText: "Create repo-local .compass/ core files and add .compass/ to .gitignore."
        )
      case .incompleteCoreFiles:
        return repairAction(
          issueKind: issue.kind,
          helpText:
            "Restore missing repo-local Compass files and .gitignore coverage without overwriting existing files."
        )
      case .unignoredCompass:
        return repairAction(
          issueKind: issue.kind,
          helpText: "Add .compass/ to .gitignore using the repo-local workspace initializer."
        )
      case .repoLocalHealthy,
        .currentApplicationSupportCandidateExists:
        break
      }
    }
    return nil
  }

  private static func repairAction(issueKind: Kind, helpText: String) -> RepairAction {
    RepairAction(
      kind: .initializeRepoLocalWorkspace,
      issueKind: issueKind,
      label: boundedText("Repair storage", limit: repairActionLabelLimit),
      helpText: boundedText(helpText, limit: repairActionHelpLimit),
      systemImage: "wrench.fill"
    )
  }

  private static func issue(
    kind: Kind,
    severity: Severity,
    label: String,
    detail: String,
    recommendation: String,
    systemImage: String
  ) -> Issue {
    Issue(
      kind: kind,
      severity: severity,
      label: boundedText(label, limit: labelLimit),
      detail: boundedText(detail, limit: detailLimit),
      recommendation: boundedText(recommendation, limit: recommendationLimit),
      systemImage: systemImage
    )
  }

  private static func url(for coreFile: CoreFile, in workspace: CompassWorkspace) -> URL {
    switch coreFile {
    case .state:
      return workspace.stateURL
    case .drafts:
      return workspace.draftsURL
    case .lessons:
      return workspace.lessonsURL
    case .vision:
      return workspace.visionURL
    case .sessionsRecord:
      return workspace.sessionsRecordURL
    }
  }

  private static func gitignoreCoversCompass(_ text: String?) -> Bool {
    guard let text else { return false }
    return
      text
      .split(whereSeparator: \.isNewline)
      .contains { rawLine in
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return false }
        return line == ".compass"
          || line == ".compass/"
          || line == "/.compass"
          || line == "/.compass/"
      }
  }

  private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func fileExists(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && !isDirectory.boolValue
  }

  private static func sanitizedSlug(from value: String, limit: Int) -> String {
    var scalars = String.UnicodeScalarView()
    var previousWasSeparator = false

    for scalar in value.lowercased().unicodeScalars {
      let isASCIILetter = scalar.value >= 97 && scalar.value <= 122
      let isDigit = scalar.value >= 48 && scalar.value <= 57
      if isASCIILetter || isDigit {
        scalars.append(scalar)
        previousWasSeparator = false
      } else if !previousWasSeparator, !scalars.isEmpty {
        scalars.append("-")
        previousWasSeparator = true
      }
    }

    let trimmed = String(String(scalars).prefix(max(1, limit)))
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "project" : trimmed
  }

  private static func stableHash(_ value: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100_0000_01b3
    }
    let raw = String(hash, radix: 16)
    return String(repeating: "0", count: max(0, 16 - raw.count)) + raw
  }

  private static func boundedIdentifier(_ value: String) -> String {
    String(value.prefix(maxProjectIdentifierLength))
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 1 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassWorkspaceStoragePreflight: Equatable {
  static let labelLimit = 34
  static let detailLimit = 180
  static let recommendationLimit = 140

  var repoURL: URL
  var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots
  var projectStorageIdentifier: String
  var repoLocalReadiness: RepoLocalReadiness
  var missingCoreFiles: [CompassWorkspaceStorageAssessment.CoreFile]
  var sessionsDirectoryExists: Bool
  var currentApplicationSupportCandidate: ApplicationSupportCandidate
  var status: Status

  var kind: Kind { status.kind }
  var label: String { status.label }
  var detail: String { status.detail }
  var recommendation: String { status.recommendation }
  var systemImage: String { status.systemImage }
  var currentApplicationSupportCandidateURL: URL { currentApplicationSupportCandidate.url }
  var currentApplicationSupportCandidateIsOccupied: Bool {
    currentApplicationSupportCandidate.isOccupied
  }
  var occupiedApplicationSupportCandidates: [ApplicationSupportCandidate] {
    currentApplicationSupportCandidate.isOccupied ? [currentApplicationSupportCandidate] : []
  }
  var migrationWouldBeSafe: Bool {
    repoLocalReadiness == .ready && occupiedApplicationSupportCandidates.isEmpty
  }

  init(
    repoURL: URL,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots =
      KnownProjectStore.productionApplicationSupportRoots(),
    fileManager: FileManager = .default
  ) {
    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL,
      applicationSupportRoots: applicationSupportRoots,
      fileManager: fileManager
    )
    self.init(assessment: assessment)
  }

  init(assessment: CompassWorkspaceStorageAssessment) {
    let readiness = Self.repoLocalReadiness(from: assessment.facts)
    let currentCandidate = ApplicationSupportCandidate(
      url: assessment.currentApplicationSupportCandidateURL,
      occupancy: assessment.facts.currentApplicationSupportCandidateExists ? .occupied : .empty
    )

    self.repoURL = assessment.repoURL
    self.applicationSupportRoots = assessment.applicationSupportRoots
    projectStorageIdentifier = assessment.projectStorageIdentifier
    repoLocalReadiness = readiness
    missingCoreFiles = assessment.facts.missingCoreFiles
    sessionsDirectoryExists = assessment.facts.sessionsDirectoryExists
    currentApplicationSupportCandidate = currentCandidate
    status = Self.status(
      repoURL: assessment.repoURL,
      readiness: readiness,
      missingCoreFiles: assessment.facts.missingCoreFiles,
      sessionsDirectoryExists: assessment.facts.sessionsDirectoryExists,
      occupiedCandidates: currentCandidate.isOccupied ? [currentCandidate] : []
    )
  }

  enum RepoLocalReadiness: String, Equatable {
    case ready
    case missingWorkspace
    case incompleteWorkspace

    var displayName: String {
      switch self {
      case .ready:
        return "ready"
      case .missingWorkspace:
        return "missing .compass/"
      case .incompleteWorkspace:
        return "incomplete .compass/"
      }
    }
  }

  enum CandidateOccupancy: String, Equatable {
    case empty
    case occupied

    var displayName: String {
      switch self {
      case .empty:
        return "empty"
      case .occupied:
        return "occupied"
      }
    }
  }

  struct ApplicationSupportCandidate: Identifiable, Equatable {
    var url: URL
    var occupancy: CandidateOccupancy

    var id: String { url.path }
    var isOccupied: Bool { occupancy == .occupied }
  }

  enum Kind: String, Equatable {
    case migrationReady
    case repoLocalMissing
    case repoLocalIncomplete
    case applicationSupportConflict
  }

  struct Status: Equatable {
    var kind: Kind
    var label: String
    var detail: String
    var recommendation: String
    var systemImage: String
  }

  private static func repoLocalReadiness(
    from facts: CompassWorkspaceStorageAssessment.Facts
  ) -> RepoLocalReadiness {
    guard facts.compassDirectoryExists else { return .missingWorkspace }
    guard facts.missingCoreFiles.isEmpty, facts.sessionsDirectoryExists else {
      return .incompleteWorkspace
    }
    return .ready
  }

  private static func status(
    repoURL: URL,
    readiness: RepoLocalReadiness,
    missingCoreFiles: [CompassWorkspaceStorageAssessment.CoreFile],
    sessionsDirectoryExists: Bool,
    occupiedCandidates: [ApplicationSupportCandidate]
  ) -> Status {
    switch readiness {
    case .missingWorkspace:
      return status(
        kind: .repoLocalMissing,
        label: "Preflight blocked",
        detail: "Repo-local .compass/ is missing for \(boundedPath(repoURL.path, limit: 96)).",
        recommendation: "Run repo-local repair before considering Application Support migration.",
        systemImage: "folder.badge.questionmark"
      )
    case .incompleteWorkspace:
      let missingItems =
        missingCoreFiles.map(\.relativePath)
        + (sessionsDirectoryExists ? [] : ["sessions/"])
      return status(
        kind: .repoLocalIncomplete,
        label: "Preflight blocked",
        detail: ".compass/ is missing \(missingItems.joined(separator: ", ")).",
        recommendation: "Repair repo-local storage before any migration or mirroring work.",
        systemImage: "exclamationmark.triangle.fill"
      )
    case .ready:
      if occupiedCandidates.isEmpty {
        return status(
          kind: .migrationReady,
          label: "Preflight clear",
          detail:
            "Repo-local .compass/ is complete and the Application Support candidate path is empty.",
          recommendation:
            "Future migration can start from repo-local storage without path conflicts.",
          systemImage: "checkmark.seal.fill"
        )
      }

      let conflictText =
        occupiedCandidates
        .map { boundedPath($0.url.path, limit: 72) }
        .joined(separator: "; ")
      return status(
        kind: .applicationSupportConflict,
        label: "Inspect support data",
        detail: "Inspect-only conflict at \(conflictText).",
        recommendation:
          "Inspect occupied support candidates before migration; Compass remains on repo-local .compass/.",
        systemImage: "externaldrive.badge.exclamationmark"
      )
    }
  }

  private static func status(
    kind: Kind,
    label: String,
    detail: String,
    recommendation: String,
    systemImage: String
  ) -> Status {
    Status(
      kind: kind,
      label: boundedText(label, limit: labelLimit),
      detail: boundedText(detail, limit: detailLimit),
      recommendation: boundedText(recommendation, limit: recommendationLimit),
      systemImage: systemImage
    )
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 1 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassWorkspaceStorageBoundary: Equatable {
  static let labelLimit = 34
  static let detailLimit = 180
  static let recommendationLimit = 140

  var repoURL: URL
  var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots
  var projectStorageIdentifier: String
  var currentApplicationSupportCandidateURL: URL
  var assessmentKind: CompassWorkspaceStorageAssessment.Kind
  var preflightKind: CompassWorkspaceStoragePreflight.Kind
  var migrationCouldBeTechnicallyEligible: Bool
  var status: Status

  var kind: Kind { status.kind }
  var severity: CompassWorkspaceStorageAssessment.Severity { status.severity }
  var label: String { status.label }
  var detail: String { status.detail }
  var recommendation: String { status.recommendation }
  var systemImage: String { status.systemImage }

  init(
    assessment: CompassWorkspaceStorageAssessment,
    preflight: CompassWorkspaceStoragePreflight
  ) {
    repoURL = assessment.repoURL
    applicationSupportRoots = assessment.applicationSupportRoots
    projectStorageIdentifier = assessment.projectStorageIdentifier
    currentApplicationSupportCandidateURL = assessment.currentApplicationSupportCandidateURL
    assessmentKind = assessment.kind
    preflightKind = preflight.kind
    migrationCouldBeTechnicallyEligible = preflight.migrationWouldBeSafe
    status = Self.status(assessment: assessment, preflight: preflight)
  }

  enum Kind: String, Equatable {
    case repoLocalRecommended
    case repoLocalRepairFirst
    case applicationSupportInspectOnlyConflict
  }

  struct Status: Equatable {
    var kind: Kind
    var severity: CompassWorkspaceStorageAssessment.Severity
    var label: String
    var detail: String
    var recommendation: String
    var systemImage: String
  }

  private static func status(
    assessment: CompassWorkspaceStorageAssessment,
    preflight: CompassWorkspaceStoragePreflight
  ) -> Status {
    if assessment.issues.contains(where: isRepoLocalRepairIssue) {
      return status(
        kind: .repoLocalRepairFirst,
        severity: assessment.severity,
        label: "Repair repo-local",
        detail: repairFirstDetail(for: assessment),
        recommendation:
          "Use repo-local repair first; leave Application Support as inspect-only future-candidate storage.",
        systemImage: assessment.systemImage
      )
    }

    if !preflight.occupiedApplicationSupportCandidates.isEmpty {
      let occupied = preflight.occupiedApplicationSupportCandidates
        .map { boundedPath($0.url.path, limit: 72) }
        .joined(separator: ", ")
      return status(
        kind: .applicationSupportInspectOnlyConflict,
        severity: .warning,
        label: "Inspect support data",
        detail:
          "Active state remains in repo-local .compass/; inspect-only conflict at \(occupied).",
        recommendation:
          "No migration or mirroring by default; inspect support directories before any future opt-in storage change.",
        systemImage: "externaldrive.badge.exclamationmark"
      )
    }

    return status(
      kind: .repoLocalRecommended,
      severity: .healthy,
      label: "Repo-local boundary",
      detail:
        "Active project state stays in repo-local .compass/; Application Support remains the project registry and future-candidate area.",
      recommendation:
        "No migration or mirroring needed by default; preflight only preserves future opt-in eligibility.",
      systemImage: "checkmark.seal.fill"
    )
  }

  private static func isRepoLocalRepairIssue(
    _ issue: CompassWorkspaceStorageAssessment.Issue
  ) -> Bool {
    switch issue.kind {
    case .missingWorkspace,
      .incompleteCoreFiles,
      .unignoredCompass:
      return true
    case .repoLocalHealthy,
      .currentApplicationSupportCandidateExists:
      return false
    }
  }

  private static func repairFirstDetail(
    for assessment: CompassWorkspaceStorageAssessment
  ) -> String {
    switch assessment.kind {
    case .missingWorkspace:
      return
        "Repo-local .compass/ is missing; repair the workspace before considering migration or mirroring."
    case .incompleteCoreFiles:
      return
        ".compass/ is incomplete; restore the repo-local skeleton before considering migration or mirroring."
    case .unignoredCompass:
      return
        ".compass/ is complete but not ignored; repair .gitignore coverage before storage changes."
    case .repoLocalHealthy,
      .currentApplicationSupportCandidateExists:
      return assessment.detail
    }
  }

  private static func status(
    kind: Kind,
    severity: CompassWorkspaceStorageAssessment.Severity,
    label: String,
    detail: String,
    recommendation: String,
    systemImage: String
  ) -> Status {
    Status(
      kind: kind,
      severity: severity,
      label: boundedText(label, limit: labelLimit),
      detail: boundedText(detail, limit: detailLimit),
      recommendation: boundedText(recommendation, limit: recommendationLimit),
      systemImage: systemImage
    )
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 1 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassWorkspaceStorageDisplayStatus: Equatable {
  static let labelLimit = 38
  static let detailLimit = 220
  static let recommendationLimit = 160
  static let repairActionLabelLimit = 24
  static let repairActionHelpLimit = 150
  static let compatibilityDetailLimit = 180
  static let compatibilityRecommendationLimit = 160
  static let compatibilityHelpLimit = 180

  var repoURL: URL
  var activeStorage: KnownProjectActiveStorage
  var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots
  var activeStorageRootURL: URL
  var projectStorageIdentifier: String
  var currentApplicationSupportCandidateURL: URL
  var assessmentKind: CompassWorkspaceStorageAssessment.Kind
  var preflightKind: CompassWorkspaceStoragePreflight.Kind
  var repoLocalReadiness: CompassWorkspaceStoragePreflight.RepoLocalReadiness
  var migrationCouldBeTechnicallyEligible: Bool
  var activeRootFacts: ActiveRootFacts
  var applicationSupportCompatibility: ApplicationSupportCompatibility?
  var status: Status
  var supportRepairAction: RepairAction?

  var kind: Kind { status.kind }
  var severity: CompassWorkspaceStorageAssessment.Severity { status.severity }
  var label: String { status.label }
  var detail: String { status.detail }
  var recommendation: String { status.recommendation }
  var systemImage: String { status.systemImage }
  var activeRootHealth: ActiveRootHealth { activeRootFacts.health }

  var activeStorageDisplayName: String {
    switch activeStorage {
    case .repoLocal:
      return "repo-local .compass/"
    case .applicationSupport:
      return "Application Support"
    }
  }

  init(
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots =
      KnownProjectStore.productionApplicationSupportRoots(),
    fileManager: FileManager = .default
  ) {
    let standardizedRepoURL = repoURL.standardizedFileURL
    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: standardizedRepoURL,
      applicationSupportRoots: applicationSupportRoots,
      fileManager: fileManager
    )
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let activeStorageRootURL = CompassProjectStorageResolver.storageRootURL(
      for: standardizedRepoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: applicationSupportRoots
    )
    self.init(
      repoURL: standardizedRepoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: applicationSupportRoots,
      activeStorageRootURL: activeStorageRootURL,
      assessment: assessment,
      preflight: preflight,
      fileManager: fileManager
    )
  }

  init(
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots,
    activeStorageRootURL: URL,
    assessment: CompassWorkspaceStorageAssessment,
    preflight: CompassWorkspaceStoragePreflight,
    fileManager: FileManager = .default
  ) {
    let facts: ActiveRootFacts
    switch activeStorage {
    case .repoLocal:
      facts = ActiveRootFacts(assessmentFacts: assessment.facts)
    case .applicationSupport:
      facts = Self.collectActiveRootFacts(
        repoURL: assessment.repoURL,
        activeStorageRootURL: activeStorageRootURL,
        fileManager: fileManager
      )
    }
    self.init(
      repoURL: repoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: applicationSupportRoots,
      activeStorageRootURL: activeStorageRootURL,
      assessment: assessment,
      preflight: preflight,
      activeRootFacts: facts
    )
  }

  init(
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots,
    activeStorageRootURL: URL,
    assessment: CompassWorkspaceStorageAssessment,
    preflight: CompassWorkspaceStoragePreflight,
    activeRootFacts: ActiveRootFacts
  ) {
    let standardizedRepoURL = repoURL.standardizedFileURL
    let standardizedActiveRootURL = activeStorageRootURL.standardizedFileURL
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    self.repoURL = standardizedRepoURL
    self.activeStorage = activeStorage
    self.applicationSupportRoots = applicationSupportRoots
    self.activeStorageRootURL = standardizedActiveRootURL
    projectStorageIdentifier = assessment.projectStorageIdentifier
    currentApplicationSupportCandidateURL = assessment.currentApplicationSupportCandidateURL
    assessmentKind = assessment.kind
    preflightKind = preflight.kind
    repoLocalReadiness = preflight.repoLocalReadiness
    migrationCouldBeTechnicallyEligible = preflight.migrationWouldBeSafe
    self.activeRootFacts = activeRootFacts
    let supportCompatibility =
      activeStorage == .applicationSupport
      ? Self.makeApplicationSupportCompatibility(
        activeStorageRootURL: standardizedActiveRootURL,
        preflight: preflight
      )
      : nil
    applicationSupportCompatibility = supportCompatibility
    let derivedStatus = Self.status(
      repoURL: standardizedRepoURL,
      activeStorage: activeStorage,
      activeStorageRootURL: standardizedActiveRootURL,
      activeRootFacts: activeRootFacts,
      preflight: preflight,
      boundary: boundary,
      applicationSupportCompatibility: supportCompatibility
    )
    status = derivedStatus
    supportRepairAction = Self.supportRepairAction(for: derivedStatus.kind)
  }

  enum Kind: String, Equatable {
    case repoLocalRecommended
    case repoLocalRepairFirst
    case applicationSupportInspectOnlyConflict
    case applicationSupportActive
    case applicationSupportActiveMissing
    case applicationSupportActiveIncomplete
  }

  enum ActiveRootHealth: String, Equatable {
    case healthy
    case missing
    case incomplete

    var displayName: String {
      switch self {
      case .healthy:
        return "healthy"
      case .missing:
        return "missing"
      case .incomplete:
        return "incomplete"
      }
    }
  }

  enum RepoLocalCompatibilityKind: String, Equatable {
    case retainedStale
    case missing
    case incomplete

    var displayName: String {
      switch self {
      case .retainedStale:
        return "retained stale"
      case .missing:
        return "missing"
      case .incomplete:
        return "incomplete"
      }
    }
  }

  struct ActiveRootFacts: Equatable {
    var directoryExists: Bool
    var presentCoreFiles: Set<CompassWorkspaceStorageAssessment.CoreFile>
    var sessionsDirectoryExists: Bool

    var missingCoreFiles: [CompassWorkspaceStorageAssessment.CoreFile] {
      CompassWorkspaceStorageAssessment.CoreFile.allCases.filter { !presentCoreFiles.contains($0) }
    }

    var missingItems: [String] {
      missingCoreFiles.map(\.relativePath) + (sessionsDirectoryExists ? [] : ["sessions/"])
    }

    var health: ActiveRootHealth {
      guard directoryExists else { return .missing }
      return missingItems.isEmpty ? .healthy : .incomplete
    }

    init(
      directoryExists: Bool,
      presentCoreFiles: Set<CompassWorkspaceStorageAssessment.CoreFile>,
      sessionsDirectoryExists: Bool
    ) {
      self.directoryExists = directoryExists
      self.presentCoreFiles = presentCoreFiles
      self.sessionsDirectoryExists = sessionsDirectoryExists
    }

    init(assessmentFacts: CompassWorkspaceStorageAssessment.Facts) {
      self.init(
        directoryExists: assessmentFacts.compassDirectoryExists,
        presentCoreFiles: assessmentFacts.presentCoreFiles,
        sessionsDirectoryExists: assessmentFacts.sessionsDirectoryExists
      )
    }
  }

  struct RepoLocalCompatibilityContext: Equatable {
    var kind: RepoLocalCompatibilityKind
    var missingItems: [String]
    var detail: String
    var recommendation: String
    var helpText: String
  }

  struct ApplicationSupportCompatibility: Equatable {
    var repoLocalContext: RepoLocalCompatibilityContext
    var inspectOnlyApplicationSupportDrift:
      [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate]
    var detail: String
    var recommendation: String
    var helpText: String

    var hasInspectOnlyDrift: Bool {
      !inspectOnlyApplicationSupportDrift.isEmpty
    }
  }

  struct Status: Equatable {
    var kind: Kind
    var severity: CompassWorkspaceStorageAssessment.Severity
    var label: String
    var detail: String
    var recommendation: String
    var systemImage: String
  }

  enum RepairKind: String, Equatable {
    case initializeApplicationSupportWorkspace
  }

  struct RepairAction: Identifiable, Equatable {
    var kind: RepairKind
    var issueKind: Kind
    var label: String
    var helpText: String
    var systemImage: String

    var id: String { "\(kind.rawValue)-\(issueKind.rawValue)" }
  }

  private static func collectActiveRootFacts(
    repoURL: URL,
    activeStorageRootURL: URL,
    fileManager: FileManager
  ) -> ActiveRootFacts {
    let workspace = CompassWorkspace(repoURL: repoURL, storageRootURL: activeStorageRootURL)
    let rootDirectoryExists = directoryExists(activeStorageRootURL, fileManager: fileManager)
    let presentCoreFiles = Set(
      CompassWorkspaceStorageAssessment.CoreFile.allCases.filter { coreFile in
        fileExists(url(for: coreFile, in: workspace), fileManager: fileManager)
      })

    return ActiveRootFacts(
      directoryExists: rootDirectoryExists,
      presentCoreFiles: presentCoreFiles,
      sessionsDirectoryExists: directoryExists(workspace.sessionsURL, fileManager: fileManager)
    )
  }

  private static func status(
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage,
    activeStorageRootURL: URL,
    activeRootFacts: ActiveRootFacts,
    preflight: CompassWorkspaceStoragePreflight,
    boundary: CompassWorkspaceStorageBoundary,
    applicationSupportCompatibility: ApplicationSupportCompatibility?
  ) -> Status {
    switch activeStorage {
    case .repoLocal:
      return status(
        kind: displayKind(for: boundary.kind),
        severity: boundary.severity,
        label: boundary.label,
        detail: boundary.detail,
        recommendation: boundary.recommendation,
        systemImage: boundary.systemImage
      )
    case .applicationSupport:
      return applicationSupportStatus(
        repoURL: repoURL,
        activeStorageRootURL: activeStorageRootURL,
        activeRootFacts: activeRootFacts,
        compatibility: applicationSupportCompatibility
          ?? makeApplicationSupportCompatibility(
            activeStorageRootURL: activeStorageRootURL,
            preflight: preflight
          )
      )
    }
  }

  private static func applicationSupportStatus(
    repoURL: URL,
    activeStorageRootURL: URL,
    activeRootFacts: ActiveRootFacts,
    compatibility: ApplicationSupportCompatibility
  ) -> Status {
    switch activeRootFacts.health {
    case .healthy:
      return status(
        kind: .applicationSupportActive,
        severity: compatibility.hasInspectOnlyDrift ? .info : .healthy,
        label: compatibility.hasInspectOnlyDrift ? "Support drift noted" : "Support storage active",
        detail: applicationSupportActiveDetail(
          activeStorageRootURL: activeStorageRootURL,
          repoURL: repoURL,
          compatibility: compatibility
        ),
        recommendation: compatibility.recommendation,
        systemImage: compatibility.hasInspectOnlyDrift
          ? "externaldrive.badge.exclamationmark"
          : "externaldrive.fill.badge.checkmark"
      )
    case .missing:
      return status(
        kind: .applicationSupportActiveMissing,
        severity: .warning,
        label: "Support storage missing",
        detail:
          "Active Application Support state root is missing at \(boundedPath(activeStorageRootURL.path, limit: 144)).",
        recommendation: "Restore or initialize the active support root before running Compass.",
        systemImage: "folder.badge.questionmark"
      )
    case .incomplete:
      return status(
        kind: .applicationSupportActiveIncomplete,
        severity: .failure,
        label: "Support storage incomplete",
        detail:
          "Active Application Support state root is missing \(activeRootFacts.missingItems.joined(separator: ", ")) at \(boundedPath(activeStorageRootURL.path, limit: 112)).",
        recommendation: "Restore the active support storage skeleton before running Compass.",
        systemImage: "exclamationmark.triangle.fill"
      )
    }
  }

  private static func makeApplicationSupportCompatibility(
    activeStorageRootURL: URL,
    preflight: CompassWorkspaceStoragePreflight
  ) -> ApplicationSupportCompatibility {
    let repoLocalContext = repoLocalCompatibilityContext(from: preflight)
    let inspectOnlyDrift = inspectOnlyApplicationSupportDrift(
      activeStorageRootURL: activeStorageRootURL,
      preflight: preflight
    )
    return ApplicationSupportCompatibility(
      repoLocalContext: repoLocalContext,
      inspectOnlyApplicationSupportDrift: inspectOnlyDrift,
      detail: applicationSupportCompatibilityDetail(
        repoLocalContext: repoLocalContext,
        inspectOnlyDrift: inspectOnlyDrift
      ),
      recommendation: applicationSupportCompatibilityRecommendation(
        repoLocalContext: repoLocalContext,
        inspectOnlyDrift: inspectOnlyDrift
      ),
      helpText: applicationSupportCompatibilityHelpText(
        activeStorageRootURL: activeStorageRootURL,
        repoLocalContext: repoLocalContext,
        inspectOnlyDrift: inspectOnlyDrift
      )
    )
  }

  private static func repoLocalCompatibilityContext(
    from preflight: CompassWorkspaceStoragePreflight
  ) -> RepoLocalCompatibilityContext {
    let missingItems =
      preflight.missingCoreFiles.map(\.relativePath)
      + (preflight.sessionsDirectoryExists ? [] : ["sessions/"])

    let kind: RepoLocalCompatibilityKind
    let detail: String
    let recommendation: String
    let helpText: String

    switch preflight.repoLocalReadiness {
    case .ready:
      kind = .retainedStale
      detail = "Repo-local .compass/ is retained stale compatibility context."
      recommendation =
        "Leave repo-local state unchanged unless explicitly reverting to repo-local storage."
      helpText =
        "Repo-local .compass/ is not active while Application Support is selected; treat it as stale compatibility context."
    case .missingWorkspace:
      kind = .missing
      detail = "Repo-local .compass/ is absent; Application Support has the active state."
      recommendation = "No repo-local storage action is needed by default."
      helpText =
        "Missing repo-local .compass/ does not block an Application Support-active project."
    case .incompleteWorkspace:
      kind = .incomplete
      detail =
        ".compass/ is incomplete stale compatibility context: \(missingItems.joined(separator: ", "))."
      recommendation =
        "Leave incomplete repo-local state unchanged unless explicitly reverting storage."
      helpText =
        "Incomplete repo-local .compass/ is compatibility context only while Application Support is active."
    }

    return RepoLocalCompatibilityContext(
      kind: kind,
      missingItems: missingItems,
      detail: boundedText(detail, limit: compatibilityDetailLimit),
      recommendation: boundedText(recommendation, limit: compatibilityRecommendationLimit),
      helpText: boundedText(helpText, limit: compatibilityHelpLimit)
    )
  }

  private static func inspectOnlyApplicationSupportDrift(
    activeStorageRootURL: URL,
    preflight: CompassWorkspaceStoragePreflight
  ) -> [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate] {
    let activeRootPath = activeStorageRootURL.standardizedFileURL.path
    return [preflight.currentApplicationSupportCandidate].filter { candidate in
      candidate.isOccupied && candidate.url.standardizedFileURL.path != activeRootPath
    }
  }

  private static func applicationSupportActiveDetail(
    activeStorageRootURL: URL,
    repoURL: URL,
    compatibility: ApplicationSupportCompatibility
  ) -> String {
    let rootText =
      "Active Compass state root: \(boundedPath(activeStorageRootURL.path, limit: 76)); repoURL: \(boundedPath(repoURL.path, limit: 44))."
    return boundedText(
      "\(compatibility.detail) \(rootText)",
      limit: detailLimit
    )
  }

  private static func applicationSupportCompatibilityDetail(
    repoLocalContext: RepoLocalCompatibilityContext,
    inspectOnlyDrift: [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate]
  ) -> String {
    let drift = inspectOnlyDriftText(inspectOnlyDrift, pathLimit: 64)
    let detail =
      drift.isEmpty
      ? repoLocalContext.detail
      : "\(repoLocalContext.detail) Inspect-only support drift: \(drift)."
    return boundedText(detail, limit: compatibilityDetailLimit)
  }

  private static func applicationSupportCompatibilityRecommendation(
    repoLocalContext: RepoLocalCompatibilityContext,
    inspectOnlyDrift: [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate]
  ) -> String {
    let recommendation =
      inspectOnlyDrift.isEmpty
      ? repoLocalContext.recommendation
      : "\(repoLocalContext.recommendation) Inspect occupied support data separately; keep Application Support active."
    return boundedText(recommendation, limit: compatibilityRecommendationLimit)
  }

  private static func applicationSupportCompatibilityHelpText(
    activeStorageRootURL: URL,
    repoLocalContext: RepoLocalCompatibilityContext,
    inspectOnlyDrift: [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate]
  ) -> String {
    let drift = inspectOnlyDriftText(inspectOnlyDrift, pathLimit: 72)
    let supportText =
      drift.isEmpty
      ? "Active root: \(boundedPath(activeStorageRootURL.path, limit: 84))."
      : "Inspect-only drift: \(drift); active root remains \(boundedPath(activeStorageRootURL.path, limit: 64))."
    return boundedText(
      "\(repoLocalContext.helpText) \(supportText)",
      limit: compatibilityHelpLimit
    )
  }

  private static func inspectOnlyDriftText(
    _ candidates: [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate],
    pathLimit: Int
  ) -> String {
    candidates
      .map { boundedPath($0.url.path, limit: pathLimit) }
      .joined(separator: "; ")
  }

  private static func displayKind(for boundaryKind: CompassWorkspaceStorageBoundary.Kind) -> Kind {
    switch boundaryKind {
    case .repoLocalRecommended:
      return .repoLocalRecommended
    case .repoLocalRepairFirst:
      return .repoLocalRepairFirst
    case .applicationSupportInspectOnlyConflict:
      return .applicationSupportInspectOnlyConflict
    }
  }

  private static func status(
    kind: Kind,
    severity: CompassWorkspaceStorageAssessment.Severity,
    label: String,
    detail: String,
    recommendation: String,
    systemImage: String
  ) -> Status {
    Status(
      kind: kind,
      severity: severity,
      label: boundedText(label, limit: labelLimit),
      detail: boundedText(detail, limit: detailLimit),
      recommendation: boundedText(recommendation, limit: recommendationLimit),
      systemImage: systemImage
    )
  }

  private static func supportRepairAction(for kind: Kind) -> RepairAction? {
    switch kind {
    case .applicationSupportActiveMissing:
      return supportRepairAction(
        issueKind: kind,
        helpText:
          "Create the active Application Support Compass root and core files without touching repo-local .compass/ or .gitignore."
      )
    case .applicationSupportActiveIncomplete:
      return supportRepairAction(
        issueKind: kind,
        helpText:
          "Restore missing active Application Support Compass files and sessions without touching repo-local .compass/ or .gitignore."
      )
    case .repoLocalRecommended,
      .repoLocalRepairFirst,
      .applicationSupportInspectOnlyConflict,
      .applicationSupportActive:
      return nil
    }
  }

  private static func supportRepairAction(issueKind: Kind, helpText: String) -> RepairAction {
    RepairAction(
      kind: .initializeApplicationSupportWorkspace,
      issueKind: issueKind,
      label: boundedText("Repair support storage", limit: repairActionLabelLimit),
      helpText: boundedText(helpText, limit: repairActionHelpLimit),
      systemImage: "externaldrive.badge.plus"
    )
  }

  private static func url(
    for coreFile: CompassWorkspaceStorageAssessment.CoreFile,
    in workspace: CompassWorkspace
  ) -> URL {
    switch coreFile {
    case .state:
      return workspace.stateURL
    case .drafts:
      return workspace.draftsURL
    case .lessons:
      return workspace.lessonsURL
    case .vision:
      return workspace.visionURL
    case .sessionsRecord:
      return workspace.sessionsRecordURL
    }
  }

  private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func fileExists(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && !isDirectory.boolValue
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 1 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassWorkspaceStorageHeaderActions: Equatable {
  var showsCandidatePreparation: Bool
  var showsActivation: Bool
  var showsRepoLocalRepair: Bool
  var showsApplicationSupportRepair: Bool

  init(
    activeStorage: KnownProjectActiveStorage,
    candidatePreparationIsAvailable: Bool,
    candidatePreparationShouldShowFeedback: Bool,
    activationIsAvailable: Bool,
    activationShouldShowFeedback: Bool,
    activationIsIdle: Bool,
    repoLocalRepairActionIsAvailable: Bool,
    applicationSupportRepairActionIsAvailable: Bool = false
  ) {
    showsCandidatePreparation =
      candidatePreparationShouldShowFeedback
      || (activeStorage == .repoLocal && candidatePreparationIsAvailable)
    showsActivation =
      activationShouldShowFeedback
      || (activeStorage == .repoLocal && activationIsAvailable && activationIsIdle)
    showsRepoLocalRepair = activeStorage == .repoLocal && repoLocalRepairActionIsAvailable
    showsApplicationSupportRepair =
      activeStorage == .applicationSupport
      && applicationSupportRepairActionIsAvailable
  }
}

struct CompassWorkspaceStorageActivationPlan: Equatable {
  static let labelLimit = 34
  static let detailLimit = 220
  static let recommendationLimit = 150

  var repoURL: URL
  var activeStorage: KnownProjectActiveStorage
  var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots
  var projectStorageIdentifier: String
  var repoLocalURL: URL
  var candidateURL: URL
  var missingItems: [String]
  var invalidReason: String?
  var status: Status

  var kind: Kind { status.kind }
  var label: String { status.label }
  var detail: String { status.detail }
  var recommendation: String { status.recommendation }
  var systemImage: String { status.systemImage }
  var isAvailable: Bool { kind == .available }

  init(
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots =
      KnownProjectStore.productionApplicationSupportRoots(),
    fileManager: FileManager = .default
  ) {
    let standardizedRepoURL = repoURL.standardizedFileURL
    let identifier = CompassWorkspaceStorageAssessment.projectStorageIdentifier(
      for: standardizedRepoURL)
    let candidateURL = CompassWorkspaceStorageAssessment.currentApplicationSupportCandidateURL(
      for: standardizedRepoURL,
      applicationSupportRoots: applicationSupportRoots,
      identifier: identifier
    )
    let validation = Self.validateCandidate(
      repoURL: standardizedRepoURL,
      candidateURL: candidateURL,
      fileManager: fileManager
    )

    self.repoURL = standardizedRepoURL
    self.activeStorage = activeStorage
    self.applicationSupportRoots = applicationSupportRoots
    projectStorageIdentifier = identifier
    repoLocalURL = CompassWorkspace.repoLocalStorageRootURL(for: standardizedRepoURL)
    self.candidateURL = candidateURL
    missingItems = validation.missingItems
    invalidReason = validation.invalidReason
    status = Self.status(
      activeStorage: activeStorage,
      candidateURL: candidateURL,
      validation: validation
    )
  }

  enum Kind: String, Equatable {
    case available
    case alreadyApplicationSupport
    case candidateMissing
    case candidateIncomplete
    case candidateInvalid
  }

  struct Status: Equatable {
    var kind: Kind
    var label: String
    var detail: String
    var recommendation: String
    var systemImage: String
  }

  private struct CandidateValidation {
    var kind: Kind
    var missingItems: [String]
    var invalidReason: String?
  }

  private static func validateCandidate(
    repoURL: URL,
    candidateURL: URL,
    fileManager: FileManager
  ) -> CandidateValidation {
    guard directoryExists(candidateURL, fileManager: fileManager) else {
      return CandidateValidation(
        kind: .candidateMissing,
        missingItems: [],
        invalidReason: nil
      )
    }

    let workspace = CompassWorkspace(repoURL: repoURL, storageRootURL: candidateURL)
    var missingItems = CompassWorkspaceStorageAssessment.CoreFile.allCases
      .filter { !fileExists(url(for: $0, in: workspace), fileManager: fileManager) }
      .map(\.relativePath)
    if !directoryExists(workspace.sessionsURL, fileManager: fileManager) {
      missingItems.append("sessions/")
    }
    if !missingItems.isEmpty {
      return CandidateValidation(
        kind: .candidateIncomplete,
        missingItems: missingItems,
        invalidReason: nil
      )
    }

    do {
      _ = try workspace.readState()
    } catch {
      return CandidateValidation(
        kind: .candidateInvalid,
        missingItems: [],
        invalidReason: "state.json could not be decoded: \(error.localizedDescription)"
      )
    }

    do {
      let data = try Data(contentsOf: workspace.sessionsRecordURL)
      if !data.isEmpty {
        _ = try JSONDecoder().decode([SessionRecord].self, from: data)
      }
    } catch {
      return CandidateValidation(
        kind: .candidateInvalid,
        missingItems: [],
        invalidReason: "sessions.json could not be decoded: \(error.localizedDescription)"
      )
    }

    return CandidateValidation(kind: .available, missingItems: [], invalidReason: nil)
  }

  private static func status(
    activeStorage: KnownProjectActiveStorage,
    candidateURL: URL,
    validation: CandidateValidation
  ) -> Status {
    guard activeStorage == .repoLocal else {
      return status(
        kind: .alreadyApplicationSupport,
        label: "Activation unavailable",
        detail: "Application Support storage is already active for this project.",
        recommendation: "Keep using the active support-backed Compass state root.",
        systemImage: "externaldrive.fill.badge.checkmark"
      )
    }

    switch validation.kind {
    case .available:
      return status(
        kind: .available,
        label: "Activation available",
        detail:
          "Prepared Application Support Compass state is usable at \(boundedPath(candidateURL.path, limit: 128)).",
        recommendation:
          "Activate only when ready; repoURL remains the Git and agent working directory.",
        systemImage: "externaldrive.badge.checkmark"
      )
    case .alreadyApplicationSupport:
      return status(
        kind: .alreadyApplicationSupport,
        label: "Activation unavailable",
        detail: "Application Support storage is already active for this project.",
        recommendation: "Keep using the active support-backed Compass state root.",
        systemImage: "externaldrive.fill.badge.checkmark"
      )
    case .candidateMissing:
      return status(
        kind: .candidateMissing,
        label: "Activation blocked",
        detail:
          "Prepared Application Support candidate is missing at \(boundedPath(candidateURL.path, limit: 128)).",
        recommendation: "Prepare a candidate by copying repo-local .compass/ first.",
        systemImage: "folder.badge.questionmark"
      )
    case .candidateIncomplete:
      let missing = validation.missingItems.joined(separator: ", ")
      return status(
        kind: .candidateIncomplete,
        label: "Activation blocked",
        detail: "Prepared Application Support candidate is missing \(missing).",
        recommendation:
          "Prepare the candidate again before activating Application Support storage.",
        systemImage: "exclamationmark.triangle.fill"
      )
    case .candidateInvalid:
      return status(
        kind: .candidateInvalid,
        label: "Activation blocked",
        detail:
          "Prepared Application Support candidate is not usable: \(validation.invalidReason ?? "unknown validation failure").",
        recommendation: "Inspect or recreate the candidate before switching active storage.",
        systemImage: "exclamationmark.triangle.fill"
      )
    }
  }

  private static func status(
    kind: Kind,
    label: String,
    detail: String,
    recommendation: String,
    systemImage: String
  ) -> Status {
    Status(
      kind: kind,
      label: boundedText(label, limit: labelLimit),
      detail: boundedText(detail, limit: detailLimit),
      recommendation: boundedText(recommendation, limit: recommendationLimit),
      systemImage: systemImage
    )
  }

  private static func url(
    for coreFile: CompassWorkspaceStorageAssessment.CoreFile,
    in workspace: CompassWorkspace
  ) -> URL {
    switch coreFile {
    case .state:
      return workspace.stateURL
    case .drafts:
      return workspace.draftsURL
    case .lessons:
      return workspace.lessonsURL
    case .vision:
      return workspace.visionURL
    case .sessionsRecord:
      return workspace.sessionsRecordURL
    }
  }

  private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func fileExists(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && !isDirectory.boolValue
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 1 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassWorkspaceStorageMigrationPlan: Equatable {
  static let labelLimit = 34
  static let detailLimit = 180
  static let recommendationLimit = 140

  var repoURL: URL
  var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots
  var projectStorageIdentifier: String
  var sourceCompassURL: URL
  var destinationURL: URL
  var stagingParentURL: URL
  var assessmentKind: CompassWorkspaceStorageAssessment.Kind
  var preflightKind: CompassWorkspaceStoragePreflight.Kind
  var boundaryKind: CompassWorkspaceStorageBoundary.Kind
  var repoLocalReadiness: CompassWorkspaceStoragePreflight.RepoLocalReadiness
  var currentApplicationSupportCandidateIsOccupied: Bool
  var status: Status

  var kind: Kind { status.kind }
  var label: String { status.label }
  var detail: String { status.detail }
  var recommendation: String { status.recommendation }
  var systemImage: String { status.systemImage }
  var isAvailable: Bool { kind == .available }
  var manifestURL: URL {
    destinationURL.appending(path: CompassWorkspaceStorageMigrationManifest.fileName)
  }

  init(
    repoURL: URL,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots =
      KnownProjectStore.productionApplicationSupportRoots(),
    fileManager: FileManager = .default
  ) {
    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL,
      applicationSupportRoots: applicationSupportRoots,
      fileManager: fileManager
    )
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)
    self.init(assessment: assessment, preflight: preflight, boundary: boundary)
  }

  init(
    assessment: CompassWorkspaceStorageAssessment,
    preflight: CompassWorkspaceStoragePreflight,
    boundary: CompassWorkspaceStorageBoundary
  ) {
    repoURL = assessment.repoURL
    applicationSupportRoots = assessment.applicationSupportRoots
    projectStorageIdentifier = assessment.projectStorageIdentifier
    sourceCompassURL = CompassWorkspace(repoURL: assessment.repoURL).compassURL
    destinationURL = assessment.currentApplicationSupportCandidateURL
    stagingParentURL = assessment.currentApplicationSupportCandidateURL.deletingLastPathComponent()
    assessmentKind = assessment.kind
    preflightKind = preflight.kind
    boundaryKind = boundary.kind
    repoLocalReadiness = preflight.repoLocalReadiness
    currentApplicationSupportCandidateIsOccupied =
      preflight.currentApplicationSupportCandidateIsOccupied
    status = Self.status(
      assessment: assessment,
      preflight: preflight,
      boundary: boundary
    )
  }

  enum Kind: String, Equatable {
    case available
    case repoLocalMissing
    case repoLocalIncomplete
    case repoLocalRepairRequired
    case applicationSupportOccupied
  }

  struct Status: Equatable {
    var kind: Kind
    var label: String
    var detail: String
    var recommendation: String
    var systemImage: String
  }

  private static func status(
    assessment: CompassWorkspaceStorageAssessment,
    preflight: CompassWorkspaceStoragePreflight,
    boundary: CompassWorkspaceStorageBoundary
  ) -> Status {
    switch preflight.repoLocalReadiness {
    case .missingWorkspace:
      return status(
        kind: .repoLocalMissing,
        label: "Migration blocked",
        detail:
          "Repo-local .compass/ is missing for \(boundedPath(assessment.repoURL.path, limit: 96)).",
        recommendation:
          "Initialize repo-local Compass storage before preparing an Application Support candidate.",
        systemImage: "folder.badge.questionmark"
      )
    case .incompleteWorkspace:
      let missingItems =
        preflight.missingCoreFiles.map(\.relativePath)
        + (preflight.sessionsDirectoryExists ? [] : ["sessions/"])
      return status(
        kind: .repoLocalIncomplete,
        label: "Migration blocked",
        detail: ".compass/ is incomplete and missing \(missingItems.joined(separator: ", ")).",
        recommendation: "Repair repo-local storage before copying it to Application Support.",
        systemImage: "exclamationmark.triangle.fill"
      )
    case .ready:
      break
    }

    let occupiedCandidates = preflight.occupiedApplicationSupportCandidates
    if !occupiedCandidates.isEmpty {
      let occupiedText =
        occupiedCandidates
        .map { boundedPath($0.url.path, limit: 72) }
        .joined(separator: "; ")
      return status(
        kind: .applicationSupportOccupied,
        label: "Migration blocked",
        detail: "Application Support candidate is occupied at \(occupiedText).",
        recommendation: "Inspect occupied support storage before running this opt-in transaction.",
        systemImage: "externaldrive.badge.exclamationmark"
      )
    }

    if boundary.kind == .repoLocalRepairFirst {
      return status(
        kind: .repoLocalRepairRequired,
        label: "Migration blocked",
        detail: boundary.detail,
        recommendation:
          "Repair repo-local storage before preparing Application Support candidate storage.",
        systemImage: boundary.systemImage
      )
    }

    return status(
      kind: .available,
      label: "Migration available",
      detail: "Repo-local .compass/ is complete and the Application Support candidate is clear.",
      recommendation:
        "Run only as an explicit transaction; repo-local .compass/ remains active after copy.",
      systemImage: "arrow.triangle.2.circlepath"
    )
  }

  private static func status(
    kind: Kind,
    label: String,
    detail: String,
    recommendation: String,
    systemImage: String
  ) -> Status {
    Status(
      kind: kind,
      label: boundedText(label, limit: labelLimit),
      detail: boundedText(detail, limit: detailLimit),
      recommendation: boundedText(recommendation, limit: recommendationLimit),
      systemImage: systemImage
    )
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 1 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassWorkspaceStorageMigrationManifest: Codable, Equatable {
  static let fileName = "migration-manifest.json"
  static let pathLimit = 512
  static let identifierLimit = CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
  static let timestampLimit = 40

  var repoPath: String
  var storageIdentifier: String
  var sourcePath: String
  var destinationPath: String
  var copiedFileCount: Int
  var migratedAt: String

  init(
    repoPath: String,
    storageIdentifier: String,
    sourcePath: String,
    destinationPath: String,
    copiedFileCount: Int,
    migratedAt: String
  ) {
    self.repoPath = Self.boundedPath(repoPath, limit: Self.pathLimit)
    self.storageIdentifier = Self.boundedText(storageIdentifier, limit: Self.identifierLimit)
    self.sourcePath = Self.boundedPath(sourcePath, limit: Self.pathLimit)
    self.destinationPath = Self.boundedPath(destinationPath, limit: Self.pathLimit)
    self.copiedFileCount = max(0, copiedFileCount)
    self.migratedAt = Self.boundedText(migratedAt, limit: Self.timestampLimit)
  }

  init(
    plan: CompassWorkspaceStorageMigrationPlan,
    copiedFileCount: Int,
    migratedAt: Date
  ) {
    self.init(
      repoPath: plan.repoURL.path,
      storageIdentifier: plan.projectStorageIdentifier,
      sourcePath: plan.sourceCompassURL.path,
      destinationPath: plan.destinationURL.path,
      copiedFileCount: copiedFileCount,
      migratedAt: Self.timestampString(from: migratedAt)
    )
  }

  private static func timestampString(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 1 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassWorkspaceStorageMigrationResult: Equatable {
  static let summaryLimit = 120
  static let detailLimit = 220

  var manifest: CompassWorkspaceStorageMigrationManifest
  var manifestURL: URL
  var destinationURL: URL
  var copiedFileCount: Int
  var repoLocalSourcePreserved: Bool
  var activeStorageDidChange: Bool
  var summary: String
  var detail: String

  init(
    manifest: CompassWorkspaceStorageMigrationManifest,
    manifestURL: URL,
    destinationURL: URL
  ) {
    self.manifest = manifest
    self.manifestURL = manifestURL
    self.destinationURL = destinationURL
    copiedFileCount = manifest.copiedFileCount
    repoLocalSourcePreserved = true
    activeStorageDidChange = false
    summary = Self.boundedText(
      "Prepared Application Support storage candidate with \(manifest.copiedFileCount) copied files.",
      limit: Self.summaryLimit
    )
    detail = Self.boundedText(
      "Repo-local .compass/ remains the active source of truth; candidate manifest is at \(manifestURL.path).",
      limit: Self.detailLimit
    )
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassWorkspaceStorageMigrator {
  typealias CopyAction = (_ sourceURL: URL, _ stagingURL: URL, _ fileManager: FileManager) throws ->
    Int
  typealias PromoteAction = (_ stagingURL: URL, _ destinationURL: URL, _ fileManager: FileManager)
    throws -> Void

  var fileManager: FileManager
  var now: () -> Date
  var makeTransactionIdentifier: () -> String
  var copyCompassContents: CopyAction
  var promoteStaging: PromoteAction

  init(
    fileManager: FileManager = .default,
    now: @escaping () -> Date = Date.init,
    makeTransactionIdentifier: @escaping () -> String = { UUID().uuidString },
    copyCompassContents: CopyAction? = nil,
    promoteStaging: PromoteAction? = nil
  ) {
    self.fileManager = fileManager
    self.now = now
    self.makeTransactionIdentifier = makeTransactionIdentifier
    self.copyCompassContents = copyCompassContents ?? Self.defaultCopyCompassContents
    self.promoteStaging = promoteStaging ?? Self.defaultPromoteStaging
  }

  func migrate(plan: CompassWorkspaceStorageMigrationPlan) throws
    -> CompassWorkspaceStorageMigrationResult
  {
    guard plan.isAvailable else {
      throw CompassWorkspaceStorageMigrationError.unavailable(kind: plan.kind, detail: plan.detail)
    }
    guard Self.directoryExists(plan.sourceCompassURL, fileManager: fileManager) else {
      throw CompassWorkspaceStorageMigrationError.sourceUnavailable(plan.sourceCompassURL.path)
    }
    guard !fileManager.fileExists(atPath: plan.destinationURL.path) else {
      throw CompassWorkspaceStorageMigrationError.destinationOccupied(plan.destinationURL.path)
    }

    let stagingURL = plan.stagingParentURL.appending(
      path: ".\(plan.projectStorageIdentifier)-migration-\(makeTransactionIdentifier())",
      directoryHint: .isDirectory
    )
    var didAttemptPromotion = false

    do {
      try fileManager.createDirectory(at: plan.stagingParentURL, withIntermediateDirectories: true)
      if fileManager.fileExists(atPath: stagingURL.path) {
        try fileManager.removeItem(at: stagingURL)
      }
      try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)

      let copiedFileCount = try copyCompassContents(plan.sourceCompassURL, stagingURL, fileManager)
      let manifest = CompassWorkspaceStorageMigrationManifest(
        plan: plan,
        copiedFileCount: copiedFileCount,
        migratedAt: now()
      )
      try Self.writeManifest(
        manifest,
        to: stagingURL.appending(path: CompassWorkspaceStorageMigrationManifest.fileName)
      )

      guard !fileManager.fileExists(atPath: plan.destinationURL.path) else {
        throw CompassWorkspaceStorageMigrationError.destinationOccupied(plan.destinationURL.path)
      }

      didAttemptPromotion = true
      try promoteStaging(stagingURL, plan.destinationURL, fileManager)

      return CompassWorkspaceStorageMigrationResult(
        manifest: manifest,
        manifestURL: plan.manifestURL,
        destinationURL: plan.destinationURL
      )
    } catch {
      try? removeIfPresent(stagingURL)
      if didAttemptPromotion {
        try? removeIfPresent(plan.destinationURL)
      }
      throw error
    }
  }

  private func removeIfPresent(_ url: URL) throws {
    guard fileManager.fileExists(atPath: url.path) else { return }
    try fileManager.removeItem(at: url)
  }

  private static func defaultCopyCompassContents(
    sourceURL: URL,
    stagingURL: URL,
    fileManager: FileManager
  ) throws -> Int {
    guard directoryExists(sourceURL, fileManager: fileManager) else {
      throw CompassWorkspaceStorageMigrationError.sourceUnavailable(sourceURL.path)
    }

    var copiedFileCount = 0
    guard
      let enumerator = fileManager.enumerator(
        at: sourceURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: []
      )
    else {
      throw CompassWorkspaceStorageMigrationError.sourceUnavailable(sourceURL.path)
    }

    for case let sourceChildURL as URL in enumerator {
      let relativePath = try relativePath(of: sourceChildURL, under: sourceURL)
      let destinationChildURL = stagingURL.appending(path: relativePath)
      let values = try sourceChildURL.resourceValues(forKeys: [.isDirectoryKey])

      if values.isDirectory == true {
        try fileManager.createDirectory(
          at: destinationChildURL,
          withIntermediateDirectories: true
        )
      } else {
        try fileManager.createDirectory(
          at: destinationChildURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceChildURL, to: destinationChildURL)
        copiedFileCount += 1
      }
    }

    return copiedFileCount
  }

  private static func defaultPromoteStaging(
    stagingURL: URL,
    destinationURL: URL,
    fileManager: FileManager
  ) throws {
    try fileManager.moveItem(at: stagingURL, to: destinationURL)
  }

  private static func writeManifest(
    _ manifest: CompassWorkspaceStorageMigrationManifest,
    to url: URL
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    try data.write(to: url, options: .atomic)
  }

  private static func relativePath(of childURL: URL, under rootURL: URL) throws -> String {
    let rootPath = rootURL.standardizedFileURL.path
    let childPath = childURL.standardizedFileURL.path
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard childPath.hasPrefix(prefix) else {
      throw CompassWorkspaceStorageMigrationError.sourceUnavailable(childPath)
    }
    return String(childPath.dropFirst(prefix.count))
  }

  private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }
}

enum CompassWorkspaceStorageMigrationError: LocalizedError, Equatable {
  case unavailable(kind: CompassWorkspaceStorageMigrationPlan.Kind, detail: String)
  case sourceUnavailable(String)
  case destinationOccupied(String)

  var errorDescription: String? {
    switch self {
    case .unavailable(_, let detail):
      return "Storage migration is unavailable: \(detail)"
    case .sourceUnavailable(let path):
      return "Repo-local Compass storage is unavailable at \(path)."
    case .destinationOccupied(let path):
      return "Application Support candidate is already occupied at \(path)."
    }
  }
}

private enum CompassWorkspaceError: LocalizedError {
  case lessonEditFailed(String)

  var errorDescription: String? {
    switch self {
    case .lessonEditFailed(let message):
      return message
    }
  }
}

extension String {
  fileprivate func nonOverlappingOccurrences(of needle: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var searchStart = startIndex
    while let range = range(of: needle, range: searchStart..<endIndex) {
      count += 1
      searchStart = range.upperBound
    }
    return count
  }
}
