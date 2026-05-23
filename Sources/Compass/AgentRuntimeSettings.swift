import Foundation

enum AgentPhase: String, Sendable, CaseIterable {
  case plan
  case develop
  case reflect
}

/// Runtime configuration for the OpenAI-compatible agent endpoint.
///
/// Compass talks to an OpenAI-compatible chat completions endpoint (default:
/// MiniMax at `https://api.minimax.io/v1`). The base URL, API key, and model
/// can be set per-process via env vars, and the model can additionally be
/// overridden per phase or by the live sidebar field.
struct AgentRuntimeSettings: Equatable, Sendable {
  static let defaultBaseURLString = "https://api.minimax.io/v1"
  static let defaultModelIdentifier = "MiniMax-M2.7"

  var baseURL: URL
  var apiKey: String
  var model: String
  var planModelOverride: String?
  var developModelOverride: String?
  var reflectModelOverride: String?

  init(
    baseURL: URL = AgentRuntimeSettings.defaultBaseURL,
    apiKey: String = "",
    model: String = AgentRuntimeSettings.defaultModelIdentifier,
    planModelOverride: String? = nil,
    developModelOverride: String? = nil,
    reflectModelOverride: String? = nil
  ) {
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.model = model
    self.planModelOverride = planModelOverride
    self.developModelOverride = developModelOverride
    self.reflectModelOverride = reflectModelOverride
  }

  static var defaultBaseURL: URL {
    // String literal validated at first call; safe to force-unwrap.
    URL(string: defaultBaseURLString)!
  }

  /// Build settings from the given environment dictionary (defaults to the
  /// process environment). Empty / whitespace-only values are treated as
  /// unset so a developer can `unset COMPASS_AGENT_MODEL_PLAN` by exporting
  /// it as `""`.
  static func defaultFromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let baseURL =
      environment.compassAgentTrimmed("COMPASS_AGENT_BASE_URL")
      .flatMap(URL.init(string:)) ?? defaultBaseURL
    return Self(
      baseURL: baseURL,
      apiKey: environment.compassAgentTrimmed("COMPASS_AGENT_API_KEY") ?? "",
      model: environment.compassAgentTrimmed("COMPASS_AGENT_MODEL") ?? defaultModelIdentifier,
      planModelOverride: environment.compassAgentTrimmed("COMPASS_AGENT_MODEL_PLAN"),
      developModelOverride: environment.compassAgentTrimmed("COMPASS_AGENT_MODEL_DEV"),
      reflectModelOverride: environment.compassAgentTrimmed("COMPASS_AGENT_MODEL_REFLECT")
    )
  }

  /// Resolve the model identifier for a given phase.
  ///
  /// Resolution order: sidebar override → phase-specific env override →
  /// default model.
  func model(for phase: AgentPhase, sidebarOverride: String = "") -> String {
    let sidebar = sidebarOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    if !sidebar.isEmpty { return sidebar }
    let phaseOverride: String?
    switch phase {
    case .plan: phaseOverride = planModelOverride
    case .develop: phaseOverride = developModelOverride
    case .reflect: phaseOverride = reflectModelOverride
    }
    return phaseOverride ?? model
  }
}

extension Dictionary where Key == String, Value == String {
  fileprivate func compassAgentTrimmed(_ key: String) -> String? {
    guard let raw = self[key] else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
