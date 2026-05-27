import Foundation
import Testing

@testable import Compass

struct AgentImageGenerationTests {
  // MARK: - MiniMax adapter

  @Test func testMiniMaxAdapterRequestsImageGenerationEndpoint() async throws {
    let imageBytes = Data((0..<48).map { UInt8($0) })
    let recorder = RequestRecorder()
    let transport = stubJSONTransport(
      recorder: recorder,
      bodyJSON: [
        "data": [
          "image_base64": [imageBytes.base64EncodedString()]
        ]
      ]
    )
    let generator = DefaultAgentImageGenerator(transport: transport)

    let bytes = try await generator.generate(
      prompt: "neon koi",
      assignment: MediaAssignment(
        provider: .minimaxToken,
        baseURL: URL(string: "https://api.minimax.io/v1")!,
        apiKey: "mm-key",
        model: "image-01"
      )
    )
    #require(bytes == imageBytes)

    let recorded = recorder.requests.first
    #require(
      recorded?.url?.absoluteString ==
      "https://api.minimax.io/v1/image_generation"
    )
    #require(recorded?.value(forHTTPHeaderField: "Authorization") == "Bearer mm-key")
    let body = #require(recorder.requests.first?.httpBody)
    let payload = #require(
      JSONSerialization.jsonObject(with: body) as? [String: Any])
    #require(payload["model"] as? String == "image-01")
    #require(payload["prompt"] as? String == "neon koi")
    #require(payload["response_format"] as? String == "base64")
  }

  @Test func testMiniMaxAdapterFollowsImageURLFallback() async throws {
    let imageBytes = Data((0..<16).map { UInt8($0 + 64) })
    let recorder = RequestRecorder()
    var responses: [URL: (Data, Int)] = [:]
    responses[URL(string: "https://api.minimax.io/v1/image_generation")!] = (
      try JSONSerialization.data(withJSONObject: [
        "data": [
          "image_urls": ["https://cdn.example/image.png"]
        ]
      ]),
      200
    )
    responses[URL(string: "https://cdn.example/image.png")!] = (imageBytes, 200)

    let transport = stubMultiURLTransport(recorder: recorder, responses: responses)
    let bytes = try await DefaultAgentImageGenerator(transport: transport).generate(
      prompt: "p",
      assignment: MediaAssignment(
        provider: .minimaxToken,
        baseURL: URL(string: "https://api.minimax.io/v1")!,
        apiKey: "k",
        model: "image-01"
      )
    )
    #require(bytes == imageBytes)
    #require(recorder.requests.count == 2)
  }

  // MARK: - OpenAI adapter

  @Test func testOpenAIAdapterRequestsImagesGenerationsEndpoint() async throws {
    let imageBytes = Data("PNG bytes".utf8)
    let recorder = RequestRecorder()
    let transport = stubJSONTransport(
      recorder: recorder,
      bodyJSON: [
        "data": [
          ["b64_json": imageBytes.base64EncodedString()]
        ]
      ]
    )
    let bytes = try await DefaultAgentImageGenerator(transport: transport).generate(
      prompt: "blueprint diagram",
      assignment: MediaAssignment(
        provider: .openAI,
        baseURL: URL(string: "https://api.openai.com/v1")!,
        apiKey: "sk-test",
        model: "gpt-image-1"
      )
    )
    #require(bytes == imageBytes)
    #require(
      recorder.requests.first?.url?.absoluteString ==
      "https://api.openai.com/v1/images/generations"
    )
    #require(
      recorder.requests.first?.value(forHTTPHeaderField: "Authorization") ==
      "Bearer sk-test")
  }

  // MARK: - Failure surfaces

  @Test func testNon2xxResponseSurfaceAsRequestFailed() async {
    let transport: DefaultAgentImageGenerator.Transport = { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 401, httpVersion: "1.1", headerFields: nil)!
      return (Data(#"{"error": "unauthorized"}"#.utf8), response)
    }
    do {
      _ = try await DefaultAgentImageGenerator(transport: transport).generate(
        prompt: "p",
        assignment: MediaAssignment(
          provider: .minimaxToken,
          baseURL: URL(string: "https://api.minimax.io/v1")!,
          apiKey: "bad",
          model: "image-01"
        )
      )
      #require(false, "expected requestFailed")
    } catch let error as AgentImageGenerationError {
      switch error {
      case .requestFailed(let status, _):
        #require(status == 401)
      default:
        #require(false, "expected .requestFailed, got \(error)")
      }
    } catch {
      #require(false, "expected AgentImageGenerationError, got \(error)")
    }
  }

  @Test func testFoundationModelsProviderIsExplicitlyUnsupported() async {
    do {
      _ = try await DefaultAgentImageGenerator().generate(
        prompt: "p",
        assignment: MediaAssignment(
          provider: .appleFoundationModels,
          baseURL: URL(fileURLWithPath: "/dev/null"),
          apiKey: "",
          model: ""
        )
      )
      #require(false, "expected unsupportedProvider")
    } catch let error as AgentImageGenerationError {
      switch error {
      case .unsupportedProvider(let kind):
        #require(kind == .appleFoundationModels)
      default:
        #require(false, "expected .unsupportedProvider, got \(error)")
      }
    } catch {
      #require(false, "expected AgentImageGenerationError, got \(error)")
    }
  }
}

// MARK: - Transport stubs

private final class RequestRecorder: @unchecked Sendable {
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

private func stubJSONTransport(
  recorder: RequestRecorder,
  bodyJSON: [String: Any],
  status: Int = 200
) -> DefaultAgentImageGenerator.Transport {
  let body = try! JSONSerialization.data(withJSONObject: bodyJSON)
  return { request in
    recorder.record(request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "1.1", headerFields: nil)!
    return (body, response)
  }
}

private func stubMultiURLTransport(
  recorder: RequestRecorder,
  responses: [URL: (Data, Int)]
) -> DefaultAgentImageGenerator.Transport {
  return { request in
    recorder.record(request)
    guard let url = request.url, let (data, status) = responses[url] else {
      throw URLError(.unsupportedURL)
    }
    let response = HTTPURLResponse(
      url: url, statusCode: status, httpVersion: "1.1", headerFields: nil)!
    return (data, response)
  }
}