import Foundation
import Testing

@testable import Compass

struct AgentWebSearchToolTests {
  @Test func testMiniMaxWebSearchAdapterUsesCodingPlanEndpoint() async throws {
    let recorder = WebSearchRequestRecorder()
    let transport = stubWebSearchJSONTransport(
      recorder: recorder,
      bodyJSON: [
        "organic": [
          [
            "title": "MiniMax docs",
            "link": "https://platform.minimax.io",
            "snippet": "Docs",
          ]
        ],
        "related_searches": [],
        "base_resp": [
          "status_code": 0,
          "status_msg": "success",
        ],
      ]
    )

    let output = try await DefaultAgentWebSearcher(transport: transport).search(
      query: "minimax mcp",
      assignment: CapabilityAssignment(
        provider: .minimaxToken,
        baseURL: URL(string: "https://api.minimax.io/v1")!,
        apiKey: "mm-key",
        model: ""
      )
    )

    try #require(output.contains("MiniMax docs"))
    let request = try #require(recorder.requests.first)
    try #require(
      request.url?.absoluteString == "https://api.minimax.io/v1/coding_plan/search"
    )
    try #require(request.value(forHTTPHeaderField: "Authorization") == "Bearer mm-key")
    let body = try #require(request.httpBody)
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    try #require(payload["q"] as? String == "minimax mcp")
  }

  @Test func testMiniMaxWebSearchAdapterAcceptsHostWithoutV1Path() async throws {
    let recorder = WebSearchRequestRecorder()
    let transport = stubWebSearchJSONTransport(
      recorder: recorder,
      bodyJSON: ["base_resp": ["status_code": 0]]
    )

    _ = try await DefaultAgentWebSearcher(transport: transport).search(
      query: "swift testing",
      assignment: CapabilityAssignment(
        provider: .minimaxToken,
        baseURL: URL(string: "https://api.minimax.io")!,
        apiKey: "mm-key",
        model: ""
      )
    )

    try #require(
      recorder.requests.first?.url?.absoluteString
        == "https://api.minimax.io/v1/coding_plan/search"
    )
  }

  @Test func testToolInvokesConfiguredSearcher() async throws {
    let searcher = StubWebSearcher(result: .success("result text"))
    let tool = AgentWebSearchTool(
      assignment: stubSearchAssignment(),
      searcher: searcher
    )
    let context = AgentToolContext(workingDirectory: FileManager.default.temporaryDirectory)

    let result = try await tool.invoke(
      arguments: Data(#"{"query": "latest swift"}"#.utf8),
      context: context
    )

    try #require(!result.isError, "tool reported failure: \(result.content)")
    try #require(result.content == "result text")
    try #require(searcher.queries == ["latest swift"])
  }

  @Test func testRegistryExposesWebSearchInEveryPhaseWhenAssigned() throws {
    var settings = AgentRuntimeSettings()
    settings.webSearchAssignment = stubSearchAssignment()

    for phase in AgentPhase.allCases {
      let names = Set(ToolRegistry.tools(for: phase, settings: settings).map { $0.spec.name })
      try #require(names.contains(AgentWebSearchTool.toolName))
    }
  }

  private func stubSearchAssignment() -> CapabilityAssignment {
    CapabilityAssignment(
      provider: .minimaxToken,
      baseURL: URL(string: "https://api.minimax.io/v1")!,
      apiKey: "key",
      model: ""
    )
  }
}

private final class WebSearchRequestRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var captured: [URLRequest] = []
  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return captured
  }

  func record(_ request: URLRequest) {
    lock.lock()
    captured.append(request)
    lock.unlock()
  }
}

private func stubWebSearchJSONTransport(
  recorder: WebSearchRequestRecorder,
  bodyJSON: [String: Any],
  status: Int = 200
) -> DefaultAgentWebSearcher.Transport {
  let body = try! JSONSerialization.data(withJSONObject: bodyJSON)
  return { request in
    recorder.record(request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "1.1", headerFields: nil)!
    return (body, response)
  }
}

private final class StubWebSearcher: AgentWebSearcher, @unchecked Sendable {
  enum Outcome {
    case success(String)
    case failure(AgentExternalServiceError)
  }

  private let lock = NSLock()
  private let result: Outcome
  private(set) var queries: [String] = []

  init(result: Outcome) {
    self.result = result
  }

  func search(query: String, assignment: CapabilityAssignment) async throws -> String {
    record(query)
    switch result {
    case .success(let text): return text
    case .failure(let error): throw error
    }
  }

  private func record(_ query: String) {
    lock.lock()
    defer { lock.unlock() }
    queries.append(query)
  }
}
