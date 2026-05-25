import Foundation

/// Persists `AgentRuntimeSettings` across launches.
///
/// Configuration is namespaced per `(AgentCapability, AgentProviderKind)`
/// so users can mix and match — e.g. Text → OpenAI API, Image →
/// MiniMax Token, Audio/Video → MiniMax Token — while each
/// (capability, provider) cell keeps its own base URL / API key /
/// model independently of the others.
///
/// Storage layout:
///
/// - **UserDefaults**: `compass.capability.<capability>.provider` for
///   the selected provider kind, then `compass.capability.<capability>.
///   <provider>.<field>` for the cell's base URL, model, and (for
///   text only) per-phase overrides. See `AgentSettingsStore.Key`.
/// - **Secrets file**: each (capability, provider) cell's API key lives
///   at `~/Library/Application Support/Compass/secrets/<service>/
///   api_key.<capability>.<provider>` with `0600` POSIX perms.
///
/// Foundation Models is on-device and requires no credentials, so the
/// `.appleFoundationModels` cell stores nothing — selecting it for a
/// capability simply records the provider choice.
///
/// Resolution per field for an active assignment: persisted UI / file
/// → environment variable → legacy unprefixed key (Text + MiniMax
/// Token only — preserving pre-provider-abstraction settings) →
/// built-in default. UI edits win and are persisted; env vars exist
/// for scripted setup / CI.
final class AgentSettingsStore: @unchecked Sendable {
  static let secretService = "com.seancheatham.Compass.agent"

  /// All UserDefaults keys this store reads or writes. Used in tests
  /// to scrub state between cases. Includes:
  ///
  /// - Current per-capability keys (parameterised by `AgentCapability`
  ///   and, where credentials apply, `AgentProviderKind`).
  /// - First-generation per-provider keys (the namespacing scheme that
  ///   shipped briefly before this rework) — still read as a fallback
  ///   so users upgrading mid-iteration keep their settings.
  /// - Original unprefixed keys (`compass.agent.*`) — still read as a
  ///   fallback for the Text + MiniMax Token cell so users predating
  ///   the abstraction also keep their settings.
  enum Key: Hashable, CaseIterable {
    case capabilityProvider(AgentCapability)
    case cellBaseURL(AgentCapability, AgentProviderKind)
    case cellModel(AgentCapability, AgentProviderKind)
    case cellTextPhaseOverride(AgentProviderKind, AgentPhase)
    case legacyProviderBaseURL(AgentProviderKind)
    case legacyProviderTextModel(AgentProviderKind)
    case legacyProviderTextPhaseOverride(AgentProviderKind, AgentPhase)
    case legacyProviderImageModel(AgentProviderKind)
    case legacyProviderAudioModel(AgentProviderKind)
    case legacyProviderVideoModel(AgentProviderKind)
    case legacyProviderSelected
    case legacyBaseURL
    case legacyModel
    case legacyPlanModel
    case legacyDevelopModel
    case legacyReflectModel
    case legacyCriticModel

    var rawValue: String {
      switch self {
      case .capabilityProvider(let capability):
        return "compass.capability.\(capability.rawValue).provider"
      case .cellBaseURL(let capability, let provider):
        return "compass.capability.\(capability.rawValue).\(provider.rawValue).baseURL"
      case .cellModel(let capability, let provider):
        return "compass.capability.\(capability.rawValue).\(provider.rawValue).model"
      case .cellTextPhaseOverride(let provider, let phase):
        return "compass.capability.text.\(provider.rawValue).phase.\(phase.rawValue)"
      case .legacyProviderBaseURL(let provider):
        return "compass.provider.\(provider.rawValue).baseURL"
      case .legacyProviderTextModel(let provider):
        return "compass.provider.\(provider.rawValue).text.model"
      case .legacyProviderTextPhaseOverride(let provider, let phase):
        return "compass.provider.\(provider.rawValue).text.model.\(phase.rawValue)"
      case .legacyProviderImageModel(let provider):
        return "compass.provider.\(provider.rawValue).image.model"
      case .legacyProviderAudioModel(let provider):
        return "compass.provider.\(provider.rawValue).audio.model"
      case .legacyProviderVideoModel(let provider):
        return "compass.provider.\(provider.rawValue).video.model"
      case .legacyProviderSelected:
        return "compass.provider.selected"
      case .legacyBaseURL:
        return "compass.agent.baseURL"
      case .legacyModel:
        return "compass.agent.model"
      case .legacyPlanModel:
        return "compass.agent.model.plan"
      case .legacyDevelopModel:
        return "compass.agent.model.dev"
      case .legacyReflectModel:
        return "compass.agent.model.reflect"
      case .legacyCriticModel:
        return "compass.agent.model.critic"
      }
    }

    static var allCases: [Key] {
      var cases: [Key] = []
      for capability in AgentCapability.allCases {
        cases.append(.capabilityProvider(capability))
        for provider in capability.availableProviders where provider.requiresCredentials {
          cases.append(.cellBaseURL(capability, provider))
          cases.append(.cellModel(capability, provider))
        }
      }
      for provider in AgentCapability.text.availableProviders where provider.requiresCredentials {
        for phase in AgentPhase.allCases {
          cases.append(.cellTextPhaseOverride(provider, phase))
        }
      }
      for provider in AgentProviderKind.allCases {
        cases.append(.legacyProviderBaseURL(provider))
        cases.append(.legacyProviderTextModel(provider))
        for phase in AgentPhase.allCases {
          cases.append(.legacyProviderTextPhaseOverride(provider, phase))
        }
        cases.append(.legacyProviderImageModel(provider))
        cases.append(.legacyProviderAudioModel(provider))
        cases.append(.legacyProviderVideoModel(provider))
      }
      cases.append(.legacyProviderSelected)
      cases.append(contentsOf: [
        .legacyBaseURL, .legacyModel, .legacyPlanModel,
        .legacyDevelopModel, .legacyReflectModel, .legacyCriticModel,
      ])
      return cases
    }
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

  // MARK: - Per-capability provider selection

  /// The provider chosen for `capability`. Returns the built-in
  /// default for capabilities the user has not configured yet — text
  /// defaults to Foundation Models, media capabilities to `nil` (None).
  func selectedProvider(for capability: AgentCapability) -> AgentProviderKind? {
    if let raw = defaults.string(forKey: Key.capabilityProvider(capability).rawValue)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    {
      if raw == Self.noneProviderSentinel { return nil }
      if let kind = AgentProviderKind(rawValue: raw), kind.supports(capability) {
        return kind
      }
    }
    // No persisted choice yet — fall back to the legacy
    // "selectedProvider" key (the brief intermediate scheme) for text,
    // since v1 stored exactly one provider that meant "text".
    if capability == .text,
      let legacyRaw = defaults.string(forKey: Key.legacyProviderSelected.rawValue)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      let kind = AgentProviderKind(rawValue: legacyRaw),
      kind.supports(.text)
    {
      return kind
    }
    return capability.isRequired ? AgentRuntimeSettings.defaultTextProvider : nil
  }

  func setSelectedProvider(_ kind: AgentProviderKind?, for capability: AgentCapability) {
    let key = Key.capabilityProvider(capability).rawValue
    if let kind, kind.supports(capability) {
      defaults.set(kind.rawValue, forKey: key)
    } else {
      // Required capabilities can't be set to None — record the
      // sentinel for optional ones, clear the entry for required
      // ones (which falls back to the built-in default on next read).
      if capability.isRequired {
        defaults.removeObject(forKey: key)
      } else {
        defaults.set(Self.noneProviderSentinel, forKey: key)
      }
    }
  }

  /// Sentinel string written to the per-capability provider key when
  /// the user explicitly selects "None" for an optional capability.
  /// Distinguishes "user said no" from "never configured".
  static let noneProviderSentinel = "__none__"

  // MARK: - Load

  /// Load the merged settings: persisted UI values first, env vars
  /// next, then the built-in defaults. The returned struct's text
  /// fields reflect the Text capability's currently-selected
  /// provider; media fields reflect each capability's assignment
  /// (or `nil` if unassigned).
  func load() -> AgentRuntimeSettings {
    let textProvider =
      selectedProvider(for: .text) ?? AgentRuntimeSettings.defaultTextProvider
    let baseURL = resolveBaseURL(for: .text, provider: textProvider)
    let apiKey = resolveAPIKey(for: .text, provider: textProvider)
    let textModel: String
    if textProvider.requiresCredentials {
      textModel =
        resolveModel(for: .text, provider: textProvider)
        ?? textProvider.defaultModel(for: .text)
        ?? ""
    } else {
      textModel = ""
    }
    let contextWindowTokens: Int = {
      let raw = environment["COMPASS_AGENT_CONTEXT_WINDOW_TOKENS"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if let raw, let value = Int(raw) {
        return max(value, 0)
      }
      return AgentRuntimeSettings.defaultContextWindowTokens
    }()
    return AgentRuntimeSettings(
      textProvider: textProvider,
      baseURL: baseURL,
      apiKey: apiKey,
      model: textModel,
      planModelOverride: resolvePhaseOverride(.plan, provider: textProvider),
      developModelOverride: resolvePhaseOverride(.develop, provider: textProvider),
      reflectModelOverride: resolvePhaseOverride(.reflect, provider: textProvider),
      criticModelOverride: resolvePhaseOverride(.critic, provider: textProvider),
      codemapModelOverride: resolveEnvString("COMPASS_AGENT_MODEL_CODEMAP"),
      contextWindowTokens: contextWindowTokens,
      imageAssignment: loadMediaAssignment(for: .image),
      audioAssignment: loadMediaAssignment(for: .audio),
      videoAssignment: loadMediaAssignment(for: .video)
    )
  }

  private func loadMediaAssignment(for capability: AgentCapability) -> MediaAssignment? {
    guard let provider = selectedProvider(for: capability),
      provider.requiresCredentials,
      let defaultBaseURL = provider.defaultBaseURL
    else {
      return nil
    }
    let baseURL = resolveBaseURL(for: capability, provider: provider)
    let apiKey = resolveAPIKey(for: capability, provider: provider)
    let model =
      resolveModel(for: capability, provider: provider)
      ?? provider.defaultModel(for: capability)
      ?? ""
    return MediaAssignment(
      provider: provider,
      baseURL: baseURL == AgentRuntimeSettings.defaultBaseURL ? defaultBaseURL : baseURL,
      apiKey: apiKey,
      model: model
    )
  }

  // MARK: - Cell setters

  func setCellBaseURL(
    _ raw: String, capability: AgentCapability, provider: AgentProviderKind
  ) {
    guard provider.requiresCredentials else { return }
    setString(.cellBaseURL(capability, provider), raw)
  }

  /// Persist the API key for `(capability, provider)`. Empty input
  /// removes the file; on the next load that cell falls back to env
  /// vars (text only) and then the empty default.
  func setCellAPIKey(
    _ raw: String, capability: AgentCapability, provider: AgentProviderKind
  ) throws {
    guard provider.requiresCredentials else { return }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let account = Self.secretAccount(for: capability, provider: provider)
    if trimmed.isEmpty {
      try secrets.delete(service: Self.secretService, account: account)
    } else {
      try secrets.write(trimmed, service: Self.secretService, account: account)
    }
  }

  func setCellModel(
    _ raw: String, capability: AgentCapability, provider: AgentProviderKind
  ) {
    guard provider.requiresCredentials else { return }
    setString(.cellModel(capability, provider), raw)
  }

  func setTextPhaseOverride(
    _ phase: AgentPhase, _ raw: String, provider: AgentProviderKind
  ) {
    guard provider.requiresCredentials else { return }
    setString(.cellTextPhaseOverride(provider, phase), raw)
  }

  // MARK: - Secret accounts

  /// File name under `secretService/` that holds the API key for
  /// `(capability, provider)`. Each cell gets its own file so a key
  /// the user pastes into Text + OpenAI doesn't leak into Image +
  /// MiniMax.
  static func secretAccount(
    for capability: AgentCapability, provider: AgentProviderKind
  ) -> String {
    "api_key.\(capability.rawValue).\(provider.rawValue)"
  }

  /// Per-provider secret account from the brief intermediate scheme
  /// (one-provider-at-a-time). Used only as a legacy fallback for
  /// the Text capability.
  static func legacyProviderSecretAccount(for provider: AgentProviderKind) -> String {
    "api_key.\(provider.rawValue)"
  }

  /// Original account name for the API key, used only as a legacy
  /// fallback for the Text + MiniMax Token cell so installs predating
  /// the provider abstraction keep their key.
  static let legacySecretAccount = "api_key"

  // MARK: - Resolution helpers

  private func resolveBaseURL(
    for capability: AgentCapability, provider: AgentProviderKind
  ) -> URL {
    guard provider.requiresCredentials else {
      return AgentRuntimeSettings.defaultBaseURL
    }
    if let stored = trimmedDefault(for: .cellBaseURL(capability, provider)),
      let url = URL(string: stored)
    {
      return url
    }
    if let legacy = legacyBaseURLFallback(for: capability, provider: provider) {
      return legacy
    }
    if capability == .text,
      let env = resolveEnvString("COMPASS_AGENT_BASE_URL"),
      let url = URL(string: env)
    {
      return url
    }
    return provider.defaultBaseURL ?? AgentRuntimeSettings.defaultBaseURL
  }

  private func legacyBaseURLFallback(
    for capability: AgentCapability, provider: AgentProviderKind
  ) -> URL? {
    // v1 scheme: compass.provider.<kind>.baseURL (one provider, applied to all)
    if let stored = trimmedDefault(for: .legacyProviderBaseURL(provider)),
      let url = URL(string: stored)
    {
      return url
    }
    // v0 scheme: compass.agent.baseURL (only meaningful for Text + MiniMax Token)
    if capability == .text, provider == .minimaxToken,
      let legacy = trimmedDefault(for: .legacyBaseURL),
      let url = URL(string: legacy)
    {
      return url
    }
    return nil
  }

  private func resolveAPIKey(
    for capability: AgentCapability, provider: AgentProviderKind
  ) -> String {
    guard provider.requiresCredentials else { return "" }
    if let stored =
      (try? secrets.read(
        service: Self.secretService,
        account: Self.secretAccount(for: capability, provider: provider)
      )) ?? nil,
      !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return stored.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // v1 fallback: per-provider account.
    if let legacy =
      (try? secrets.read(
        service: Self.secretService,
        account: Self.legacyProviderSecretAccount(for: provider)
      )) ?? nil,
      !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return legacy.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // v0 fallback: unprefixed account, applied only to Text + MiniMax.
    if capability == .text, provider == .minimaxToken,
      let legacy =
        (try? secrets.read(
          service: Self.secretService,
          account: Self.legacySecretAccount
        )) ?? nil,
      !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return legacy.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if capability == .text, let env = resolveEnvString("COMPASS_AGENT_API_KEY") {
      return env
    }
    return ""
  }

  private func resolveModel(
    for capability: AgentCapability, provider: AgentProviderKind
  ) -> String? {
    guard provider.requiresCredentials else { return nil }
    if let stored = trimmedDefault(for: .cellModel(capability, provider)) {
      return stored
    }
    let legacyKey: Key
    switch capability {
    case .text: legacyKey = .legacyProviderTextModel(provider)
    case .image: legacyKey = .legacyProviderImageModel(provider)
    case .audio: legacyKey = .legacyProviderAudioModel(provider)
    case .video: legacyKey = .legacyProviderVideoModel(provider)
    }
    if let legacy = trimmedDefault(for: legacyKey) {
      return legacy
    }
    if capability == .text, provider == .minimaxToken,
      let v0 = trimmedDefault(for: .legacyModel)
    {
      return v0
    }
    if capability == .text {
      return resolveEnvString("COMPASS_AGENT_MODEL")
    }
    return nil
  }

  private func resolvePhaseOverride(
    _ phase: AgentPhase, provider: AgentProviderKind
  ) -> String? {
    guard provider.requiresCredentials else { return nil }
    if let stored = trimmedDefault(for: .cellTextPhaseOverride(provider, phase)) {
      return stored
    }
    if let legacy = trimmedDefault(for: .legacyProviderTextPhaseOverride(provider, phase)) {
      return legacy
    }
    if provider == .minimaxToken {
      let v0Key: Key
      switch phase {
      case .plan: v0Key = .legacyPlanModel
      case .develop: v0Key = .legacyDevelopModel
      case .reflect: v0Key = .legacyReflectModel
      case .critic: v0Key = .legacyCriticModel
      }
      if let v0 = trimmedDefault(for: v0Key) {
        return v0
      }
    }
    return resolveEnvString(envKey(for: phase))
  }

  private func envKey(for phase: AgentPhase) -> String {
    switch phase {
    case .plan: return "COMPASS_AGENT_MODEL_PLAN"
    case .develop: return "COMPASS_AGENT_MODEL_DEV"
    case .reflect: return "COMPASS_AGENT_MODEL_REFLECT"
    case .critic: return "COMPASS_AGENT_MODEL_CRITIC"
    }
  }

  private func resolveEnvString(_ envKey: String) -> String? {
    guard
      let env = environment[envKey]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !env.isEmpty
    else { return nil }
    return env
  }

  private func trimmedDefault(for key: Key) -> String? {
    guard
      let raw = defaults.string(forKey: key.rawValue)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else { return nil }
    return raw
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
