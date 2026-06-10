import Foundation

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

struct ContainerSandboxRoute: Equatable, Codable {
  var hostWorkspacePath: String
  var containerWorkspacePath: String

  init(hostWorkspacePath: String, containerWorkspacePath: String = "/workspace") {
    self.hostWorkspacePath = hostWorkspacePath
    self.containerWorkspacePath = containerWorkspacePath
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

  static func plan(repoURL: URL) -> Self {
    containerizedLinux(repoURL: repoURL)
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

  var effectiveRouteTitle: String {
    switch effectiveRoute {
    case .host:
      return "This Mac"
    case .containerizedLinux:
      return "Containerized Linux"
    }
  }

  var effectiveRouteIdentifier: String {
    switch effectiveRoute {
    case .host:
      return "native-macos"
    case .containerizedLinux:
      return "containerized-linux"
    }
  }

  var imageLabel: String {
    switch effectiveRoute {
    case .host:
      return "none"
    case .containerizedLinux:
      return "docker.io/library/node:22-bookworm"
    }
  }

  var workspaceLabel: String {
    switch effectiveRoute {
    case .host:
      return "host"
    case .containerizedLinux(let route):
      return Self.boundedText(route.containerWorkspacePath, limit: Self.labelLimit)
    }
  }

  var fallbackReasonLabel: String {
    fallbackReason ?? "none"
  }

  static func userFacingFallbackReason(_ reason: String) -> String {
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

  func preflightSummary(phase: String) -> String {
    [
      "\(phase) runtime: selected \(selectedPreference.title)",
      "effective route \(effectiveRouteTitle)",
      "image \(imageLabel)",
      "workspace \(workspaceLabel)",
      "fallback \(fallbackReason.map(Self.userFacingFallbackReason) ?? "none")",
    ].joined(separator: "; ")
  }

  func routeDetail() -> String {
    switch effectiveRoute {
    case .host:
      if let fallbackReason {
        return "Using this Mac because \(Self.userFacingFallbackReason(fallbackReason))"
      }
      return "Using this Mac for this phase."
    case .containerizedLinux:
      return "Using the containerized Linux runtime for this phase."
    }
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
