import Foundation

#if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
  import MLXLLM
  import MLXLMCommon
  import Tokenizers
#endif

package struct LocalModelGenerationRequest: Sendable, Equatable {
  package var modelID: String
  package var systemPrompt: String
  package var prompt: String
  package var maxOutputTokens: Int
  package var logLabel: String?

  package init(
    modelID: String = LocalModelCatalog.blessedModelID,
    systemPrompt: String,
    prompt: String,
    maxOutputTokens: Int = AgentExecutor.maxCompletionTokensPerTurn,
    logLabel: String? = nil
  ) {
    self.modelID = modelID
    self.systemPrompt = systemPrompt
    self.prompt = prompt
    self.maxOutputTokens = max(1, maxOutputTokens)
    self.logLabel = logLabel
  }
}

package struct LocalModelGenerationResult: Sendable, Equatable {
  package var text: String
  package var tokenUsage: AgentRunTokenUsage
}

package protocol LocalModelGenerating: Sendable {
  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult
}

package actor MLXLocalModelRuntime: LocalModelGenerating {
  package static let shared = MLXLocalModelRuntime()

  private var loadedModelID: String?
  private var unloadTask: Task<Void, Never>?

  #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(Tokenizers)
    private var loadedModel: ModelContainer?
  #endif

  package func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
    guard request.modelID == LocalModelCatalog.blessedModelID else {
      throw LocalModelRuntimeError.incompatibleModel(
        active: LocalModelCatalog.blessedModelID,
        requested: request.modelID
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

  package func unloadNow() async {
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
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
      let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
      return LocalHuggingFaceTokenizer(upstream)
    }
  }

  private struct LocalHuggingFaceTokenizer: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
      self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
      upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
      upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
      upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
      upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }

    var eosToken: String? { upstream.eosToken }

    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
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
