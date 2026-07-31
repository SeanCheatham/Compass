import Foundation

enum ModelRuntimeFactory {
  static func makeCloud(settings: AgentRuntimeSettings) -> OpenAICompatibleModelRuntime? {
    guard settings.hasCloudCredentials else { return nil }
    return OpenAICompatibleModelRuntime(settings: settings)
  }

  static func makeLocal() -> (any LocalModelGenerating)? {
    guard LocalModelCatalog.isBlessedModelReady() else { return nil }
    return MLXLocalModelRuntime.shared
  }

  static func makeRouted(
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

enum RoutedModelRuntimeError: LocalizedError, Equatable {
  case noBackend(ModelRoutingHint)

  var errorDescription: String? {
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
struct RoutedModelRuntime: LocalModelGenerating, Sendable {
  var cloud: (any LocalModelGenerating)?
  var local: (any LocalModelGenerating)?
  var preferCloudWhenAvailable: Bool

  init(
    cloud: (any LocalModelGenerating)?,
    local: (any LocalModelGenerating)?,
    preferCloudWhenAvailable: Bool = true
  ) {
    self.cloud = cloud
    self.local = local
    self.preferCloudWhenAvailable = preferCloudWhenAvailable
  }

  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
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

  func selectRuntime(for hint: ModelRoutingHint) throws -> any LocalModelGenerating {
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
}
