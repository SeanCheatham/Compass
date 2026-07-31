import Foundation

enum AgentProviderKind: String, Sendable, CaseIterable, Codable {
  case openAICompatible
  case mlx

  var displayName: String {
    switch self {
    case .openAICompatible: return "OpenAI-compatible"
    case .mlx: return "MLX"
    }
  }

  var requiresCredentials: Bool {
    switch self {
    case .openAICompatible: return true
    case .mlx: return false
    }
  }

  var defaultBaseURLString: String? {
    switch self {
    case .openAICompatible: return "https://api.kimi.com/coding/v1"
    case .mlx: return nil
    }
  }

  var defaultBaseURL: URL? {
    defaultBaseURLString.flatMap(URL.init(string:))
  }

  var supportedCapabilities: [AgentCapability] { [.text] }

  func supports(_ capability: AgentCapability) -> Bool {
    capability == .text
  }

  func defaultModel(for capability: AgentCapability) -> String? {
    guard supports(capability) else { return nil }
    switch self {
    case .openAICompatible:
      return "k3"
    case .mlx:
      return LocalModelCatalog.blessedModelID
    }
  }

  func usesModelField(for capability: AgentCapability) -> Bool {
    guard supports(capability) else { return false }
    switch self {
    case .openAICompatible: return true
    case .mlx: return false
    }
  }

  func textContextWindowTokens(for modelIdentifier: String?) -> Int {
    _ = modelIdentifier
    return defaultTextContextWindowTokens
  }

  func defaultModel(for phase: AgentPhase, baseModel: String) -> String? {
    _ = phase
    let trimmed = baseModel.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return defaultModel(for: .text)
  }

  var defaultTextContextWindowTokens: Int {
    switch self {
    case .openAICompatible: return 128_000
    case .mlx: return 4_096
    }
  }
}

enum AgentCapability: String, Sendable, CaseIterable, Codable {
  case text

  var displayName: String { "Text" }
  var systemImageName: String { "text.bubble" }
  var isRequired: Bool { true }
  var availableProviders: [AgentProviderKind] { [.openAICompatible, .mlx] }
}
