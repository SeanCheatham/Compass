import Foundation

/// Describes why an Explore explanation could not be generated.
enum ExplainUnavailableReason: Sendable, CaseIterable {
  case foundationModelsUnavailable
  case noDiff
  case emptyDiff
  case emptyResponse
  case unavailable

  var message: String {
    switch self {
    case .foundationModelsUnavailable:
      return "Generated explanation is unavailable until a text model is configured."
    case .noDiff:
      return "No commit diff available for this file."
    case .emptyDiff:
      return "No content changes found in this file."
    case .emptyResponse:
      return "The model did not produce an explanation. Please try again."
    case .unavailable:
      return "Explanation unavailable."
    }
  }
}

/// Lightweight assist text path for narrators and Explore helpers.
///
/// Prefer MLX when downloaded; otherwise fall back to the configured
/// OpenAI-compatible cloud endpoint. Agent Plan/Develop/Critic turns do not
/// use this path — they go through `AgentExecutor` + `RoutedModelRuntime`.
enum FoundationModelsAvailability {
  static let generatedExploreUnavailableMessage =
    "Generated Explore insight is unavailable until a text model is configured. Deterministic change details remain available."

  struct TextProvider: Sendable {
    var isAvailable: @Sendable () -> Bool
    var streamText: @Sendable (_ prompt: String) async -> String?

    init(
      isAvailable: @escaping @Sendable () -> Bool,
      streamText: @escaping @Sendable (_ prompt: String) async -> String?
    ) {
      self.isAvailable = isAvailable
      self.streamText = streamText
    }
  }

  @TaskLocal private static var textProviderOverride: TextProvider?

  static func withTextProvider<T>(
    _ provider: TextProvider,
    operation: () async throws -> T
  ) async rethrows -> T {
    try await $textProviderOverride.withValue(provider) {
      try await operation()
    }
  }

  static var isAvailable: Bool {
    if let textProviderOverride {
      return textProviderOverride.isAvailable()
    }
    let settings = AgentSettingsStore().load()
    return settings.isTextCapabilityReady || settings.isLocalAssistReady
  }

  static func _streamText(prompt: String) async -> String? {
    if let textProviderOverride {
      return await textProviderOverride.streamText(prompt)
    }

    let settings = AgentSettingsStore().load()
    let runtime = ModelRuntimeFactory.makeRouted(settings: settings)
    do {
      let result = try await runtime.generateText(
        request: LocalModelGenerationRequest(
          modelID: settings.codemapModel,
          systemPrompt:
            "You write concise, practical guidance for a local software-factory UI. Reply with plain text only.",
          prompt: prompt,
          maxOutputTokens: 512,
          logLabel: "assist-narration",
          routingHint: .localPreferred
        )
      )
      let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    } catch {
      return nil
    }
  }
}
