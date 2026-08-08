import Foundation

public enum AgentPhase: String, Sendable, CaseIterable {
  case plan
  case develop
  case critic
  case requirementsAudit = "requirements_audit"
  case health
}

public struct AgentRuntimeSettings: Equatable, Sendable {
  public static let defaultTextProvider: AgentProviderKind = .openAICompatible
  public static let defaultContextWindowTokens =
    AgentProviderKind.openAICompatible.defaultTextContextWindowTokens
  public static let defaultBaseURLString =
    AgentProviderKind.openAICompatible.defaultBaseURLString ?? "https://api.kimi.com/coding/v1"
  public static var defaultBaseURL: URL {
    URL(string: defaultBaseURLString) ?? URL(fileURLWithPath: "/")
  }

  public var textProvider: AgentProviderKind
  public var baseURL: URL
  public var apiKey: String
  public var model: String
  public var contextWindowTokens: Int

  public init(
    textProvider: AgentProviderKind = AgentRuntimeSettings.defaultTextProvider,
    baseURL: URL = AgentRuntimeSettings.defaultBaseURL,
    apiKey: String = "",
    model: String = "",
    contextWindowTokens: Int = AgentRuntimeSettings.defaultContextWindowTokens
  ) {
    self.textProvider = textProvider
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.model = model
    self.contextWindowTokens = max(0, contextWindowTokens)
  }

  public static func defaultFromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    AgentSettingsStore(environment: environment).load()
  }

  public var trimmedAPIKey: String {
    apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var trimmedModel: String {
    model.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var hasCloudCredentials: Bool {
    !trimmedAPIKey.isEmpty && !trimmedModel.isEmpty && !baseURL.absoluteString.isEmpty
  }

  public var isCloudConfigured: Bool {
    textProvider == .openAICompatible && hasCloudCredentials
  }

  public var isLocalAssistReady: Bool {
    LocalModelCatalog.isBlessedModelReady()
  }

  public var codemapModel: String {
    if isLocalAssistReady {
      return LocalModelCatalog.blessedModelID
    }
    return model(for: .plan)
  }

  public var isTextCapabilityReady: Bool {
    isTextCapabilityRunnable(localModelReady: LocalModelCatalog.isBlessedModelReady())
  }

  public func isTextCapabilityRunnable(localModelReady: Bool) -> Bool {
    switch textProvider {
    case .openAICompatible:
      return hasCloudCredentials
    case .mlx:
      return localModelReady
    }
  }

  public func model(for phase: AgentPhase, sidebarOverride: String = "") -> String {
    let override = sidebarOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    if !override.isEmpty { return override }
    switch textProvider {
    case .openAICompatible:
      return trimmedModel
    case .mlx:
      return LocalModelCatalog.blessedModelID
    }
  }

  public func cloudEndpointDisplay() -> String {
    baseURL.absoluteString
  }
}

extension Dictionary where Key == String, Value == String {
  public func trimmedValue(_ key: String) -> String? {
    let trimmed = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}
