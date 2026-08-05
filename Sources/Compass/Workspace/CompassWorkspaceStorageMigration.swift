import CompassCore
import Foundation

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
