import Foundation

/// Persists AgentRuntimeSettings across launches:
/// - API key in the Keychain (encrypted at rest).
/// - Everything else (base URL, default model, per-phase model overrides)
///   in UserDefaults.
///
/// Resolution per field: UserDefaults / Keychain → environment variable →
/// built-in default. UI edits win and are persisted; env vars exist for
/// scripted setup / CI.
final class AgentSettingsStore: @unchecked Sendable {
    static let keychainService = "com.seancheatham.Compass.agent"
    static let keychainAccount = "api_key"

    enum Key: String, CaseIterable {
        case baseURL = "compass.agent.baseURL"
        case model = "compass.agent.model"
        case planModel = "compass.agent.model.plan"
        case developModel = "compass.agent.model.dev"
        case reflectModel = "compass.agent.model.reflect"
    }

    private let defaults: UserDefaults
    private let keychain: AgentKeychainStorage
    private let environment: [String: String]

    init(
        defaults: UserDefaults = .standard,
        keychain: AgentKeychainStorage = AgentKeychain(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.environment = environment
    }

    /// Load the merged settings: persisted UI values first, env vars next,
    /// then the AgentRuntimeSettings defaults.
    func load() -> AgentRuntimeSettings {
        let baseURL = resolveBaseURL()
        let apiKey = resolveAPIKey()
        let model = resolveString(.model, envKey: "COMPASS_AGENT_MODEL")
            ?? AgentRuntimeSettings.defaultModelIdentifier
        return AgentRuntimeSettings(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            planModelOverride: resolveString(.planModel, envKey: "COMPASS_AGENT_MODEL_PLAN"),
            developModelOverride: resolveString(.developModel, envKey: "COMPASS_AGENT_MODEL_DEV"),
            reflectModelOverride: resolveString(.reflectModel, envKey: "COMPASS_AGENT_MODEL_REFLECT")
        )
    }

    // MARK: - Setters

    func setBaseURL(_ raw: String) {
        setString(.baseURL, raw)
    }

    /// Persist the API key in the Keychain. Empty input deletes the
    /// keychain entry, falling back to the env var (if set) on next load.
    func setAPIKey(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.delete(
                service: Self.keychainService,
                account: Self.keychainAccount
            )
        } else {
            try keychain.write(
                trimmed,
                service: Self.keychainService,
                account: Self.keychainAccount
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

    // MARK: - Resolution helpers

    private func resolveString(_ key: Key, envKey: String) -> String? {
        if let stored = defaults.string(forKey: key.rawValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            return stored
        }
        if let env = environment[envKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        return nil
    }

    private func resolveBaseURL() -> URL {
        let raw = resolveString(.baseURL, envKey: "COMPASS_AGENT_BASE_URL")
        if let raw, let url = URL(string: raw) {
            return url
        }
        return AgentRuntimeSettings.defaultBaseURL
    }

    private func resolveAPIKey() -> String {
        if let stored = try? keychain.read(
            service: Self.keychainService,
            account: Self.keychainAccount
        ) {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let env = environment["COMPASS_AGENT_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
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
