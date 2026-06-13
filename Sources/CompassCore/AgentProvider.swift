import Foundation

package enum AgentProviderKind: String, Sendable, CaseIterable, Codable {
  case mlx

  package var displayName: String { "MLX" }
  package var requiresCredentials: Bool { false }
  package var supportedCapabilities: [AgentCapability] { [.text] }

  package func supports(_ capability: AgentCapability) -> Bool {
    capability == .text
  }

  package func defaultModel(for capability: AgentCapability) -> String? {
    supports(capability) ? LocalModelCatalog.blessedModelID : nil
  }

  package func usesModelField(for capability: AgentCapability) -> Bool {
    false
  }

  package func textContextWindowTokens(for modelIdentifier: String?) -> Int {
    defaultTextContextWindowTokens
  }

  package func defaultModel(for phase: AgentPhase, baseModel: String) -> String? {
    nil
  }

  package var defaultTextContextWindowTokens: Int { 4_096 }
}

package enum AgentCapability: String, Sendable, CaseIterable, Codable {
  case text

  package var displayName: String { "Text" }
  package var systemImageName: String { "text.bubble" }
  package var isRequired: Bool { true }
  package var availableProviders: [AgentProviderKind] { [.mlx] }
}
