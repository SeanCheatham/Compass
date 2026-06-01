import Foundation

enum AgentPhase: String, Sendable, CaseIterable {
  case plan
  case develop
  case reflect
  case critic
}

/// Configuration for an optional network-bound capability the user has
/// assigned to a provider. Stored alongside `AgentRuntimeSettings` so
/// tool-execution paths can read each capability's chosen vendor,
/// credentials, endpoint, and optional model.
///
/// Foundation Models is text-only, so there is no on-device variant of
/// this struct; `CapabilityAssignment.provider` is always a network
/// provider.
struct CapabilityAssignment: Equatable, Sendable {
  var provider: AgentProviderKind
  var baseURL: URL
  var apiKey: String
  var model: String
}

/// Compatibility alias for the existing generated-media code. New
/// optional services should use `CapabilityAssignment` directly.
typealias MediaAssignment = CapabilityAssignment

/// Runtime configuration for the active agent run.
///
/// Compass talks to Apple's on-device `FoundationModels` framework
/// *or* an OpenAI-compatible HTTP endpoint for text, and (when
/// configured) separately to network providers for optional tools
/// like web search, image understanding, and media generation. Each
/// capability picks its own provider in Settings; this struct flattens
/// the resolved assignments into a shape `AgentExecutor` and tool
/// adapters can consume.
///
/// The text-execution path stays the primary surface — its fields
/// (`textProvider`, `baseURL`, `apiKey`, `model`, the per-phase
/// overrides, `contextWindowTokens`) keep their previous names so
/// most call sites don't need to change. Media assignments live in
/// optional siblings; `nil` means the user has selected "None" for
/// that capability.
///
/// Resolution order per field is: persisted UI → environment
/// variable → built-in default. Env vars exist for scripted setup
/// / CI; see `AgentSettingsStore` for the precise key names.
struct AgentRuntimeSettings: Equatable, Sendable {
  /// Generic fallback context window used by the synthetic init
  /// default (tests and ad-hoc constructions that don't go through
  /// `AgentSettingsStore.load()`). Real runs resolve the value from
  /// the selected Text provider and model (see `AgentProviderKind`), so
  /// each provider/model's actual ceiling — 4096 for Foundation
  /// Models, 200k or 1M for MiniMax, 128k for OpenAI — drives
  /// auto-compaction.
  /// `COMPASS_AGENT_CONTEXT_WINDOW_TOKENS` overrides whichever value
  /// the resolver picked; `0` disables auto-compaction entirely.
  static let defaultContextWindowTokens =
    AgentProviderKind.minimaxToken.defaultTextContextWindowTokens

  /// Out-of-the-box text provider. Foundation Models runs on-device
  /// with no credentials and is available on every Apple Silicon Mac
  /// that meets Compass's deployment target.
  static let defaultTextProvider: AgentProviderKind = .appleFoundationModels

  static var defaultBaseURLString: String {
    AgentProviderKind.minimaxToken.defaultBaseURLString ?? ""
  }

  static var defaultBaseURL: URL {
    AgentProviderKind.minimaxToken.defaultBaseURL ?? URL(fileURLWithPath: "/")
  }

  static var defaultModelIdentifier: String {
    AgentProviderKind.minimaxToken.defaultModel(for: .text) ?? ""
  }

  /// Provider chosen for the Text capability. `.appleFoundationModels`
  /// dispatches to the on-device backend and ignores `baseURL`/
  /// `apiKey`/`model`; everything else dispatches to an
  /// OpenAI-compatible HTTP endpoint and uses those fields.
  var textProvider: AgentProviderKind
  var baseURL: URL
  var apiKey: String
  var model: String
  var planModelOverride: String?
  var developModelOverride: String?
  var reflectModelOverride: String?
  /// Optional dedicated model identifier for the adversarial Critic
  /// pass that gates Develop's output. Falls back to `model` when nil.
  /// Configured via `COMPASS_AGENT_MODEL_CRITIC`; intended to be set to
  /// a stronger / different model from Develop so the critique provides
  /// independent signal.
  var criticModelOverride: String?
  /// Optional dedicated model identifier for the per-file codemap
  /// summarization pass. Falls back to `model` when nil. Configured via
  /// `COMPASS_AGENT_MODEL_CODEMAP`; intended for a cheap small model
  /// (Haiku-tier or equivalent) since the pass fans out across ~hundreds
  /// of files on first build.
  var codemapModelOverride: String?
  var contextWindowTokens: Int

  /// Optional assignments for non-text capabilities. `nil` means the
  /// user has selected "None" for that capability — Compass will not
  /// expose the corresponding tool to the agent.
  var webSearchAssignment: CapabilityAssignment?
  var imageUnderstandingAssignment: CapabilityAssignment?
  var imageAssignment: MediaAssignment?
  var audioAssignment: MediaAssignment?
  var videoAssignment: MediaAssignment?

  init(
    textProvider: AgentProviderKind = AgentRuntimeSettings.defaultTextProvider,
    baseURL: URL = AgentRuntimeSettings.defaultBaseURL,
    apiKey: String = "",
    model: String = "",
    planModelOverride: String? = nil,
    developModelOverride: String? = nil,
    reflectModelOverride: String? = nil,
    criticModelOverride: String? = nil,
    codemapModelOverride: String? = nil,
    contextWindowTokens: Int = AgentRuntimeSettings.defaultContextWindowTokens,
    webSearchAssignment: CapabilityAssignment? = nil,
    imageUnderstandingAssignment: CapabilityAssignment? = nil,
    imageAssignment: MediaAssignment? = nil,
    audioAssignment: MediaAssignment? = nil,
    videoAssignment: MediaAssignment? = nil
  ) {
    self.textProvider = textProvider
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.model = model
    self.planModelOverride = planModelOverride
    self.developModelOverride = developModelOverride
    self.reflectModelOverride = reflectModelOverride
    self.criticModelOverride = criticModelOverride
    self.codemapModelOverride = codemapModelOverride
    self.contextWindowTokens = contextWindowTokens
    self.webSearchAssignment = webSearchAssignment
    self.imageUnderstandingAssignment = imageUnderstandingAssignment
    self.imageAssignment = imageAssignment
    self.audioAssignment = audioAssignment
    self.videoAssignment = videoAssignment
  }

  /// Build settings from the given environment dictionary (defaults to the
  /// process environment). Empty / whitespace-only values are treated as
  /// unset so a developer can `unset COMPASS_AGENT_MODEL_PLAN` by exporting
  /// it as `""`. The seeded text provider is `.minimaxToken` when an API
  /// key env var is present (env vars predate the per-capability provider
  /// switch and have always pointed at an OpenAI-compatible endpoint); a
  /// fully-empty env falls back to the on-device default
  /// (`.appleFoundationModels`). The resolved context window then comes
  /// from whichever provider was chosen, unless the env var overrides
  /// explicitly.
  static func defaultFromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let baseURL =
      environment.compassAgentTrimmed("COMPASS_AGENT_BASE_URL")
      .flatMap(URL.init(string:)) ?? defaultBaseURL
    let chosenProvider: AgentProviderKind =
      environment.compassAgentTrimmed("COMPASS_AGENT_API_KEY") != nil
      ? .minimaxToken : defaultTextProvider
    let model = environment.compassAgentTrimmed("COMPASS_AGENT_MODEL") ?? defaultModelIdentifier
    let contextWindow =
      environment.compassAgentTrimmed("COMPASS_AGENT_CONTEXT_WINDOW_TOKENS")
      .flatMap(Int.init) ?? chosenProvider.textContextWindowTokens(for: model)
    return Self(
      textProvider: chosenProvider,
      baseURL: baseURL,
      apiKey: environment.compassAgentTrimmed("COMPASS_AGENT_API_KEY") ?? "",
      model: model,
      planModelOverride: environment.compassAgentTrimmed("COMPASS_AGENT_MODEL_PLAN"),
      developModelOverride: environment.compassAgentTrimmed("COMPASS_AGENT_MODEL_DEV"),
      reflectModelOverride: environment.compassAgentTrimmed("COMPASS_AGENT_MODEL_REFLECT"),
      criticModelOverride: environment.compassAgentTrimmed("COMPASS_AGENT_MODEL_CRITIC"),
      codemapModelOverride: environment.compassAgentTrimmed("COMPASS_AGENT_MODEL_CODEMAP"),
      contextWindowTokens: max(contextWindow, 0)
    )
  }

  /// Resolve the model identifier for the codemap summary pass. Returns
  /// the dedicated override if set, otherwise the base model — keeping
  /// summary cost a deliberate opt-in to a cheaper tier rather than a
  /// silent surprise.
  var codemapModel: String {
    codemapModelOverride ?? model
  }

  /// Convenience: the image capability's configured model, or `nil`
  /// if the capability is unassigned.
  var webSearchModel: String? { webSearchAssignment?.model }
  var imageUnderstandingModel: String? { imageUnderstandingAssignment?.model }
  var imageModel: String? { imageAssignment?.model }
  var audioModel: String? { audioAssignment?.model }
  var videoModel: String? { videoAssignment?.model }

  /// True when the Text capability is configured and available enough
  /// to drive a run: an on-device provider must be present on this
  /// system, while an OpenAI-compatible provider needs a non-empty API
  /// key. Used by the onboarding gate and menu shortcuts to decide
  /// whether the rest of the UI is unlocked.
  var isTextCapabilityReady: Bool {
    isTextCapabilityRunnable(foundationModelsAvailable: FoundationModelsAvailability.isAvailable)
  }

  func isTextCapabilityRunnable(foundationModelsAvailable: Bool) -> Bool {
    if textProvider.requiresCredentials {
      return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return foundationModelsAvailable
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
    case .critic: phaseOverride = criticModelOverride
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
