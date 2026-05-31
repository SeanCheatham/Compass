import Foundation

struct RepositoryActivitySourceSnapshot: Equatable {
  static let maxSessionsFileBytes = SessionRecordStore.maxSegmentBytes

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
    let sessionStore = SessionRecordStore(compassURL: storageRootURL, fileManager: fileManager)
    let sessionsRecordURL = sessionStore.activeRecordURL.standardizedFileURL
    let repoLocalSessionStore = SessionRecordStore(
      compassURL: workspace.repoLocalCompassURL.standardizedFileURL,
      fileManager: fileManager
    )
    let repoLocalSessionsRecordURL = repoLocalSessionStore.activeRecordURL
    let sourceAvailability = sessionStore.activeSegmentAvailability()
    let repoLocalSessionsState = Self.repoLocalSessionsState(
      activeStorage: activeStorage,
      sessionStore: repoLocalSessionStore
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
    sessionStore: SessionRecordStore
  ) -> RepoLocalSessionsState {
    guard activeStorage != .repoLocal else { return .activeSource }

    switch sessionStore.activeSegmentAvailability() {
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
}
