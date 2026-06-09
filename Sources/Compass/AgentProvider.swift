import Foundation

enum AgentProviderKind: String, Sendable, CaseIterable, Codable {
  case mlx

  var displayName: String { "MLX" }
  var requiresCredentials: Bool { false }
  var supportedCapabilities: [AgentCapability] { [.text] }

  func supports(_ capability: AgentCapability) -> Bool {
    capability == .text
  }

  func defaultModel(for capability: AgentCapability) -> String? {
    supports(capability) ? LocalModelCatalog.blessedModelID : nil
  }

  func usesModelField(for capability: AgentCapability) -> Bool {
    false
  }

  func textContextWindowTokens(for modelIdentifier: String?) -> Int {
    defaultTextContextWindowTokens
  }

  func defaultModel(for phase: AgentPhase, baseModel: String) -> String? {
    nil
  }

  var defaultTextContextWindowTokens: Int { 4_096 }
}

enum AgentCapability: String, Sendable, CaseIterable, Codable {
  case text

  var displayName: String { "Text" }
  var systemImageName: String { "text.bubble" }
  var isRequired: Bool { true }
  var availableProviders: [AgentProviderKind] { [.mlx] }
}
