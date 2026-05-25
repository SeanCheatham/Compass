import Foundation
import XCTest

@testable import Compass

final class AgentImageGenerationTests: XCTestCase {
  // MARK: - MiniMax adapter

  func testMiniMaxAdapterRequestsImageGenerationEndpoint() async throws {
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
    XCTAssertEqual(bytes, imageBytes)

    let recorded = recorder.requests.first
    XCTAssertEqual(
      recorded?.url?.absoluteString,
      "https://api.minimax.io/v1/image_generation"
    )
    XCTAssertEqual(recorded?.value(forHTTPHeaderField: "Authorization"), "Bearer mm-key")
    let body = try XCTUnwrap(recorded?.httpBody)
    let payload = try XCTUnwrap(
      JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(payload["model"] as? String, "image-01")
    XCTAssertEqual(payload["prompt"] as? String, "neon koi")
    XCTAssertEqual(payload["response_format"] as? String, "base64")
  }

  func testMiniMaxAdapterFollowsImageURLFallback() async throws {
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
    XCTAssertEqual(bytes, imageBytes)
    XCTAssertEqual(recorder.requests.count, 2)
  }

  // MARK: - OpenAI adapter

  func testOpenAIAdapterRequestsImagesGenerationsEndpoint() async throws {
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
    XCTAssertEqual(bytes, imageBytes)
    XCTAssertEqual(
      recorder.requests.first?.url?.absoluteString,
      "https://api.openai.com/v1/images/generations"
    )
    XCTAssertEqual(
      recorder.requests.first?.value(forHTTPHeaderField: "Authorization"),
      "Bearer sk-test")
  }

  // MARK: - Failure surfaces

  func testNon2xxResponseSurfaceAsRequestFailed() async {
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
      XCTFail("expected requestFailed")
    } catch let error as AgentImageGenerationError {
      switch error {
      case .requestFailed(let status, _):
        XCTAssertEqual(status, 401)
      default:
        XCTFail("expected .requestFailed, got \(error)")
      }
    } catch {
      XCTFail("expected AgentImageGenerationError, got \(error)")
    }
  }

  func testFoundationModelsProviderIsExplicitlyUnsupported() async {
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
      XCTFail("expected unsupportedProvider")
    } catch let error as AgentImageGenerationError {
      switch error {
      case .unsupportedProvider(let kind):
        XCTAssertEqual(kind, .appleFoundationModels)
      default:
        XCTFail("expected .unsupportedProvider, got \(error)")
      }
    } catch {
      XCTFail("expected AgentImageGenerationError, got \(error)")
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
