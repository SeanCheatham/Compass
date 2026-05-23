import Foundation

/// Persists AgentRuntimeSettings across launches:
/// - API key in a 0600-perm file under `~/Library/Application Support/Compass/secrets/`.
/// - Everything else (base URL, default model, per-phase model overrides)
///   in UserDefaults.
///
/// The keychain was the original home for the API key, but the macOS
/// keychain APIs interacted badly with both ad-hoc dev signing (cdhash
/// ACL re-prompts) and SwiftUI's `SecureField` paste path. For a
/// single-user developer tool the file storage is the simpler, more
/// reliable option — macOS already gates `~/Library` by user account.
///
/// Resolution per field: UserDefaults / file → environment variable →
/// built-in default. UI edits win and are persisted; env vars exist for
/// scripted setup / CI.
final class AgentSettingsStore: @unchecked Sendable {
  static let secretService = "com.seancheatham.Compass.agent"
  static let secretAccount = "api_key"

  enum Key: String, CaseIterable {
    case baseURL = "compass.agent.baseURL"
    case model = "compass.agent.model"
    case planModel = "compass.agent.model.plan"
    case developModel = "compass.agent.model.dev"
    case reflectModel = "compass.agent.model.reflect"
    case criticModel = "compass.agent.model.critic"
  }

  private let defaults: UserDefaults
  private let secrets: AgentSecretStorage
  private let environment: [String: String]

  init(
    defaults: UserDefaults = .standard,
    secrets: AgentSecretStorage = AgentFileSecretStorage(),
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.environment = environment
  }

  /// Load the merged settings: persisted UI values first, env vars next,
  /// then the AgentRuntimeSettings defaults.
  func load() -> AgentRuntimeSettings {
    let baseURL = resolveBaseURL()
    let apiKey = resolveAPIKey()
    let model =
      resolveString(.model, envKey: "COMPASS_AGENT_MODEL")
      ?? AgentRuntimeSettings.defaultModelIdentifier
    let contextWindowTokens: Int = {
      let raw = environment["COMPASS_AGENT_CONTEXT_WINDOW_TOKENS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if let raw, let value = Int(raw) {
        return max(value, 0)
      }
      return AgentRuntimeSettings.defaultContextWindowTokens
    }()
    return AgentRuntimeSettings(
      baseURL: baseURL,
      apiKey: apiKey,
      model: model,
      planModelOverride: resolveString(.planModel, envKey: "COMPASS_AGENT_MODEL_PLAN"),
      developModelOverride: resolveString(.developModel, envKey: "COMPASS_AGENT_MODEL_DEV"),
      reflectModelOverride: resolveString(.reflectModel, envKey: "COMPASS_AGENT_MODEL_REFLECT"),
      criticModelOverride: resolveString(.criticModel, envKey: "COMPASS_AGENT_MODEL_CRITIC"),
      codemapModelOverride: resolveEnvString("COMPASS_AGENT_MODEL_CODEMAP"),
      contextWindowTokens: contextWindowTokens
    )
  }

  // MARK: - Setters

  func setBaseURL(_ raw: String) {
    setString(.baseURL, raw)
  }

  /// Persist the API key to the secrets file. Empty input deletes the
  /// file, falling back to the env var (if set) on next load.
  func setAPIKey(_ raw: String) throws {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      try secrets.delete(
        service: Self.secretService,
        account: Self.secretAccount
      )
    } else {
      try secrets.write(
        trimmed,
        service: Self.secretService,
        account: Self.secretAccount
      )
    }
  }

  func setDefaultModel(_ raw: String) {
    setString(.model, raw)
  }

  func setPlanModelOverride(_ raw: String) {
    setString(.planModel, raw)
  }

  func setDevelopModelOverride(_ raw: String) {
    setString(.developModel, raw)
  }

  func setReflectModelOverride(_ raw: String) {
    setString(.reflectModel, raw)
  }

  func setCriticModelOverride(_ raw: String) {
    setString(.criticModel, raw)
  }

  // MARK: - Resolution helpers

  private func resolveString(_ key: Key, envKey: String) -> String? {
    if let stored = defaults.string(forKey: key.rawValue)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !stored.isEmpty
    {
      return stored
    }
    return resolveEnvString(envKey)
  }

  private func resolveEnvString(_ envKey: String) -> String? {
    guard
      let env = environment[envKey]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !env.isEmpty
    else { return nil }
    return env
  }

  private func resolveBaseURL() -> URL {
    let raw = resolveString(.baseURL, envKey: "COMPASS_AGENT_BASE_URL")
    if let raw, let url = URL(string: raw) {
      return url
    }
    return AgentRuntimeSettings.defaultBaseURL
  }

  private func resolveAPIKey() -> String {
    if let stored =
      (try? secrets.read(
        service: Self.secretService,
        account: Self.secretAccount
      )) ?? nil
    {
      let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        return trimmed
      }
    }
    if let env = environment["COMPASS_AGENT_API_KEY"]?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !env.isEmpty
    {
      return env
    }
    return ""
  }

  private func setString(_ key: Key, _ raw: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      defaults.removeObject(forKey: key.rawValue)
    } else {
      defaults.set(trimmed, forKey: key.rawValue)
    }
  }
}
