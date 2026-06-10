import Foundation

enum AgentExecutionEnvironmentPreference: String, Codable, Identifiable {
  case containerizedLinux = "containerized_linux"

  var id: Self { self }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    switch raw {
    case Self.containerizedLinux.rawValue, "shared_vm", "native_macos", "devcontainer_preferred":
      self = .containerizedLinux
    default:
      self = .containerizedLinux
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  var title: String { "Containerized Linux" }
  var systemImage: String { "shippingbox" }
}

struct ContainerSandboxRoute: Equatable, Codable {
  var hostWorkspacePath: String
  var containerWorkspacePath: String

  init(hostWorkspacePath: String, containerWorkspacePath: String = "/workspace") {
    self.hostWorkspacePath = hostWorkspacePath
    self.containerWorkspacePath = containerWorkspacePath
  }
}

struct AgentExecutionInvocation: Sendable, Equatable {
  var executable: String
  var arguments: [String]
  var workingDirectory: URL?

  init(executable: String, arguments: [String], workingDirectory: URL? = nil) {
    self.executable = executable
    self.arguments = arguments
    self.workingDirectory = workingDirectory?.standardizedFileURL
  }
}

struct AgentExecutionLaunchPlan: Equatable {
  static let fallbackReasonLimit = 180
  static let labelLimit = 80

  enum Route: Equatable {
    case host
    case containerizedLinux(ContainerSandboxRoute)
  }

  var selectedPreference: AgentExecutionEnvironmentPreference
  var effectiveRoute: Route
  var fallbackReason: String?

  init(
    selectedPreference: AgentExecutionEnvironmentPreference = .containerizedLinux,
    effectiveRoute: Route,
    fallbackReason: String? = nil
  ) {
    self.selectedPreference = selectedPreference
    self.effectiveRoute = effectiveRoute
    self.fallbackReason = Self.boundedOptionalText(fallbackReason, limit: Self.fallbackReasonLimit)
  }

  static func host(fallbackReason: String? = nil) -> Self {
    Self(effectiveRoute: .host, fallbackReason: fallbackReason)
  }

  static func containerizedLinux(
    repoURL: URL,
    containerWorkspacePath: String = "/workspace"
  ) -> Self {
    Self(
      effectiveRoute: .containerizedLinux(
        ContainerSandboxRoute(
          hostWorkspacePath: repoURL.standardizedFileURL.path,
          containerWorkspacePath: containerWorkspacePath
        )
      )
    )
  }

  var effectiveRouteIdentifier: String {
    switch effectiveRoute {
    case .host: return "host"
    case .containerizedLinux: return "containerized-linux"
    }
  }

  var effectiveRouteTitle: String {
    switch effectiveRoute {
    case .host: return "Host"
    case .containerizedLinux: return "Containerized Linux"
    }
  }

  var imageLabel: String {
    switch effectiveRoute {
    case .host: return "none"
    case .containerizedLinux: return "docker.io/library/node:22-bookworm"
    }
  }

  var workspaceLabel: String {
    switch effectiveRoute {
    case .host: return "host"
    case .containerizedLinux(let route): return route.containerWorkspacePath
    }
  }

  var fallbackReasonLabel: String {
    fallbackReason ?? "none"
  }

  var isVMRoute: Bool {
    false
  }

  var isContainerRoute: Bool {
    switch effectiveRoute {
    case .host: return false
    case .containerizedLinux: return true
    }
  }

  static func userFacingFallbackReason(_ reason: String) -> String {
    boundedText(reason, limit: fallbackReasonLimit)
  }

  func shellInvocation(command: String, hostWorkingDirectory: URL) -> AgentExecutionInvocation {
    AgentExecutionInvocation(
      executable: "/bin/zsh",
      arguments: ["-lc", command],
      workingDirectory: hostWorkingDirectory
    )
  }

  static func boundedText(_ text: String, limit: Int) -> String {
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

struct RepositoryActivitySourceSnapshot {
  enum SourceAvailability: String, Equatable {
    case available
    case noRepository = "no-repository"
    case notScanned = "not-scanned"
    case storageRootMissing = "storage-root-missing"
    case sessionsRecordMissing = "sessions-record-missing"
    case sessionsRecordOversized = "sessions-record-oversized"
    case sessionsRecordUnreadable = "sessions-record-unreadable"
  }
}

enum DraftRefinementService {
  static func normalizeDraft(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum RuntimeCopy {
  static func containsImplementationTerm(_ text: String) -> Bool {
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
