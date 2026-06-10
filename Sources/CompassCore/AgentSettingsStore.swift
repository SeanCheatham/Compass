import Foundation

final class AgentSettingsStore: @unchecked Sendable {
  enum Key: Hashable, CaseIterable {
    case contextWindowTokens

    var rawValue: String {
      switch self {
      case .contextWindowTokens:
        return "compass.mlx.contextWindowTokens"
      }
    }

    static var allCases: [Key] { [.contextWindowTokens] }
  }

  private let defaults: UserDefaults
  private let environment: [String: String]

  init(
    defaults: UserDefaults = .standard,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.defaults = defaults
    self.environment = environment
  }

  func load() -> AgentRuntimeSettings {
    let contextWindow =
      environment.trimmedValue("COMPASS_AGENT_CONTEXT_WINDOW_TOKENS").flatMap(Int.init)
      ?? defaults.string(forKey: Key.contextWindowTokens.rawValue)
        .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
      ?? AgentRuntimeSettings.defaultContextWindowTokens
    return AgentRuntimeSettings(
      contextWindowTokens: contextWindow
    )
  }

  func setContextWindowTokens(_ tokens: Int) {
    defaults.set(String(max(1, tokens)), forKey: Key.contextWindowTokens.rawValue)
  }
}
