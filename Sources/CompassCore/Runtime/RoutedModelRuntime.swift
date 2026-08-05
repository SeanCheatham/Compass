import Foundation

public enum ModelRuntimeFactory {
  public static func makeCloud(settings: AgentRuntimeSettings) -> OpenAICompatibleModelRuntime? {
    guard settings.hasCloudCredentials else { return nil }
    return OpenAICompatibleModelRuntime(settings: settings)
  }

  public static func makeLocal() -> (any LocalModelGenerating)? {
    guard LocalModelCatalog.isBlessedModelReady() else { return nil }
    return MLXLocalModelRuntime.shared
  }

  public static func makeRouted(
    settings: AgentRuntimeSettings,
    cloud: (any LocalModelGenerating)? = nil,
    local: (any LocalModelGenerating)? = nil
  ) -> RoutedModelRuntime {
    let resolvedCloud: (any LocalModelGenerating)?
    if let cloud {
      resolvedCloud = cloud
    } else if settings.textProvider == .openAICompatible || settings.hasCloudCredentials {
      resolvedCloud = makeCloud(settings: settings)
    } else {
      resolvedCloud = nil
    }

    let resolvedLocal: (any LocalModelGenerating)?
    if let local {
      resolvedLocal = local
    } else {
      resolvedLocal = makeLocal()
    }

    return RoutedModelRuntime(
      cloud: resolvedCloud,
      local: resolvedLocal,
      preferCloudWhenAvailable: settings.textProvider == .openAICompatible
    )
  }
}

public enum RoutedModelRuntimeError: LocalizedError, Equatable {
  case noBackend(ModelRoutingHint)

  public var errorDescription: String? {
    switch self {
    case .noBackend(let hint):
      switch hint {
      case .cloudPrimary:
        return
          "No model backend is ready. Configure an OpenAI-compatible endpoint (API key, base URL, model) or download the local MLX model."
      case .localPreferred:
        return
          "No assist model is ready. Download the local MLX model or configure an OpenAI-compatible endpoint."
      }
    }
  }
}

/// Routes generation requests between cloud (OpenAI-compatible) and local MLX.
public struct RoutedModelRuntime: LocalModelGenerating, Sendable {
  public var cloud: (any LocalModelGenerating)?
  public var local: (any LocalModelGenerating)?
  public var preferCloudWhenAvailable: Bool

  public init(
    cloud: (any LocalModelGenerating)?,
    local: (any LocalModelGenerating)?,
    preferCloudWhenAvailable: Bool = true
  ) {
    self.cloud = cloud
    self.local = local
    self.preferCloudWhenAvailable = preferCloudWhenAvailable
  }

  public func generateText(request: LocalModelGenerationRequest) async throws
    -> LocalModelGenerationResult
  {
    let runtime = try selectRuntime(for: request.routingHint)
    var resolvedRequest = request
    if let local, isSameBackend(runtime, local) {
      resolvedRequest.modelID = LocalModelCatalog.blessedModelID
    }
    return try await runtime.generateText(request: resolvedRequest)
  }

  private func isSameBackend(
    _ lhs: any LocalModelGenerating,
    _ rhs: any LocalModelGenerating
  ) -> Bool {
    (lhs as AnyObject) === (rhs as AnyObject)
  }

  public func selectRuntime(for hint: ModelRoutingHint) throws -> any LocalModelGenerating {
    switch hint {
    case .cloudPrimary:
      if preferCloudWhenAvailable, let cloud {
        return cloud
      }
      if let local {
        return local
      }
      if let cloud {
        return cloud
      }
      throw RoutedModelRuntimeError.noBackend(hint)
    case .localPreferred:
      if let local {
        return local
      }
      if let cloud {
        return cloud
      }
      throw RoutedModelRuntimeError.noBackend(hint)
    }
  }

  /// The backend a `.cloudPrimary` turn would use, cast to the native
  /// tool-calling interface when it supports one. Returns `nil` for
  /// text-only backends (fixtures, legacy runtimes), which keeps those
  /// callers on the envelope loop.
  public func chatBackend(for hint: ModelRoutingHint = .cloudPrimary) -> (any AgentChatGenerating)?
  {
    try? selectRuntime(for: hint) as? AgentChatGenerating
  }
}

extension ModelRuntimeFactory {
  /// Prompt mode callers should use when building phase prompts for the
  /// runtime this configuration will resolve to. Both real backends (cloud,
  /// MLX) support native tool calling; injected text-only runtimes stay on
  /// the envelope protocol.
  public static func promptMode(
    settings: AgentRuntimeSettings,
    modelRuntime: (any LocalModelGenerating)? = nil
  ) -> AgentPromptMode {
    if let modelRuntime {
      if let logging = modelRuntime as? PromptLoggingLocalModelRuntime {
        return logging.chatBase != nil ? .nativeTools : .envelope
      }
      if let routed = modelRuntime as? RoutedModelRuntime {
        return routed.chatBackend(for: .cloudPrimary) != nil ? .nativeTools : .envelope
      }
      return modelRuntime is any AgentChatGenerating ? .nativeTools : .envelope
    }
    return makeRouted(settings: settings).chatBackend(for: .cloudPrimary) != nil
      ? .nativeTools
      : .envelope
  }
}
