import Foundation

enum AgentPhase: String, Sendable, CaseIterable {
  case plan
  case develop
  case critic
}

struct AgentRuntimeSettings: Equatable, Sendable {
  static let defaultTextProvider: AgentProviderKind = .mlx
  static let defaultContextWindowTokens = LocalModelCatalog.defaultContextWindowTokens

  var textProvider: AgentProviderKind
  var contextWindowTokens: Int

  init(
    textProvider: AgentProviderKind = AgentRuntimeSettings.defaultTextProvider,
    contextWindowTokens: Int = AgentRuntimeSettings.defaultContextWindowTokens
  ) {
    self.textProvider = textProvider
    self.contextWindowTokens = max(0, contextWindowTokens)
  }

  static func defaultFromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let contextWindow =
      environment.trimmedValue("COMPASS_AGENT_CONTEXT_WINDOW_TOKENS")
      .flatMap(Int.init) ?? defaultContextWindowTokens
    return Self(
      contextWindowTokens: contextWindow
    )
  }

  var codemapModel: String {
    LocalModelCatalog.blessedModelID
  }

  var isTextCapabilityReady: Bool {
    isTextCapabilityRunnable(localModelReady: LocalModelCatalog.isBlessedModelReady())
  }

  func isTextCapabilityRunnable(localModelReady: Bool) -> Bool {
    localModelReady
  }

  func model(for phase: AgentPhase, sidebarOverride: String = "") -> String {
    _ = phase
    _ = sidebarOverride
    return LocalModelCatalog.blessedModelID
  }
}

extension Dictionary where Key == String, Value == String {
  func trimmedValue(_ key: String) -> String? {
    let trimmed = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}
