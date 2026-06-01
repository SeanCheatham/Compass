import Foundation

/// A configurable LLM/AI vendor that exposes one or more
/// `AgentCapability`s.
///
/// Each `AgentCapability` is configured independently — the Settings
/// screen lets the user pick a different `AgentProviderKind` for Text,
/// Image, Audio, and Video. A provider declares its default base URL
/// (when network-bound), the set of capabilities it offers, and a
/// suggested default model identifier per capability.
///
/// `appleFoundationModels` is a special case: it runs on-device via
/// Apple's `FoundationModels` framework and therefore has no base URL,
/// no API key, and no per-capability model identifier. It is the
/// out-of-box default for the Text capability so a fresh install can
/// produce something useful without first configuring a third-party
/// account.
enum AgentProviderKind: String, Sendable, CaseIterable, Codable {
  case appleFoundationModels
  case minimaxToken
  case openAI

  var displayName: String {
    switch self {
    case .appleFoundationModels: return "Foundation Models"
    case .minimaxToken: return "MiniMax Token"
    case .openAI: return "OpenAI API"
    }
  }

  /// True when the provider runs over an OpenAI-compatible HTTP
  /// endpoint and therefore needs a base URL + API key. Foundation
  /// Models is the only on-device provider today, so this is `false`
  /// only for `.appleFoundationModels`.
  var requiresCredentials: Bool {
    switch self {
    case .appleFoundationModels: return false
    case .minimaxToken, .openAI: return true
    }
  }

  /// Default base URL for network-bound providers, or `nil` for
  /// on-device ones.
  var defaultBaseURLString: String? {
    switch self {
    case .appleFoundationModels: return nil
    case .minimaxToken: return "https://api.minimax.io/v1"
    case .openAI: return "https://api.openai.com/v1"
    }
  }

  var defaultBaseURL: URL? {
    defaultBaseURLString.flatMap(URL.init(string:))
  }

  var supportedCapabilities: [AgentCapability] {
    switch self {
    case .appleFoundationModels: return [.text]
    case .minimaxToken:
      return [.text, .webSearch, .imageUnderstanding, .image, .audio, .video]
    case .openAI: return [.text]
    }
  }

  func supports(_ capability: AgentCapability) -> Bool {
    supportedCapabilities.contains(capability)
  }

  /// Default model identifier for the given capability, or `nil` if
  /// the provider does not offer it or does not expose a configurable
  /// model name. Foundation Models has no user-pickable identifier —
  /// the OS selects the on-device model — so it returns `nil` for
  /// every capability.
  func defaultModel(for capability: AgentCapability) -> String? {
    guard supports(capability) else { return nil }
    switch (self, capability) {
    case (.minimaxToken, .text): return MiniMaxTextModelVersion.default.modelIdentifier
    case (.minimaxToken, .image): return "image-01"
    case (.minimaxToken, .audio): return "speech-02-hd"
    case (.minimaxToken, .video): return "MiniMax-Hailuo-02"
    case (.openAI, .text): return "gpt-4o"
    default: return nil
    }
  }

  /// Whether Settings should expose a model field for this
  /// provider/capability cell. Some provider-backed tools are fixed
  /// services rather than model-selectable generation endpoints.
  func usesModelField(for capability: AgentCapability) -> Bool {
    guard supports(capability), requiresCredentials else { return false }
    switch (self, capability) {
    case (.minimaxToken, .webSearch), (.minimaxToken, .imageUnderstanding):
      return false
    default:
      return true
    }
  }

  func textContextWindowTokens(for modelIdentifier: String?) -> Int {
    guard self == .minimaxToken else {
      return defaultTextContextWindowTokens
    }
    return MiniMaxTextModelVersion(
      modelIdentifier: modelIdentifier ?? MiniMaxTextModelVersion.default.modelIdentifier
    )?.contextWindowTokens ?? defaultTextContextWindowTokens
  }

  func defaultModel(for phase: AgentPhase, baseModel: String) -> String? {
    let trimmedBase = baseModel.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = trimmedBase.isEmpty ? defaultModel(for: .text) : trimmedBase
    guard self == .minimaxToken else { return fallback }

    switch phase {
    case .plan:
      return MiniMaxTextModelVersion.m3.modelIdentifier
    case .develop, .reflect, .critic:
      return fallback
    }
  }

  /// Built-in default context window (in tokens) for this provider's
  /// text capability. Drives `AgentExecutor`'s auto-compaction
  /// threshold when no more specific model size is selected, and keeps
  /// Compass from constructing requests that would be rejected outright
  /// for exceeding the model's hard ceiling. The
  /// `COMPASS_AGENT_CONTEXT_WINDOW_TOKENS` env var still overrides the
  /// resolved value when set, and `0` disables compaction entirely.
  ///
  /// Numbers reflect each vendor's publicly-documented ceilings:
  /// - Apple Foundation Models is a ~3B-param on-device model with
  ///   a 4096-token rolling window the framework manages internally.
  /// - MiniMax 2.7 defaults to a 200k-token window; MiniMax 3 opts
  ///   into 1M via `textContextWindowTokens(for:)`.
  /// - OpenAI is sized for the GPT-4o family (128k); higher-window
  ///   models can opt in by setting the env var.
  var defaultTextContextWindowTokens: Int {
    switch self {
    case .appleFoundationModels: return 4_096
    case .minimaxToken: return MiniMaxTextModelVersion.default.contextWindowTokens
    case .openAI: return 128_000
    }
  }
}

enum MiniMaxTextModelVersion: String, Sendable, CaseIterable, Codable, Identifiable, Hashable {
  case m27
  case m3

  static let `default`: Self = .m27

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .m27: return "MiniMax 2.7"
    case .m3: return "MiniMax 3"
    }
  }

  var modelIdentifier: String {
    switch self {
    case .m27: return "MiniMax-M2.7"
    case .m3: return "MiniMax-M3"
    }
  }

  var contextWindowTokens: Int {
    switch self {
    case .m27: return 200_000
    case .m3: return 1_000_000
    }
  }

  init?(modelIdentifier: String) {
    let normalized = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    switch normalized {
    case "minimax-m2.7", "minimax-2.7", "m2.7", "2.7":
      self = .m27
    case "minimax-m3", "minimax-3", "m3", "3":
      self = .m3
    default:
      return nil
    }
  }
}

/// A class of work a provider can perform. Each capability is
/// configured independently in Settings.
enum AgentCapability: String, Sendable, CaseIterable, Codable {
  case text
  case webSearch
  case imageUnderstanding
  case image
  case audio
  case video

  var displayName: String {
    switch self {
    case .text: return "Text"
    case .webSearch: return "Web Search"
    case .imageUnderstanding: return "Image Understanding"
    case .image: return "Image"
    case .audio: return "Audio"
    case .video: return "Video"
    }
  }

  var systemImageName: String {
    switch self {
    case .text: return "text.bubble"
    case .webSearch: return "globe"
    case .imageUnderstanding: return "eye"
    case .image: return "photo"
    case .audio: return "waveform"
    case .video: return "film"
    }
  }

  /// True when this capability *must* be assigned for Compass to
  /// run an agent loop. Text gates every run; media capabilities
  /// are optional and can be left unassigned ("None").
  var isRequired: Bool {
    self == .text
  }

  /// Providers (in display order) the user can pick from for this
  /// capability — every kind that declares this capability in
  /// `supportedCapabilities`.
  var availableProviders: [AgentProviderKind] {
    AgentProviderKind.allCases.filter { $0.supports(self) }
  }
}
