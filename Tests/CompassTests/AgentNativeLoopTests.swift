import Foundation
import Testing

@testable import CompassCore

@Suite("Native tool-calling loop")
struct AgentNativeLoopTests {
  final class ScriptedChatRuntime: AgentChatGenerating, @unchecked Sendable {
    var responses: [AgentChatResponse]
    private(set) var requests: [AgentChatRequest] = []

    init(responses: [AgentChatResponse]) {
      self.responses = responses
    }

    func generateChat(request: AgentChatRequest) async throws -> AgentChatResponse {
      requests.append(request)
      guard !responses.isEmpty else {
        throw AgentExecutionError.streamFailed("scripted runtime exhausted")
      }
      return responses.removeFirst()
    }
  }

  private func usage() -> AgentRunTokenUsage {
    var usage = AgentRunTokenUsage()
    usage.recordTurn(
      inputTokens: 100,
      outputTokens: 20,
      totalTokens: 120,
      isEstimated: false,
      streamedUsageAvailable: true
    )
    return usage
  }

  private func configuration(
    tools: [any AgentTool],
    validate: (@Sendable (Data) throws -> Void)? = nil
  ) -> AgentExecutionConfiguration {
    AgentExecutionConfiguration(
      settings: AgentRuntimeSettings(),
      phase: .develop,
      systemPrompt: "sys",
      userPrompt: "do the work",
      tools: tools,
      submitResultSchema: AgentToolParametersSchema(literal: ["type": "object"]),
      workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
      validateSubmitResult: validate,
      promptMode: .nativeTools,
      maxIterations: 8,
      wallClockTimeout: 60
    )
  }

  @Test
  func submitToolCallTerminatesWithPayload() async throws {
    let submitPayload = #"{"status":"succeeded","summary":"done"}"#
    let runtime = ScriptedChatRuntime(responses: [
      AgentChatResponse(
        text: "",
        toolCalls: [
          AgentChatToolCall(id: "c1", name: "develop_submit", argumentsJSON: submitPayload)
        ],
        tokenUsage: usage()
      )
    ])
    let executor = AgentExecutor()
    let result = try await executor.runNative(
      configuration(tools: []),
      chatRuntime: runtime,
      textRuntime: runtime
    )
    let decoded = try JSONSerialization.jsonObject(with: result.submitResultArguments) as? [String: Any]
    #expect(decoded?["status"] as? String == "succeeded")
    #expect(result.iterations == 1)

    let request = try #require(runtime.requests.first)
    #expect(request.tools.contains(where: { $0.name == "develop_submit" }))
    #expect(request.messages.first?.role == .system)
    #expect(request.messages.dropFirst().first?.role == .user)
  }

  @Test
  func rejectedSubmitBecomesToolResultAndRetries() async throws {
    struct RejectOnce: Error {}
    let validationCalls = ManagedCounter()
    let validate: @Sendable (Data) throws -> Void = { _ in
      if validationCalls.increment() == 1 {
        throw RejectOnce()
      }
    }
    let runtime = ScriptedChatRuntime(responses: [
      AgentChatResponse(
        text: "",
        toolCalls: [
          AgentChatToolCall(id: "c1", name: "develop_submit", argumentsJSON: #"{"status":"succeeded"}"#)
        ],
        tokenUsage: usage()
      ),
      AgentChatResponse(
        text: "",
        toolCalls: [
          AgentChatToolCall(id: "c2", name: "develop_submit", argumentsJSON: #"{"status":"succeeded"}"#)
        ],
        tokenUsage: usage()
      ),
    ])
    let executor = AgentExecutor()
    let result = try await executor.runNative(
      configuration(tools: [], validate: validate),
      chatRuntime: runtime,
      textRuntime: runtime
    )
    #expect(result.iterations == 2)
    let secondRequest = try #require(runtime.requests.dropFirst().first)
    let toolMessage = secondRequest.messages.last { $0.role == .tool }
    #expect(toolMessage?.toolCallID == "c1")
    #expect(toolMessage != nil)
  }

  @Test
  func toolCallExecutesAndObservationFlowsBack() async throws {
    let workspace = FileManager.default.temporaryDirectory
      .appending(path: "native-loop-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }
    try "hello".write(to: workspace.appending(path: "note.txt"), atomically: true, encoding: .utf8)

    let runtime = ScriptedChatRuntime(responses: [
      AgentChatResponse(
        text: "reading",
        toolCalls: [
          AgentChatToolCall(id: "c1", name: "read_file", argumentsJSON: #"{"path":"note.txt"}"#)
        ],
        tokenUsage: usage()
      ),
      AgentChatResponse(
        text: "",
        toolCalls: [
          AgentChatToolCall(id: "c2", name: "develop_submit", argumentsJSON: #"{"status":"succeeded"}"#)
        ],
        tokenUsage: usage()
      ),
    ])
    var config = configuration(tools: [AgentReadFileTool()])
    config.workingDirectory = workspace
    let executor = AgentExecutor()
    _ = try await executor.runNative(config, chatRuntime: runtime, textRuntime: runtime)

    let secondRequest = try #require(runtime.requests.dropFirst().first)
    let observation = secondRequest.messages.last { $0.role == .tool }
    #expect(observation?.content.contains("hello") == true)
    #expect(observation?.content.contains("isError") == true)
    let assistant = secondRequest.messages.last { $0.role == .assistant }
    #expect(assistant?.toolCalls.first?.name == "read_file")
  }

  @Test
  func parallelReadOnlyToolCallsReturnOrderedObservations() async throws {
    let workspace = FileManager.default.temporaryDirectory
      .appending(path: "native-parallel-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }
    try "alpha".write(to: workspace.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    try "beta".write(to: workspace.appending(path: "b.txt"), atomically: true, encoding: .utf8)

    let runtime = ScriptedChatRuntime(responses: [
      AgentChatResponse(
        text: "batch",
        toolCalls: [
          AgentChatToolCall(id: "c1", name: "read_file", argumentsJSON: #"{"path":"a.txt"}"#),
          AgentChatToolCall(id: "c2", name: "read_file", argumentsJSON: #"{"path":"b.txt"}"#),
        ],
        tokenUsage: usage()
      ),
      AgentChatResponse(
        text: "",
        toolCalls: [
          AgentChatToolCall(id: "c3", name: "develop_submit", argumentsJSON: #"{"status":"succeeded"}"#)
        ],
        tokenUsage: usage()
      ),
    ])
    var config = configuration(tools: [AgentReadFileTool()])
    config.workingDirectory = workspace
    let executor = AgentExecutor()
    _ = try await executor.runNative(config, chatRuntime: runtime, textRuntime: runtime)

    let secondRequest = try #require(runtime.requests.dropFirst().first)
    let toolMessages = secondRequest.messages.filter { $0.role == .tool }
    #expect(toolMessages.count == 2)
    #expect(toolMessages[0].toolCallID == "c1")
    #expect(toolMessages[1].toolCallID == "c2")
    #expect(toolMessages[0].content.contains("alpha"))
    #expect(toolMessages[1].content.contains("beta"))
  }

  @Test
  func proseOnlyTurnsAreNudgedThenFail() async throws {
    let runtime = ScriptedChatRuntime(
      responses: (0..<5).map { _ in
        AgentChatResponse(text: "some prose", toolCalls: [], tokenUsage: usage())
      }
    )
    let executor = AgentExecutor()
    await #expect(throws: AgentExecutionError.self) {
      _ = try await executor.runNative(
        configuration(tools: []),
        chatRuntime: runtime,
        textRuntime: runtime
      )
    }
    let lastRequest = try #require(runtime.requests.last)
    #expect(lastRequest.messages.last?.content.contains("no tool call was made") == true)
  }

  @Test
  func promptModeResolvesNativeForChatCapableBackends() {
    let chat = ScriptedChatRuntime(responses: [])
    #expect(
      ModelRuntimeFactory.promptMode(
        settings: AgentRuntimeSettings(),
        modelRuntime: chat
      ) == .nativeTools
    )
  }

  final class ManagedCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()

    func increment() -> Int {
      lock.lock()
      defer { lock.unlock() }
      value += 1
      return value
    }
  }
}

extension AgentNativeLoopTests.ScriptedChatRuntime: LocalModelGenerating {
  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
    throw AgentExecutionError.streamFailed("text generation not scripted")
  }
}
