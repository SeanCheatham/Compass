import Foundation
import CompassCore

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
