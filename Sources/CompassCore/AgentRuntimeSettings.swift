import Foundation

package enum AgentPhase: String, Sendable, CaseIterable {
  case plan
  case develop
  case critic

  package var identifier: String { rawValue }
}

package struct AgentRuntimeSettings: Equatable, Sendable {
  package static let defaultTextProvider: AgentProviderKind = .mlx
  package static let defaultContextWindowTokens = LocalModelCatalog.defaultContextWindowTokens

  package var textProvider: AgentProviderKind
  package var contextWindowTokens: Int

  package init(
    textProvider: AgentProviderKind = AgentRuntimeSettings.defaultTextProvider,
    contextWindowTokens: Int = AgentRuntimeSettings.defaultContextWindowTokens
  ) {
    self.textProvider = textProvider
    self.contextWindowTokens = max(0, contextWindowTokens)
  }

  package static func defaultFromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let contextWindow =
      environment.trimmedValue("COMPASS_AGENT_CONTEXT_WINDOW_TOKENS")
      .flatMap(Int.init) ?? defaultContextWindowTokens
    return Self(
      contextWindowTokens: contextWindow
    )
  }

  package var codemapModel: String {
    LocalModelCatalog.blessedModelID
  }

  package var isTextCapabilityReady: Bool {
    isTextCapabilityRunnable(localModelReady: LocalModelCatalog.isBlessedModelReady())
  }

  package func isTextCapabilityRunnable(localModelReady: Bool) -> Bool {
    localModelReady
  }

  package func model(for phase: AgentPhase, sidebarOverride: String = "") -> String {
    _ = phase
    _ = sidebarOverride
    return LocalModelCatalog.blessedModelID
  }
}

package extension Dictionary where Key == String, Value == String {
  package func trimmedValue(_ key: String) -> String? {
    let trimmed = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}
