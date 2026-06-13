import Foundation

package final class AgentSettingsStore: @unchecked Sendable {
  package enum Key: Hashable, CaseIterable {
    case contextWindowTokens

    package var rawValue: String {
      switch self {
      case .contextWindowTokens:
        return "compass.mlx.contextWindowTokens"
      }
    }

    package var storageKey: String { rawValue }

    package static var allCases: [Key] { [.contextWindowTokens] }
  }

  private let defaults: UserDefaults
  private let environment: [String: String]

  package init(
    defaults: UserDefaults = .standard,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.defaults = defaults
    self.environment = environment
  }

  package func load() -> AgentRuntimeSettings {
    let contextWindow =
      environment.trimmedValue("COMPASS_AGENT_CONTEXT_WINDOW_TOKENS").flatMap(Int.init)
      ?? defaults.string(forKey: Key.contextWindowTokens.rawValue)
        .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
      ?? AgentRuntimeSettings.defaultContextWindowTokens
    return AgentRuntimeSettings(
      contextWindowTokens: contextWindow
    )
  }

  package func setContextWindowTokens(_ tokens: Int) {
    defaults.set(String(max(1, tokens)), forKey: Key.contextWindowTokens.rawValue)
  }
}
