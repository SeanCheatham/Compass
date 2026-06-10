import Foundation

enum AgentExecutionEnvironmentPreference: String, Codable, Identifiable {
  case sharedVM = "shared_vm"

  var id: Self { self }
  var title: String { "Host" }
  var systemImage: String { "desktopcomputer" }
}

enum SharedCompassVMReadiness: Equatable, Codable {
  case unavailable(String)
  case notProvisioned
  case downloadingIPSW(Double)
  case installing(Double)
  case guestPrepping
  case provisioningDevTools(Double)
  case ready(String)
  case error(String)
}

struct SharedVMRoute: Equatable, Codable {
  var guestWorkspacePath: String
}

protocol SharedVMToolchainService: Sendable {}

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
    case sharedVM(SharedVMRoute)
  }

  var selectedPreference: AgentExecutionEnvironmentPreference
  var effectiveRoute: Route
  var vmReadiness: SharedCompassVMReadiness?
  var fallbackReason: String?

  static func host(
    vmReadiness: SharedCompassVMReadiness? = nil,
    fallbackReason: String? = nil
  ) -> Self {
    Self(
      selectedPreference: .sharedVM,
      effectiveRoute: .host,
      vmReadiness: vmReadiness,
      fallbackReason: fallbackReason
    )
  }

  var effectiveRouteIdentifier: String {
    switch effectiveRoute {
    case .host: return "host"
    case .sharedVM: return "shared-vm"
    }
  }

  var effectiveRouteTitle: String {
    switch effectiveRoute {
    case .host: return "Host"
    case .sharedVM: return "Shared VM"
    }
  }

  var imageLabel: String {
    switch effectiveRoute {
    case .host: return "none"
    case .sharedVM: return "shared-vm"
    }
  }

  var workspaceLabel: String {
    switch effectiveRoute {
    case .host: return "host"
    case .sharedVM(let route): return route.guestWorkspacePath
    }
  }

  var isVMRoute: Bool {
    switch effectiveRoute {
    case .host: return false
    case .sharedVM: return true
    }
  }

  static func userFacingFallbackReason(_ reason: String) -> String {
    StringUtils.boundedText(reason, limit: fallbackReasonLimit)
  }

  func shellInvocation(command: String, hostWorkingDirectory: URL) -> AgentExecutionInvocation {
    AgentExecutionInvocation(
      executable: "/bin/zsh",
      arguments: ["-lc", command],
      workingDirectory: hostWorkingDirectory
    )
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

enum PrivateWorkspaceCopy {
  static func containsImplementationTerm(_ text: String) -> Bool {
    let normalized = text.lowercased()
    return normalized.contains("shared vm")
      || normalized.contains("ssh")
      || normalized.contains("ipsw")
      || normalized.contains("guest")
      || normalized.range(
        of: #"\b[\w.-]+@\d{1,3}(?:\.\d{1,3}){3}\b"#,
        options: .regularExpression
      ) != nil
  }
}
