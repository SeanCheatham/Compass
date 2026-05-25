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
    case .minimaxToken: return [.text, .image, .audio, .video]
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
    case (.minimaxToken, .text): return "MiniMax-M2.7"
    case (.minimaxToken, .image): return "image-01"
    case (.minimaxToken, .audio): return "speech-02-hd"
    case (.minimaxToken, .video): return "MiniMax-Hailuo-02"
    case (.openAI, .text): return "gpt-4o"
    default: return nil
    }
  }

  /// Built-in maximum context window (in tokens) for this provider's
  /// text capability. Drives `AgentExecutor`'s auto-compaction
  /// threshold (compaction triggers at ~75% of this value) and keeps
  /// Compass from constructing requests that would be rejected
  /// outright for exceeding the model's hard ceiling. The
  /// `COMPASS_AGENT_CONTEXT_WINDOW_TOKENS` env var still overrides
  /// the resolved value when set, and `0` disables compaction
  /// entirely.
  ///
  /// Numbers reflect each vendor's publicly-documented ceilings:
  /// - Apple Foundation Models is a ~3B-param on-device model with
  ///   a 4096-token rolling window the framework manages internally.
  /// - MiniMax M-series exposes a 200k-token window.
  /// - OpenAI is sized for the GPT-4o family (128k); higher-window
  ///   models can opt in by setting the env var.
  var defaultTextContextWindowTokens: Int {
    switch self {
    case .appleFoundationModels: return 4_096
    case .minimaxToken: return 200_000
    case .openAI: return 128_000
    }
  }
}

/// A class of work a provider can perform. Each capability is
/// configured independently in Settings.
enum AgentCapability: String, Sendable, CaseIterable, Codable {
  case text
  case image
  case audio
  case video

  var displayName: String {
    switch self {
    case .text: return "Text"
    case .image: return "Image"
    case .audio: return "Audio"
    case .video: return "Video"
    }
  }

  var systemImageName: String {
    switch self {
    case .text: return "text.bubble"
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
