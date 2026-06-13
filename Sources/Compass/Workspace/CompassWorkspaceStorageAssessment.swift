import Foundation
import CompassCore

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
    case sessionsRecord = "sessions.jsonl"

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
