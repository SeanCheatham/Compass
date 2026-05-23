import Foundation

struct RepositoryActivitySourceSnapshot: Equatable {
  static let maxSessionsFileBytes: UInt64 = 2 * 1024 * 1024

  enum SourceAvailability: String, Equatable {
    case available
    case noRepository = "no-repository"
    case notScanned = "not-scanned"
    case storageRootMissing = "storage-root-missing"
    case sessionsRecordMissing = "sessions-record-missing"
    case sessionsRecordOversized = "sessions-record-oversized"
    case sessionsRecordUnreadable = "sessions-record-unreadable"
  }

  enum RepoLocalSessionsState: String, Equatable {
    case activeSource = "active-source"
    case ignoredMissing = "ignored-missing"
    case ignoredCompatible = "ignored-compatible"
    case ignoredOversized = "ignored-oversized"
    case ignoredUnreadable = "ignored-unreadable"
  }

  var activeStorage: KnownProjectActiveStorage
  var storageRootURL: URL?
  var sessionsRecordURL: URL?
  var sourceAvailability: SourceAvailability
  var repoLocalSessionsRecordURL: URL?
  var repoLocalSessionsState: RepoLocalSessionsState

  var activeStorageIdentifier: String { activeStorage.rawValue }
  var sourceAvailabilityIdentifier: String { sourceAvailability.rawValue }
  var repoLocalSessionsStateIdentifier: String { repoLocalSessionsState.rawValue }

  var ignoresRepoLocalSessions: Bool {
    switch repoLocalSessionsState {
    case .activeSource:
      return false
    case .ignoredMissing,
      .ignoredCompatible,
      .ignoredOversized,
      .ignoredUnreadable:
      return true
    }
  }

  var repoLocalSessionsIgnoredIdentifier: String {
    ignoresRepoLocalSessions ? "ignored" : "active"
  }

  var identifier: String {
    [
      "storage:\(activeStorageIdentifier)",
      "root:\(storageRootURL?.standardizedFileURL.path ?? "none")",
      "sessions:\(sessionsRecordURL?.standardizedFileURL.path ?? "none")",
      "availability:\(sourceAvailabilityIdentifier)",
      "repo-local:\(repoLocalSessionsStateIdentifier)",
      "repo-local-mode:\(repoLocalSessionsIgnoredIdentifier)",
    ].joined(separator: "|")
  }

  static func notScanned(activeStorage: KnownProjectActiveStorage = .repoLocal) -> Self {
    Self(
      activeStorage: activeStorage,
      storageRootURL: nil,
      sessionsRecordURL: nil,
      sourceAvailability: .notScanned,
      repoLocalSessionsRecordURL: nil,
      repoLocalSessionsState: activeStorage == .repoLocal ? .activeSource : .ignoredMissing
    )
  }

  static func noRepository(activeStorage: KnownProjectActiveStorage) -> Self {
    Self(
      activeStorage: activeStorage,
      storageRootURL: nil,
      sessionsRecordURL: nil,
      sourceAvailability: .noRepository,
      repoLocalSessionsRecordURL: nil,
      repoLocalSessionsState: activeStorage == .repoLocal ? .activeSource : .ignoredMissing
    )
  }

  static func snapshot(
    activeStorage: KnownProjectActiveStorage,
    workspace: CompassWorkspace,
    fileManager: FileManager = .default
  ) -> Self {
    let storageRootURL = workspace.compassURL.standardizedFileURL
    let sessionsRecordURL = workspace.sessionsRecordURL.standardizedFileURL
    let repoLocalSessionsRecordURL = workspace.repoLocalCompassURL
      .appending(path: "sessions.json")
      .standardizedFileURL
    let sourceAvailability = availability(
      storageRootURL: storageRootURL,
      sessionsRecordURL: sessionsRecordURL,
      fileManager: fileManager
    )
    let repoLocalSessionsState = Self.repoLocalSessionsState(
      activeStorage: activeStorage,
      repoLocalStorageRootURL: workspace.repoLocalCompassURL,
      repoLocalSessionsRecordURL: repoLocalSessionsRecordURL,
      fileManager: fileManager
    )

    return Self(
      activeStorage: activeStorage,
      storageRootURL: storageRootURL,
      sessionsRecordURL: sessionsRecordURL,
      sourceAvailability: sourceAvailability,
      repoLocalSessionsRecordURL: repoLocalSessionsRecordURL,
      repoLocalSessionsState: repoLocalSessionsState
    )
  }

  private static func repoLocalSessionsState(
    activeStorage: KnownProjectActiveStorage,
    repoLocalStorageRootURL: URL,
    repoLocalSessionsRecordURL: URL,
    fileManager: FileManager
  ) -> RepoLocalSessionsState {
    guard activeStorage != .repoLocal else { return .activeSource }

    switch availability(
      storageRootURL: repoLocalStorageRootURL,
      sessionsRecordURL: repoLocalSessionsRecordURL,
      fileManager: fileManager
    ) {
    case .available:
      return .ignoredCompatible
    case .sessionsRecordOversized:
      return .ignoredOversized
    case .sessionsRecordUnreadable:
      return .ignoredUnreadable
    case .storageRootMissing,
      .sessionsRecordMissing,
      .noRepository,
      .notScanned:
      return .ignoredMissing
    }
  }

  private static func availability(
    storageRootURL: URL,
    sessionsRecordURL: URL,
    fileManager: FileManager
  ) -> SourceAvailability {
    guard directoryExists(storageRootURL, fileManager: fileManager) else {
      return .storageRootMissing
    }
    guard fileExists(sessionsRecordURL, fileManager: fileManager) else {
      return .sessionsRecordMissing
    }
    guard let attributes = try? fileManager.attributesOfItem(atPath: sessionsRecordURL.path),
      let size = attributes[.size] as? NSNumber
    else {
      return .sessionsRecordUnreadable
    }
    guard size.uint64Value <= maxSessionsFileBytes else {
      return .sessionsRecordOversized
    }
    guard let data = try? Data(contentsOf: sessionsRecordURL) else {
      return .sessionsRecordUnreadable
    }
    guard !data.isEmpty else { return .available }
    guard (try? JSONDecoder().decode([SessionRecord].self, from: data)) != nil else {
      return .sessionsRecordUnreadable
    }
    return .available
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
}
