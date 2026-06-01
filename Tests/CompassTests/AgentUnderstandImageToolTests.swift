import Foundation
import Testing

@testable import Compass

struct AgentUnderstandImageToolTests: ~Copyable {
  private var workingDirectory: URL!
  private var filesystem: AgentHostFilesystem!

  init() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "compass-understand-image-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    workingDirectory = base.standardizedFileURL
    filesystem = AgentHostFilesystem()
  }

  deinit {
    if let workingDirectory {
      try? FileManager.default.removeItem(at: workingDirectory)
    }
  }

  @Test func testMiniMaxImageUnderstandingAdapterUsesVLMEndpoint() async throws {
    let recorder = ImageUnderstandingRequestRecorder()
    let transport = stubImageUnderstandingJSONTransport(
      recorder: recorder,
      bodyJSON: [
        "content": "The screenshot shows a settings panel.",
        "base_resp": [
          "status_code": 0,
          "status_msg": "success",
        ],
      ]
    )

    let output = try await DefaultAgentImageUnderstander(transport: transport).understand(
      prompt: "What is shown?",
      imageDataURL: "data:image/png;base64,AAAA",
      assignment: stubVisionAssignment()
    )

    try #require(output == "The screenshot shows a settings panel.")
    let request = try #require(recorder.requests.first)
    try #require(
      request.url?.absoluteString == "https://api.minimax.io/v1/coding_plan/vlm"
    )
    let body = try #require(request.httpBody)
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    try #require(payload["prompt"] as? String == "What is shown?")
    try #require(payload["image_url"] as? String == "data:image/png;base64,AAAA")
  }

  @Test func testToolReadsWorkspaceImageAndInvokesUnderstander() async throws {
    let imageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
    let imageURL = workingDirectory.appendingPathComponent("screens/settings.png")
    try FileManager.default.createDirectory(
      at: imageURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try imageBytes.write(to: imageURL)

    let understander = StubImageUnderstander(result: .success("looks good"))
    let tool = AgentUnderstandImageTool(
      assignment: stubVisionAssignment(),
      understander: understander
    )
    let context = AgentToolContext(workingDirectory: workingDirectory, filesystem: filesystem)

    let result = try await tool.invoke(
      arguments: Data(
        #"{"prompt": "Read the screenshot", "image_path": "screens/settings.png"}"#.utf8),
      context: context
    )

    try #require(!result.isError, "tool reported failure: \(result.content)")
    try #require(result.content == "looks good")
    try #require(understander.prompts == ["Read the screenshot"])
    let dataURL = try #require(understander.imageDataURLs.first)
    try #require(dataURL.hasPrefix("data:image/png;base64,"))
  }

  @Test func testToolRejectsUnsupportedLocalImageFormat() async throws {
    let dataURL = workingDirectory.appendingPathComponent("bad.bmp")
    try Data("not really an image".utf8).write(to: dataURL)
    let tool = AgentUnderstandImageTool(
      assignment: stubVisionAssignment(),
      understander: StubImageUnderstander(result: .success("unused"))
    )
    let context = AgentToolContext(workingDirectory: workingDirectory, filesystem: filesystem)

    let result = try await tool.invoke(
      arguments: Data(#"{"prompt": "what", "image_source": "bad.bmp"}"#.utf8),
      context: context
    )

    try #require(result.isError)
    try #require(result.errorKind == .invalidArguments)
  }

  @Test func testRegistryExposesImageUnderstandingInEveryPhaseWhenAssigned() throws {
    var settings = AgentRuntimeSettings()
    settings.imageUnderstandingAssignment = stubVisionAssignment()

    for phase in AgentPhase.allCases {
      let names = Set(ToolRegistry.tools(for: phase, settings: settings).map { $0.spec.name })
      try #require(names.contains(AgentUnderstandImageTool.toolName))
    }
  }

  private func stubVisionAssignment() -> CapabilityAssignment {
    CapabilityAssignment(
      provider: .minimaxToken,
      baseURL: URL(string: "https://api.minimax.io/v1")!,
      apiKey: "key",
      model: ""
    )
  }
}

private final class ImageUnderstandingRequestRecorder: @unchecked Sendable {
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

private func stubImageUnderstandingJSONTransport(
  recorder: ImageUnderstandingRequestRecorder,
  bodyJSON: [String: Any],
  status: Int = 200
) -> DefaultAgentImageUnderstander.Transport {
  let body = try! JSONSerialization.data(withJSONObject: bodyJSON)
  return { request in
    recorder.record(request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "1.1", headerFields: nil)!
    return (body, response)
  }
}

private final class StubImageUnderstander: AgentImageUnderstander, @unchecked Sendable {
  enum Outcome {
    case success(String)
    case failure(AgentExternalServiceError)
  }

  private let lock = NSLock()
  private let result: Outcome
  private(set) var prompts: [String] = []
  private(set) var imageDataURLs: [String] = []

  init(result: Outcome) {
    self.result = result
  }

  func understand(
    prompt: String,
    imageDataURL: String,
    assignment: CapabilityAssignment
  ) async throws -> String {
    record(prompt: prompt, imageDataURL: imageDataURL)
    switch result {
    case .success(let text): return text
    case .failure(let error): throw error
    }
  }

  private func record(prompt: String, imageDataURL: String) {
    lock.lock()
    defer { lock.unlock() }
    prompts.append(prompt)
    imageDataURLs.append(imageDataURL)
  }
}
