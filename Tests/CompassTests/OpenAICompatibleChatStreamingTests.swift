import Foundation
import Testing

@testable import CompassCore

@Suite("Cloud chat streaming", .serialized)
struct OpenAICompatibleChatStreamingTests {
  final class SSEProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseBody: String = ""
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      if let body = request.httpBody {
        Self.lastRequestBody = body
      } else if let stream = request.httpBodyStream {
        stream.open()
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65_536)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
          let read = stream.read(buffer, maxLength: 65_536)
          if read <= 0 { break }
          data.append(buffer, count: read)
        }
        stream.close()
        Self.lastRequestBody = data
      }
      let body = Self.responseBody
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "text/event-stream"]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
  }

  private func session() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SSEProtocol.self]
    return URLSession(configuration: config)
  }

  private func runtime() -> OpenAICompatibleModelRuntime {
    OpenAICompatibleModelRuntime(
      endpoint: OpenAICompatibleEndpoint(
        baseURL: URL(string: "https://api.example.com/v1")!,
        apiKey: "sk-test",
        model: "k3"
      ),
      session: session()
    )
  }

  @Test
  func streamsToolCallsAndUsage() async throws {
    SSEProtocol.responseBody = """
      data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"read_file","arguments":"{\\"path\\""}}]}}]}

      data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\\"a.txt\\"}"}}]}}]}

      data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":1234,"completion_tokens":56,"total_tokens":1290}}

      data: [DONE]

      """
    let response = try await runtime().generateChat(
      request: AgentChatRequest(
        modelID: "k3",
        messages: [.system("sys"), .user("hi")],
        tools: [
          AgentToolSpec(
            name: "read_file",
            description: "Read a file",
            parameters: AgentToolParametersSchema(literal: ["type": "object"])
          )
        ]
      )
    )
    #expect(response.toolCalls.count == 1)
    #expect(response.toolCalls.first?.id == "call_1")
    #expect(response.toolCalls.first?.name == "read_file")
    #expect(response.toolCalls.first?.argumentsJSON == #"{"path":"a.txt"}"#)
    #expect(response.tokenUsage.inputTokens == 1234)
    #expect(response.tokenUsage.usesEstimate == false)

    let body = try #require(SSEProtocol.lastRequestBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["stream"] as? Bool == true)
    #expect((json["tools"] as? [[String: Any]])?.count == 1)
    #expect(json["tool_choice"] as? String == "auto")
  }

  @Test
  func streamsPlainTextContent() async throws {
    SSEProtocol.responseBody = """
      data: {"choices":[{"delta":{"content":"Hello, "}}]}

      data: {"choices":[{"delta":{"content":"world"}}]}

      data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

      data: [DONE]

      """
    let response = try await runtime().generateChat(
      request: AgentChatRequest(modelID: "k3", messages: [.user("hi")])
    )
    #expect(response.text == "Hello, world")
    #expect(response.toolCalls.isEmpty)
    #expect(response.tokenUsage.usesEstimate == true)
  }

  @Test
  func streamsReasoningOnlyWithoutFinishReasonAsError() async throws {
    SSEProtocol.responseBody = """
      data: {"choices":[{"delta":{"reasoning_content":"thinking..."}}]}

      data: [DONE]

      """
    await #expect(throws: OpenAICompatibleRuntimeError.self) {
      _ = try await runtime().generateChat(
        request: AgentChatRequest(modelID: "k3", messages: [.user("hi")])
      )
    }
  }

  @Test
  func streamsReasoningThenStopWithoutContentSucceedsEmpty() async throws {
    SSEProtocol.responseBody = """
      data: {"choices":[{"delta":{"reasoning_content":"thinking..."}}]}

      data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

      data: [DONE]

      """
    let response = try await runtime().generateChat(
      request: AgentChatRequest(modelID: "k3", messages: [.user("hi")])
    )
    #expect(response.text.isEmpty)
    #expect(response.toolCalls.isEmpty)
  }

  @Test
  func encodesAssistantToolCallsAndToolResults() async throws {
    SSEProtocol.responseBody = "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n"
    _ = try await runtime().generateChat(
      request: AgentChatRequest(
        modelID: "k3",
        messages: [
          .system("sys"),
          .user("work"),
          .assistant(
            "",
            toolCalls: [AgentChatToolCall(id: "c1", name: "read_file", argumentsJSON: #"{"path":"a"}"#)]
          ),
          .toolResult("contents", toolCallID: "c1"),
        ]
      )
    )
    let body = try #require(SSEProtocol.lastRequestBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try #require(json["messages"] as? [[String: Any]])
    #expect(messages.count == 4)
    let assistant = messages[2]
    let toolCalls = try #require(assistant["tool_calls"] as? [[String: Any]])
    #expect(toolCalls.first?["id"] as? String == "c1")
    #expect((toolCalls.first?["function"] as? [String: Any])?["name"] as? String == "read_file")
    #expect(messages[3]["role"] as? String == "tool")
    #expect(messages[3]["tool_call_id"] as? String == "c1")
  }

  @Test
  func generateChatRetriesTransientOverloadThenSucceeds() async throws {
    final class FlakySSEProtocol: URLProtocol, @unchecked Sendable {
      nonisolated(unsafe) static var callCount = 0

      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

      override func startLoading() {
        Self.callCount += 1
        if Self.callCount == 1 {
          let body = Data(
            #"{"error":{"message":"The engine is currently overloaded, please try again later","type":"engine_overloaded_error"}}"#
              .utf8
          )
          let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
          )!
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          client?.urlProtocol(self, didLoad: body)
          client?.urlProtocolDidFinishLoading(self)
          return
        }

        let body = Data(
          """
          data: {"choices":[{"delta":{"content":"recovered"}}]}

          data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

          data: [DONE]

          """.utf8
        )
        let response = HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
      }

      override func stopLoading() {}
    }

    FlakySSEProtocol.callCount = 0
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FlakySSEProtocol.self]
    let runtime = OpenAICompatibleModelRuntime(
      endpoint: OpenAICompatibleEndpoint(
        baseURL: URL(string: "https://api.example.com/v1")!,
        apiKey: "sk-test",
        model: "k3"
      ),
      session: URLSession(configuration: config),
      retryPolicy: OpenAICompatibleRetryPolicy(
        maxAttempts: 3,
        initialBackoffNanoseconds: 50,
        maxBackoffNanoseconds: 500,
        jitterFraction: 0
      ),
      sleep: { _ in }
    )
    let response = try await runtime.generateChat(
      request: AgentChatRequest(modelID: "k3", messages: [.user("hi")])
    )
    #expect(response.text == "recovered")
    #expect(FlakySSEProtocol.callCount == 2)
  }
}
