import Foundation

public enum AgentProviderKind: String, Sendable, CaseIterable, Codable {
  case openAICompatible
  case mlx

  public var displayName: String {
    switch self {
    case .openAICompatible: return "OpenAI-compatible"
    case .mlx: return "MLX"
    }
  }

  public var requiresCredentials: Bool {
    switch self {
    case .openAICompatible: return true
    case .mlx: return false
    }
  }

  public var defaultBaseURLString: String? {
    switch self {
    case .openAICompatible: return "https://api.kimi.com/coding/v1"
    case .mlx: return nil
    }
  }

  public var defaultBaseURL: URL? {
    defaultBaseURLString.flatMap(URL.init(string:))
  }

  public var supportedCapabilities: [AgentCapability] { [.text] }

  public func supports(_ capability: AgentCapability) -> Bool {
    capability == .text
  }

  public func defaultModel(for capability: AgentCapability) -> String? {
    guard supports(capability) else { return nil }
    switch self {
    case .openAICompatible:
      return "k3"
    case .mlx:
      return LocalModelCatalog.blessedModelID
    }
  }

  public func usesModelField(for capability: AgentCapability) -> Bool {
    guard supports(capability) else { return false }
    switch self {
    case .openAICompatible: return true
    case .mlx: return false
    }
  }

  public func textContextWindowTokens(for modelIdentifier: String?) -> Int {
    _ = modelIdentifier
    return defaultTextContextWindowTokens
  }

  public func defaultModel(for phase: AgentPhase, baseModel: String) -> String? {
    _ = phase
    let trimmed = baseModel.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return defaultModel(for: .text)
  }

  public var defaultTextContextWindowTokens: Int {
    switch self {
    case .openAICompatible: return 128_000
    case .mlx: return LocalModelCatalog.defaultContextWindowTokens
    }
  }
}

public enum AgentCapability: String, Sendable, CaseIterable, Codable {
  case text

  public var displayName: String { "Text" }
  public var systemImageName: String { "text.bubble" }
  public var isRequired: Bool { true }
  public var availableProviders: [AgentProviderKind] { [.openAICompatible, .mlx] }
}
