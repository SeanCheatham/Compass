import Foundation

public final class AgentSettingsStore: @unchecked Sendable {
  public static let secretService = "com.seancheatham.Compass.agent"
  public static let textAPIKeyAccount = "api_key.text.openAICompatible"

  public enum Key: Hashable, CaseIterable {
    case textProvider
    case baseURL
    case model
    case contextWindowTokens

    public var rawValue: String {
      switch self {
      case .textProvider:
        return "compass.capability.text.provider"
      case .baseURL:
        return "compass.capability.text.openAICompatible.baseURL"
      case .model:
        return "compass.capability.text.openAICompatible.model"
      case .contextWindowTokens:
        return "compass.agent.contextWindowTokens"
      }
    }

    public static var allCases: [Key] {
      [.textProvider, .baseURL, .model, .contextWindowTokens]
    }
  }

  private let defaults: UserDefaults
  private let secrets: AgentSecretStorage
  private let environment: [String: String]

  public init(
    defaults: UserDefaults = .standard,
    secrets: AgentSecretStorage = AgentFileSecretStorage(),
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.environment = environment
  }

  public func load() -> AgentRuntimeSettings {
    let textProvider = resolveTextProvider()
    let baseURL = resolveBaseURL()
    let apiKey = resolveAPIKey()
    let model = resolveModel(for: textProvider)
    let contextWindow =
      environment.trimmedValue("COMPASS_AGENT_CONTEXT_WINDOW_TOKENS").flatMap(Int.init)
      ?? defaults.string(forKey: Key.contextWindowTokens.rawValue)
        .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
      ?? textProvider.textContextWindowTokens(for: model)

    return AgentRuntimeSettings(
      textProvider: textProvider,
      baseURL: baseURL,
      apiKey: apiKey,
      model: model,
      contextWindowTokens: max(0, contextWindow)
    )
  }

  public func setTextProvider(_ provider: AgentProviderKind) {
    defaults.set(provider.rawValue, forKey: Key.textProvider.rawValue)
  }

  public func setBaseURL(_ url: URL) {
    defaults.set(url.absoluteString, forKey: Key.baseURL.rawValue)
  }

  public func setModel(_ model: String) {
    defaults.set(model, forKey: Key.model.rawValue)
  }

  public func setAPIKey(_ key: String) throws {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      try secrets.delete(service: Self.secretService, account: Self.textAPIKeyAccount)
    } else {
      try secrets.write(trimmed, service: Self.secretService, account: Self.textAPIKeyAccount)
    }
  }

  public func setContextWindowTokens(_ tokens: Int) {
    defaults.set(String(max(0, tokens)), forKey: Key.contextWindowTokens.rawValue)
  }

  private func resolveTextProvider() -> AgentProviderKind {
    if let raw = environment.trimmedValue("COMPASS_AGENT_TEXT_PROVIDER"),
      let kind = AgentProviderKind(rawValue: raw)
    {
      return kind
    }
    if let raw = defaults.string(forKey: Key.textProvider.rawValue)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      let kind = AgentProviderKind(rawValue: raw)
    {
      return kind
    }
    return AgentRuntimeSettings.defaultTextProvider
  }

  private func resolveBaseURL() -> URL {
    if let raw = environment.trimmedValue("COMPASS_AGENT_BASE_URL"),
      let url = URL(string: raw)
    {
      return url
    }
    if let raw = defaults.string(forKey: Key.baseURL.rawValue)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      let url = URL(string: raw), !raw.isEmpty
    {
      return url
    }
    return AgentRuntimeSettings.defaultBaseURL
  }

  private func resolveAPIKey() -> String {
    if let env = environment.trimmedValue("COMPASS_AGENT_API_KEY") {
      return env
    }
    return (try? secrets.read(service: Self.secretService, account: Self.textAPIKeyAccount)) ?? ""
  }

  private func resolveModel(for provider: AgentProviderKind) -> String {
    if let env = environment.trimmedValue("COMPASS_AGENT_MODEL") {
      return env
    }
    if let stored = defaults.string(forKey: Key.model.rawValue)?
      .trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty
    {
      return stored
    }
    return provider.defaultModel(for: .text) ?? ""
  }
}
