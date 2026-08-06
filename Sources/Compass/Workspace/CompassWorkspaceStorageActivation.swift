import CompassCore
import Foundation

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
      try workspace.sessionRecordStore.validatePrimaryRecord()
    } catch {
      return CandidateValidation(
        kind: .candidateInvalid,
        missingItems: [],
        invalidReason: "sessions record could not be decoded: \(error.localizedDescription)"
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
    case .brief:
      return workspace.briefURL
    case .requirements:
      return workspace.requirementsURL
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
