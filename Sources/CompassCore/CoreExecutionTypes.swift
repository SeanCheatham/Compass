import CompassSandbox
import Foundation

package enum AgentExecutionEnvironmentPreference: String, Codable, Identifiable {
  case containerizedLinux = "containerized_linux"

  package var id: Self { self }

  package init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    switch raw {
    case Self.containerizedLinux.rawValue, "shared_vm", "native_macos", "devcontainer_preferred":
      self = .containerizedLinux
    default:
      self = .containerizedLinux
    }
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  package var title: String { "Containerized Linux" }
  package var systemImage: String { "shippingbox" }
}

package struct ContainerSandboxRoute: Equatable, Codable {
  package var hostWorkspacePath: String
  package var containerWorkspacePath: String

  package init(hostWorkspacePath: String, containerWorkspacePath: String = "/workspace") {
    self.hostWorkspacePath = hostWorkspacePath
    self.containerWorkspacePath = containerWorkspacePath
  }
}

package struct AgentExecutionInvocation: Sendable, Equatable {
  package var executable: String
  package var arguments: [String]
  package var workingDirectory: URL?

  package init(executable: String, arguments: [String], workingDirectory: URL? = nil) {
    self.executable = executable
    self.arguments = arguments
    self.workingDirectory = workingDirectory?.standardizedFileURL
  }
}

package struct AgentExecutionLaunchPlan: Equatable {
  package static let fallbackReasonLimit = 180
  package static let labelLimit = 80

  package enum Route: Equatable {
    case host
    case containerizedLinux(ContainerSandboxRoute)
  }

  package var selectedPreference: AgentExecutionEnvironmentPreference
  package var effectiveRoute: Route
  package var fallbackReason: String?

  package init(
    selectedPreference: AgentExecutionEnvironmentPreference = .containerizedLinux,
    effectiveRoute: Route,
    fallbackReason: String? = nil
  ) {
    self.selectedPreference = selectedPreference
    self.effectiveRoute = effectiveRoute
    self.fallbackReason = Self.boundedOptionalText(fallbackReason, limit: Self.fallbackReasonLimit)
  }

  package static func host(fallbackReason: String? = nil) -> Self {
    Self(effectiveRoute: .host, fallbackReason: fallbackReason)
  }

  package static func containerizedLinux(
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

  package static func plan(repoURL: URL) -> Self {
    containerizedLinux(repoURL: repoURL)
  }

  package var effectiveRouteIdentifier: String {
    switch effectiveRoute {
    case .host: return "native-macos"
    case .containerizedLinux: return "containerized-linux"
    }
  }

  package var effectiveRouteTitle: String {
    switch effectiveRoute {
    case .host: return "This Mac"
    case .containerizedLinux: return "Containerized Linux"
    }
  }

  package var imageLabel: String {
    switch effectiveRoute {
    case .host: return "none"
    case .containerizedLinux: return ContainerSandboxConfiguration.defaultRuntimeImage
    }
  }

  package var workspaceLabel: String {
    switch effectiveRoute {
    case .host: return "host"
    case .containerizedLinux(let route): return Self.boundedText(route.containerWorkspacePath, limit: Self.labelLimit)
    }
  }

  package var fallbackReasonLabel: String {
    fallbackReason ?? "none"
  }

  package var isVMRoute: Bool {
    false
  }

  package var isContainerRoute: Bool {
    switch effectiveRoute {
    case .host: return false
    case .containerizedLinux: return true
    }
  }

  package static func userFacingFallbackReason(_ reason: String) -> String {
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

  package func preflightSummary(phase: String) -> String {
    [
      "\(phase) runtime: selected \(selectedPreference.title)",
      "effective route \(effectiveRouteTitle)",
      "image \(imageLabel)",
      "workspace \(workspaceLabel)",
      "fallback \(fallbackReason.map(Self.userFacingFallbackReason) ?? "none")",
    ].joined(separator: "; ")
  }

  package func routeDetail() -> String {
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

  package func shellInvocation(command: String, hostWorkingDirectory: URL) -> AgentExecutionInvocation {
    AgentExecutionInvocation(
      executable: "/bin/zsh",
      arguments: ["-lc", command],
      workingDirectory: hostWorkingDirectory
    )
  }

  package static func boundedText(_ text: String, limit: Int) -> String {
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

package struct RepositoryActivitySourceSnapshot {
  package enum SourceAvailability: String, Equatable {
    case available
    case noRepository = "no-repository"
    case notScanned = "not-scanned"
    case storageRootMissing = "storage-root-missing"
    case sessionsRecordMissing = "sessions-record-missing"
    case sessionsRecordOversized = "sessions-record-oversized"
    case sessionsRecordUnreadable = "sessions-record-unreadable"
  }
}

package enum DraftRefinementService {
  package static func normalizeDraft(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

package enum RuntimeCopy {
  package static func containsImplementationTerm(_ text: String) -> Bool {
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
