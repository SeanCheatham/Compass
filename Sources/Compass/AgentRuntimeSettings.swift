import Foundation

enum AgentPhase: String, Sendable, CaseIterable {
  case plan
  case develop
  case critic
}

struct AgentRuntimeSettings: Equatable, Sendable {
  static let defaultTextProvider: AgentProviderKind = .openAICompatible
  static let defaultContextWindowTokens =
    AgentProviderKind.openAICompatible.defaultTextContextWindowTokens
  static let defaultBaseURLString =
    AgentProviderKind.openAICompatible.defaultBaseURLString ?? "https://api.moonshot.ai/v1"
  static var defaultBaseURL: URL {
    URL(string: defaultBaseURLString) ?? URL(fileURLWithPath: "/")
  }

  var textProvider: AgentProviderKind
  var baseURL: URL
  var apiKey: String
  var model: String
  var contextWindowTokens: Int

  init(
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

  static func defaultFromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    AgentSettingsStore(environment: environment).load()
  }

  var trimmedAPIKey: String {
    apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var trimmedModel: String {
    model.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var hasCloudCredentials: Bool {
    !trimmedAPIKey.isEmpty && !trimmedModel.isEmpty && !baseURL.absoluteString.isEmpty
  }

  var isCloudConfigured: Bool {
    textProvider == .openAICompatible && hasCloudCredentials
  }

  var isLocalAssistReady: Bool {
    LocalModelCatalog.isBlessedModelReady()
  }

  var codemapModel: String {
    if isLocalAssistReady {
      return LocalModelCatalog.blessedModelID
    }
    return model(for: .plan)
  }

  var isTextCapabilityReady: Bool {
    isTextCapabilityRunnable(localModelReady: LocalModelCatalog.isBlessedModelReady())
  }

  func isTextCapabilityRunnable(localModelReady: Bool) -> Bool {
    switch textProvider {
    case .openAICompatible:
      return hasCloudCredentials
    case .mlx:
      return localModelReady
    }
  }

  func model(for phase: AgentPhase, sidebarOverride: String = "") -> String {
    let override = sidebarOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    if !override.isEmpty { return override }
    switch textProvider {
    case .openAICompatible:
      return trimmedModel
    case .mlx:
      return LocalModelCatalog.blessedModelID
    }
  }

  func cloudEndpointDisplay() -> String {
    baseURL.absoluteString
  }
}

extension Dictionary where Key == String, Value == String {
  func trimmedValue(_ key: String) -> String? {
    let trimmed = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}
