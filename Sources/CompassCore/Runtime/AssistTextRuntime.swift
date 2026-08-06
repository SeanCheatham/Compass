import Foundation

/// Lightweight assist text path for Studio thinking narration and similar
/// non-agent helpers.
///
/// Prefer MLX when downloaded; otherwise fall back to the configured
/// OpenAI-compatible cloud endpoint. Agent Plan/Develop/Critic turns and
/// transcript compaction do not use this path — they go through
/// `AgentExecutor` + `RoutedModelRuntime` with `.cloudPrimary`.
public enum AssistTextRuntime {
  public struct TextProvider: Sendable {
    public var isAvailable: @Sendable () -> Bool
    public var streamText: @Sendable (_ prompt: String) async -> String?

    public init(
      isAvailable: @escaping @Sendable () -> Bool,
      streamText: @escaping @Sendable (_ prompt: String) async -> String?
    ) {
      self.isAvailable = isAvailable
      self.streamText = streamText
    }
  }

  @TaskLocal private static var textProviderOverride: TextProvider?

  public static func withTextProvider<T>(
    _ provider: TextProvider,
    operation: () async throws -> T
  ) async rethrows -> T {
    try await $textProviderOverride.withValue(provider) {
      try await operation()
    }
  }

  public static var isAvailable: Bool {
    if let textProviderOverride {
      return textProviderOverride.isAvailable()
    }
    let settings = AgentSettingsStore().load()
    return settings.isTextCapabilityReady || settings.isLocalAssistReady
  }

  public static func generateText(prompt: String) async -> String? {
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
          logLabel: "assist-text",
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
