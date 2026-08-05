import Foundation

public enum AgentExecutionEnvironmentPreference: String, Codable, Identifiable {
  case macOSVM = "macos_vm"

  public var id: Self { self }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    // All legacy identifiers (including the removed container runtime)
    // migrate to the macOS VM route.
    _ = try container.decode(String.self)
    self = .macOSVM
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var title: String { "macOS VM" }
  public var systemImage: String { "desktopcomputer" }
}

public struct MacOSVMRoute: Equatable, Codable {
  public var hostWorkspacePath: String
  public var guestWorkspacePath: String

  public init(
    hostWorkspacePath: String,
    guestWorkspacePath: String = SharedCompassVMGuestLayout.current.reposRoot
  ) {
    self.hostWorkspacePath = hostWorkspacePath
    self.guestWorkspacePath = guestWorkspacePath
  }
}

public struct AgentExecutionInvocation: Sendable, Equatable {
  public var executable: String
  public var arguments: [String]
  public var workingDirectory: URL?

  public init(executable: String, arguments: [String], workingDirectory: URL? = nil) {
    self.executable = executable
    self.arguments = arguments
    self.workingDirectory = workingDirectory?.standardizedFileURL
  }
}

public struct AgentExecutionLaunchPlan: Equatable {
  public static let fallbackReasonLimit = 180
  public static let labelLimit = 80

  public enum Route: Equatable {
    case host
    case macOSVM(MacOSVMRoute)
  }

  public var selectedPreference: AgentExecutionEnvironmentPreference
  public var effectiveRoute: Route
  public var fallbackReason: String?

  public init(
    selectedPreference: AgentExecutionEnvironmentPreference = .macOSVM,
    effectiveRoute: Route,
    fallbackReason: String? = nil
  ) {
    self.selectedPreference = selectedPreference
    self.effectiveRoute = effectiveRoute
    self.fallbackReason = Self.boundedOptionalText(fallbackReason, limit: Self.fallbackReasonLimit)
  }

  public static func host(fallbackReason: String? = nil) -> Self {
    Self(effectiveRoute: .host, fallbackReason: fallbackReason)
  }

  public static func macOSVM(repoURL: URL, guestWorkspacePath: String? = nil) -> Self {
    Self(
      selectedPreference: .macOSVM,
      effectiveRoute: .macOSVM(
        MacOSVMRoute(
          hostWorkspacePath: repoURL.standardizedFileURL.path,
          guestWorkspacePath: guestWorkspacePath
            ?? SharedCompassVMGuestLayout.current.reposRoot
        )
      )
    )
  }

  public static func plan(repoURL: URL) -> Self {
    macOSVM(repoURL: repoURL)
  }

  public static func plan(
    repoURL: URL,
    preference _: AgentExecutionEnvironmentPreference
  ) -> Self {
    macOSVM(repoURL: repoURL)
  }

  public var effectiveRouteIdentifier: String {
    switch effectiveRoute {
    case .host: return "native-macos"
    case .macOSVM: return "macos-vm"
    }
  }

  public var effectiveRouteTitle: String {
    switch effectiveRoute {
    case .host: return "This Mac"
    case .macOSVM: return "macOS VM"
    }
  }

  public var imageLabel: String {
    switch effectiveRoute {
    case .host: return "none"
    case .macOSVM: return "macOS restore image (IPSW)"
    }
  }

  public var workspaceLabel: String {
    switch effectiveRoute {
    case .host: return "host"
    case .macOSVM(let route):
      return Self.boundedText(route.guestWorkspacePath, limit: Self.labelLimit)
    }
  }

  public var fallbackReasonLabel: String {
    fallbackReason ?? "none"
  }

  public var isVMRoute: Bool {
    switch effectiveRoute {
    case .macOSVM: return true
    case .host: return false
    }
  }

  public static func userFacingFallbackReason(_ reason: String) -> String {
    punctuatedSentence(boundedText(reason, limit: fallbackReasonLimit))
  }

  private static func punctuatedSentence(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let last = trimmed.last else { return "" }
    if [".", "!", "?"].contains(String(last)) {
      return trimmed
    }
    return "\(trimmed)."
  }

  public func preflightSummary(phase: String) -> String {
    [
      "\(phase) runtime: selected \(selectedPreference.title)",
      "effective route \(effectiveRouteTitle)",
      "image \(imageLabel)",
      "workspace \(workspaceLabel)",
      "fallback \(fallbackReason.map(Self.userFacingFallbackReason) ?? "none")",
    ].joined(separator: "; ")
  }

  public func routeDetail() -> String {
    switch effectiveRoute {
    case .host:
      if let fallbackReason {
        return "Using this Mac because \(Self.userFacingFallbackReason(fallbackReason))"
      }
      return "Using this Mac for this phase."
    case .macOSVM:
      return "Using the embedded macOS VM for this phase."
    }
  }

  public func shellInvocation(command: String, hostWorkingDirectory: URL) -> AgentExecutionInvocation {
    AgentExecutionInvocation(
      executable: "/bin/zsh",
      arguments: ["-lc", command],
      workingDirectory: hostWorkingDirectory
    )
  }

  public static func boundedText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    let normalized =
      text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > limit else { return normalized }
    return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func boundedOptionalText(_ text: String?, limit: Int) -> String? {
    let bounded = boundedText(text ?? "", limit: limit)
    return bounded.isEmpty ? nil : bounded
  }
}

public enum KnownProjectActiveStorage: String, Codable, CaseIterable, Identifiable {
  case repoLocal = "repo_local"
  case applicationSupport = "application_support"

  public var id: Self { self }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    self = KnownProjectActiveStorage(rawValue: rawValue) ?? .repoLocal
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct RepositoryActivitySourceSnapshot: Equatable {
  public enum SourceAvailability: String, Equatable {
    case available
    case noRepository = "no-repository"
    case notScanned = "not-scanned"
    case storageRootMissing = "storage-root-missing"
    case sessionsRecordMissing = "sessions-record-missing"
    case sessionsRecordOversized = "sessions-record-oversized"
    case sessionsRecordUnreadable = "sessions-record-unreadable"
  }

  public enum RepoLocalSessionsState: String, Equatable {
    case activeSource = "active-source"
    case ignoredMissing = "ignored-missing"
    case ignoredCompatible = "ignored-compatible"
    case ignoredOversized = "ignored-oversized"
    case ignoredUnreadable = "ignored-unreadable"
  }

  public var activeStorage: KnownProjectActiveStorage
  public var storageRootURL: URL?
  public var sessionsRecordURL: URL?
  public var sourceAvailability: SourceAvailability
  public var repoLocalSessionsRecordURL: URL?
  public var repoLocalSessionsState: RepoLocalSessionsState

  public init(
    activeStorage: KnownProjectActiveStorage,
    storageRootURL: URL?,
    sessionsRecordURL: URL?,
    sourceAvailability: SourceAvailability,
    repoLocalSessionsRecordURL: URL?,
    repoLocalSessionsState: RepoLocalSessionsState
  ) {
    self.activeStorage = activeStorage
    self.storageRootURL = storageRootURL
    self.sessionsRecordURL = sessionsRecordURL
    self.sourceAvailability = sourceAvailability
    self.repoLocalSessionsRecordURL = repoLocalSessionsRecordURL
    self.repoLocalSessionsState = repoLocalSessionsState
  }

  public var activeStorageIdentifier: String { activeStorage.rawValue }
  public var sourceAvailabilityIdentifier: String { sourceAvailability.rawValue }
  public var repoLocalSessionsStateIdentifier: String { repoLocalSessionsState.rawValue }

  public var ignoresRepoLocalSessions: Bool {
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

  public var repoLocalSessionsIgnoredIdentifier: String {
    ignoresRepoLocalSessions ? "ignored" : "active"
  }

  public var identifier: String {
    [
      "storage:\(activeStorageIdentifier)",
      "root:\(storageRootURL?.standardizedFileURL.path ?? "none")",
      "sessions:\(sessionsRecordURL?.standardizedFileURL.path ?? "none")",
      "availability:\(sourceAvailabilityIdentifier)",
      "repo-local:\(repoLocalSessionsStateIdentifier)",
      "repo-local-mode:\(repoLocalSessionsIgnoredIdentifier)",
    ].joined(separator: "|")
  }

  public static func notScanned(activeStorage: KnownProjectActiveStorage = .repoLocal) -> Self {
    Self(
      activeStorage: activeStorage,
      storageRootURL: nil,
      sessionsRecordURL: nil,
      sourceAvailability: .notScanned,
      repoLocalSessionsRecordURL: nil,
      repoLocalSessionsState: activeStorage == .repoLocal ? .activeSource : .ignoredMissing
    )
  }

  public static func noRepository(activeStorage: KnownProjectActiveStorage) -> Self {
    Self(
      activeStorage: activeStorage,
      storageRootURL: nil,
      sessionsRecordURL: nil,
      sourceAvailability: .noRepository,
      repoLocalSessionsRecordURL: nil,
      repoLocalSessionsState: activeStorage == .repoLocal ? .activeSource : .ignoredMissing
    )
  }

  public static func snapshot(
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

public enum RuntimeCopy {
  public static func containsImplementationTerm(_ text: String) -> Bool {
    let normalized = text.lowercased()
    return normalized.contains("shared vm")
      || normalized.contains("ssh")
      || normalized.contains("ipsw")

      || normalized.range(
        of: #"\b[\w.-]+@\d{1,3}(?:\.\d{1,3}){3}\b"#,
        options: .regularExpression
      ) != nil
  }
}
