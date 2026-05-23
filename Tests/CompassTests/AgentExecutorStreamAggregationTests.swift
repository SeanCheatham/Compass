import Foundation
import OpenAI
import XCTest

@testable import Compass

/// Exercises `AgentExecutor.aggregate(stream:)`, the internal seam that
/// turns a chat-completions stream into an `AggregatedTurn`. Building
/// canned chunks means decoding them from JSON because MacPaw's
/// `ChatStreamResult` has no public memberwise initializer.
final class AgentExecutorStreamAggregationTests: XCTestCase {

  // MARK: - Basic aggregation

  func testAggregatesContentDeltasInOrder() async throws {
    let chunks = try chunks(fromJSONFragments: [
      delta(content: "Hello, "),
      delta(content: "world!"),
      finalChunk(finishReason: "stop"),
    ])
    let executor = AgentExecutor()
    let turn = try await executor.aggregate(stream: chunks)
    XCTAssertEqual(turn.assistantText, "Hello, world!")
    XCTAssertEqual(turn.finishReason, "stop")
    XCTAssertTrue(turn.toolCalls.isEmpty)
    XCTAssertEqual(turn.reasoningText, "")
  }

  func testAggregatesReasoningSeparately() async throws {
    let chunks = try chunks(fromJSONFragments: [
      deltaRaw(#""reasoning": "step 1", "content": "answer""#),
      finalChunk(finishReason: "stop"),
    ])
    let executor = AgentExecutor()
    let turn = try await executor.aggregate(stream: chunks)
    XCTAssertEqual(turn.assistantText, "answer")
    XCTAssertEqual(turn.reasoningText, "step 1")
  }

  func testStripsThinkTagsFromContent() async throws {
    let chunks = try chunks(fromJSONFragments: [
      delta(content: "before <think>secret</think> after"),
      finalChunk(finishReason: "stop"),
    ])
    let executor = AgentExecutor()
    let turn = try await executor.aggregate(stream: chunks)
    XCTAssertEqual(turn.assistantText, "before  after")
    XCTAssertEqual(turn.reasoningText, "secret")
  }

  // MARK: - Tool call assembly

  func testReassemblesToolCallFromFragmentedDeltas() async throws {
    let chunks = try chunks(fromJSONFragments: [
      toolCallDelta(index: 0, id: "call_1", name: "read_file", argumentsFragment: #"{"pat"#),
      toolCallDelta(index: 0, argumentsFragment: #"h":"foo.txt"}"#),
      finalChunk(finishReason: "tool_calls"),
    ])
    let executor = AgentExecutor()
    let turn = try await executor.aggregate(stream: chunks)
    XCTAssertEqual(turn.toolCalls.count, 1)
    XCTAssertEqual(turn.toolCalls.first?.name, "read_file")
    XCTAssertEqual(turn.toolCalls.first?.id, "call_1")
    XCTAssertEqual(turn.toolCalls.first?.arguments, #"{"path":"foo.txt"}"#)
    XCTAssertEqual(turn.finishReason, "toolCalls")
  }

  func testKeepsToolCallsOrderedByIndex() async throws {
    let chunks = try chunks(fromJSONFragments: [
      toolCallDelta(index: 1, id: "call_b", name: "ls", argumentsFragment: "{}"),
      toolCallDelta(index: 0, id: "call_a", name: "read_file", argumentsFragment: "{}"),
      finalChunk(finishReason: "tool_calls"),
    ])
    let executor = AgentExecutor()
    let turn = try await executor.aggregate(stream: chunks)
    XCTAssertEqual(turn.toolCalls.map(\.id), ["call_a", "call_b"])
  }

  func testDropsToolCallsMissingIdOrName() async throws {
    let chunks = try chunks(fromJSONFragments: [
      toolCallDelta(index: 0, argumentsFragment: "{}"),  // never gets id/name
      toolCallDelta(index: 1, id: "call_b", name: "ls", argumentsFragment: "{}"),
      finalChunk(finishReason: "tool_calls"),
    ])
    let executor = AgentExecutor()
    let turn = try await executor.aggregate(stream: chunks)
    XCTAssertEqual(turn.toolCalls.map(\.id), ["call_b"])
  }

  // MARK: - Cancellation

  func testCancelledExecutorThrowsBeforeConsumingStream() async {
    let executor = AgentExecutor()
    executor.cancel()
    let chunks = try! chunks(fromJSONFragments: [delta(content: "anything")])
    do {
      _ = try await executor.aggregate(stream: chunks)
      XCTFail("expected cancellation")
    } catch let error as AgentExecutionError {
      XCTAssertEqual(error, .cancelled)
    } catch {
      XCTFail("expected AgentExecutionError.cancelled, got \(error)")
    }
  }

  // MARK: - Helpers

  /// Build an `AsyncThrowingStream<ChatStreamResult, Error>` from a list
  /// of JSON fragments that each look like one SSE `data:` payload.
  private func chunks(fromJSONFragments fragments: [String]) throws
    -> AsyncThrowingStream<ChatStreamResult, Error>
  {
    let decoder = JSONDecoder()
    let decoded = try fragments.map { fragment -> ChatStreamResult in
      try decoder.decode(ChatStreamResult.self, from: Data(fragment.utf8))
    }
    return AsyncThrowingStream { continuation in
      for chunk in decoded {
        continuation.yield(chunk)
      }
      continuation.finish()
    }
  }

  /// Minimal `chat.completion.chunk` carrying just a `content` delta.
  private func delta(content: String) -> String {
    let escaped = jsonEscape(content)
    return """
      {"id":"x","object":"chat.completion.chunk","created":0,"model":"m",
      "choices":[{"index":0,"delta":{"content":"\(escaped)"},"finish_reason":null,"logprobs":null}]}
      """
  }

  /// A chunk where the caller supplies the raw `delta` body so reasoning
  /// fields can be included alongside content.
  private func deltaRaw(_ rawDeltaBody: String) -> String {
    """
    {"id":"x","object":"chat.completion.chunk","created":0,"model":"m",
    "choices":[{"index":0,"delta":{\(rawDeltaBody)},"finish_reason":null,"logprobs":null}]}
    """
  }

  /// A chunk that streams one tool-call fragment. Fields default to
  /// empty so a later chunk can supply them — mirrors how OpenAI
  /// streams tool calls in pieces.
  private func toolCallDelta(
    index: Int,
    id: String? = nil,
    name: String? = nil,
    argumentsFragment: String
  ) -> String {
    var function: [String: String] = ["arguments": argumentsFragment]
    if let name { function["name"] = name }
    let functionFields =
      function
      .sorted { $0.key < $1.key }
      .map { #""\#($0.key)":"\#(jsonEscape($0.value))""# }
      .joined(separator: ",")
    var call = #""index":\#(index),"type":"function","function":{\#(functionFields)}"#
    if let id { call += #","id":"\#(id)""# }
    return """
      {"id":"x","object":"chat.completion.chunk","created":0,"model":"m",
      "choices":[{"index":0,"delta":{"tool_calls":[{\(call)}]},"finish_reason":null,"logprobs":null}]}
      """
  }

  private func finalChunk(finishReason: String) -> String {
    """
    {"id":"x","object":"chat.completion.chunk","created":0,"model":"m",
    "choices":[{"index":0,"delta":{},"finish_reason":"\(finishReason)","logprobs":null}]}
    """
  }

  private func jsonEscape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}
