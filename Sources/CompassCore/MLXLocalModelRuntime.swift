import Foundation

#if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
  import MLXLLM
  import MLXLMCommon
  import Tokenizers
#endif

public enum ModelRoutingHint: String, Sendable, Equatable {
  /// Plan / Develop / Critic agent turns — prefer the configured cloud endpoint.
  case cloudPrimary
  /// Cheap assist work (compaction, narrators, codemap) — prefer MLX when ready.
  case localPreferred
}

public struct LocalModelGenerationRequest: Sendable, Equatable {
  public var modelID: String
  public var systemPrompt: String
  public var prompt: String
  public var maxOutputTokens: Int
  public var logLabel: String?
  public var routingHint: ModelRoutingHint

  public init(
    modelID: String = LocalModelCatalog.blessedModelID,
    systemPrompt: String,
    prompt: String,
    maxOutputTokens: Int = AgentExecutor.maxCompletionTokensPerTurn,
    logLabel: String? = nil,
    routingHint: ModelRoutingHint = .cloudPrimary
  ) {
    self.modelID = modelID
    self.systemPrompt = systemPrompt
    self.prompt = prompt
    self.maxOutputTokens = max(1, maxOutputTokens)
    self.logLabel = logLabel
    self.routingHint = routingHint
  }
}

public struct LocalModelGenerationResult: Sendable, Equatable {
  public var text: String
  public var tokenUsage: AgentRunTokenUsage
}

public protocol LocalModelGenerating: Sendable {
  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult
}

public actor MLXLocalModelRuntime: LocalModelGenerating {
  public static let shared = MLXLocalModelRuntime()

  private var loadedModelID: String?
  private var unloadTask: Task<Void, Never>?

  #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
    private var loadedModel: ModelContainer?
  #endif

  public func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
    guard request.modelID == LocalModelCatalog.blessedModelID else {
      throw LocalModelRuntimeError.generationFailed(
        "Local MLX runtime only supports \(LocalModelCatalog.blessedModelID); cannot serve model \"\(request.modelID)\"."
      )
    }
    guard LocalModelCatalog.isBlessedModelReady() else {
      throw LocalModelRuntimeError.modelMissing(
        "\(LocalModelCatalog.blessedModelID) is not downloaded. Open Settings and download the local MLX model before running Compass."
      )
    }

    let startedAt = Date()
    try await LocalModelLease.shared.beginRun(modelID: request.modelID)
    await MainActor.run {
      LocalModelManager.shared.markLoaded()
    }
    unloadTask?.cancel()
    unloadTask = nil

    defer {
      Task {
        await LocalModelLease.shared.endRun(modelID: request.modelID)
      }
      scheduleIdleUnload(modelID: request.modelID)
    }

    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
      let model = try await loadModelIfNeeded(modelID: request.modelID)
      let session = ChatSession(model, instructions: request.systemPrompt)
      let text = try await session.respond(to: request.prompt)
      var usage = AgentRunTokenUsage.estimated(
        inputCharacters: request.systemPrompt.count + request.prompt.count,
        outputCharacters: text.count,
        charsPerToken: AgentExecutor.estimatedCharsPerToken
      )
      usage.durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
      return LocalModelGenerationResult(text: text, tokenUsage: usage)
    #else
      throw LocalModelRuntimeError.unavailable(
        "MLX Swift LM is not linked in this build."
      )
    #endif
  }

  public func unloadNow() async {
    unloadTask?.cancel()
    unloadTask = nil
    loadedModelID = nil
    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
      loadedModel = nil
    #endif
    await LocalModelLease.shared.unloadNow()
  }

  private func scheduleIdleUnload(modelID: String) {
    unloadTask?.cancel()
    unloadTask = Task { [weak self] in
      let timeout = await LocalModelLease.shared.idleTimeoutForRuntime()
      if timeout > 0 {
        try? await Task.sleep(nanoseconds: timeout)
      }
      await self?.unloadIfIdle(modelID: modelID)
    }
  }

  private func unloadIfIdle(modelID: String) async {
    let snapshot = await LocalModelLease.shared.snapshot()
    guard snapshot.loadedModelID == nil || snapshot.loadedModelID == modelID,
      snapshot.activeRunCount == 0
    else {
      return
    }
    loadedModelID = nil
    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
      loadedModel = nil
    #endif
    await MainActor.run {
      LocalModelManager.shared.markUnloaded()
    }
  }

  #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
    private func loadModelIfNeeded(modelID: String) async throws -> ModelContainer {
      if let loadedModel, loadedModelID == modelID {
        return loadedModel
      }
      let directory = LocalModelCatalog.blessedModelDirectory
      do {
        let model = try await loadModelContainer(
          from: directory,
          using: LocalHuggingFaceTokenizerLoader()
        )
        loadedModel = model
        loadedModelID = modelID
        return model
      } catch {
        throw LocalModelRuntimeError.generationFailed(
          "MLX could not load \(modelID): \(error.localizedDescription)"
        )
      }
    }
  #endif
}

#if canImport(MLXLMCommon) && canImport(Tokenizers)
  private struct LocalHuggingFaceTokenizerLoader: MLXLMCommon.TokenizerLoader {
    public func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
      let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
      return LocalHuggingFaceTokenizer(upstream)
    }
  }

  private struct LocalHuggingFaceTokenizer: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    public init(_ upstream: any Tokenizers.Tokenizer) {
      self.upstream = upstream
    }

    public func encode(text: String, addSpecialTokens: Bool) -> [Int] {
      upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    public func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
      upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    public func convertTokenToId(_ token: String) -> Int? {
      upstream.convertTokenToId(token)
    }

    public func convertIdToToken(_ id: Int) -> String? {
      upstream.convertIdToToken(id)
    }

    public var bosToken: String? { upstream.bosToken }

    public var eosToken: String? { upstream.eosToken }

    public var unknownToken: String? { upstream.unknownToken }

    public func applyChatTemplate(
      messages: [[String: any Sendable]],
      tools: [[String: any Sendable]]?,
      additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
      do {
        return try upstream.applyChatTemplate(
          messages: messages,
          tools: tools,
          additionalContext: additionalContext
        )
      } catch Tokenizers.TokenizerError.missingChatTemplate {
        throw MLXLMCommon.TokenizerError.missingChatTemplate
      }
    }
  }
#endif

extension MLXLocalModelRuntime: AgentChatGenerating {
  /// Native tool-calling turn against the local MLX model. The model's chat
  /// template receives real tool specs and its tool-call output is parsed by
  /// MLXLMCommon's tool-call processor, so the agentic loop no longer relies
  /// on the fragile one-JSON-object text protocol for local runs either.
  public func generateChat(request: AgentChatRequest) async throws -> AgentChatResponse {
    guard request.modelID == LocalModelCatalog.blessedModelID else {
      throw LocalModelRuntimeError.generationFailed(
        "Local MLX runtime only supports \(LocalModelCatalog.blessedModelID); cannot serve model \"\(request.modelID)\"."
      )
    }
    guard LocalModelCatalog.isBlessedModelReady() else {
      throw LocalModelRuntimeError.modelMissing(
        "\(LocalModelCatalog.blessedModelID) is not downloaded. Open Settings and download the local MLX model before running Compass."
      )
    }

    let startedAt = Date()
    try await LocalModelLease.shared.beginRun(modelID: request.modelID)
    await MainActor.run {
      LocalModelManager.shared.markLoaded()
    }
    unloadTask?.cancel()
    unloadTask = nil

    defer {
      Task {
        await LocalModelLease.shared.endRun(modelID: request.modelID)
      }
      scheduleIdleUnload(modelID: request.modelID)
    }

    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
      let model = try await loadModelIfNeeded(modelID: request.modelID)
      let toolSpecs: [ToolSpec] = request.tools.compactMap { $0.nativeToolJSONObject }

      var instructions: String?
      var history: [Chat.Message] = []
      for message in request.messages {
        switch message.role {
        case .system:
          instructions = [instructions, message.content]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        case .user:
          history.append(.user(message.content))
        case .assistant:
          history.append(.assistant(Self.renderAssistantHistory(message)))
        case .tool:
          history.append(.tool(message.content))
        }
      }
      guard !history.isEmpty else {
        throw LocalModelRuntimeError.generationFailed("Chat request contained no user messages.")
      }

      let session = ChatSession(
        model,
        instructions: instructions,
        tools: toolSpecs.isEmpty ? nil : toolSpecs
      )

      var text = ""
      var toolCalls: [AgentChatToolCall] = []
      var completionInfo: GenerateCompletionInfo?
      for try await generation in session.streamDetails(to: history) {
        switch generation {
        case .chunk(let chunk):
          text += chunk
        case .toolCall(let toolCall):
          toolCalls.append(
            AgentChatToolCall(
              id: "local_\(toolCalls.count)",
              name: toolCall.function.name,
              argumentsJSON: Self.argumentsJSONString(
                from: toolCall.function.arguments.mapValues { $0.anyValue }
              )
            )
          )
        case .info(let info):
          completionInfo = info
        }
      }

      var usage: AgentRunTokenUsage
      if let completionInfo {
        usage = AgentRunTokenUsage()
        usage.recordTurn(
          inputTokens: completionInfo.promptTokenCount,
          outputTokens: completionInfo.generationTokenCount,
          totalTokens: completionInfo.promptTokenCount + completionInfo.generationTokenCount,
          isEstimated: false,
          streamedUsageAvailable: true
        )
      } else {
        let serializedInput = (instructions ?? "") + history.map(\.content).joined()
        usage = AgentRunTokenUsage.estimated(
          inputCharacters: serializedInput.count,
          outputCharacters: text.count,
          charsPerToken: AgentExecutor.estimatedCharsPerToken
        )
      }
      usage.durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
      return AgentChatResponse(
        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
        toolCalls: toolCalls,
        tokenUsage: usage
      )
    #else
      throw LocalModelRuntimeError.unavailable(
        "MLX Swift LM is not linked in this build."
      )
    #endif
  }

  /// Re-serializes an assistant turn's tool calls in the format the model's
  /// own chat template produces, so re-prefilled history matches what the
  /// model would have generated.
  private static func renderAssistantHistory(_ message: AgentChatMessage) -> String {
    guard !message.toolCalls.isEmpty else { return message.content }
    let renderedCalls = message.toolCalls.map { call -> String in
      let arguments: String
      if let data = call.argumentsJSON.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data),
        JSONSerialization.isValidJSONObject(object),
        let normalized = try? JSONSerialization.data(
          withJSONObject: object,
          options: [.sortedKeys, .withoutEscapingSlashes]
        )
      {
        arguments = String(decoding: normalized, as: UTF8.self)
      } else {
        arguments = call.argumentsJSON
      }
      return """
        <tool_call>
        {"name": "\(call.name)", "arguments": \(arguments)}
        </tool_call>
        """
    }
    return ([message.content] + renderedCalls)
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  private static func argumentsJSONString(from arguments: [String: Any]) -> String {
    guard JSONSerialization.isValidJSONObject(arguments),
      let data = try? JSONSerialization.data(
        withJSONObject: arguments,
        options: [.sortedKeys, .withoutEscapingSlashes]
      )
    else {
      return "{}"
    }
    return String(decoding: data, as: UTF8.self)
  }
}
