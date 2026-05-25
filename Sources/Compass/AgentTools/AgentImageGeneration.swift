import Foundation

/// Generates an image for a text prompt using a configured
/// `MediaAssignment`. The adapter abstracts away the per-vendor
/// quirks (path under the base URL, request body keys, response
/// unwrapping) so the tool layer stays a thin glue: dispatch on
/// `MediaAssignment.provider`, run the adapter, write bytes.
///
/// Implementations are intentionally narrow — Compass only needs to
/// turn (prompt, model, credentials) → image bytes. Anything richer
/// (size, seed, negative prompts) can be added as the tool's surface
/// grows; for now we keep the agent-facing schema small.
protocol AgentImageGenerator: Sendable {
  func generate(
    prompt: String,
    assignment: MediaAssignment
  ) async throws -> Data
}

enum AgentImageGenerationError: LocalizedError, Equatable {
  case unsupportedProvider(AgentProviderKind)
  case requestFailed(status: Int, body: String)
  case missingImageInResponse(body: String)
  case decodeFailed(String)
  case transportFailed(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedProvider(let kind):
      return "Image generation is not implemented for provider \(kind.displayName)."
    case .requestFailed(let status, let body):
      return "Image generation request failed (HTTP \(status)): \(Self.preview(body))"
    case .missingImageInResponse(let body):
      return "Image generation response did not contain image bytes: \(Self.preview(body))"
    case .decodeFailed(let detail):
      return "Image generation response could not be decoded: \(detail)"
    case .transportFailed(let detail):
      return "Image generation transport failed: \(detail)"
    }
  }

  private static func preview(_ body: String, limit: Int = 200) -> String {
    let collapsed = body.replacingOccurrences(of: "\n", with: " ")
    if collapsed.count <= limit { return collapsed }
    return String(collapsed.prefix(limit)) + "…"
  }
}

/// Vendor-dispatch image generator. Picks the per-provider adapter
/// based on `MediaAssignment.provider`, lets it shape the HTTP
/// request, and returns the decoded image bytes. The HTTP transport
/// is captured behind a closure (`urlSessionData`) so tests can
/// substitute a canned response without standing up a real network
/// stack.
struct DefaultAgentImageGenerator: AgentImageGenerator {
  /// Closure form of `URLSession.shared.data(for:)`. Injected so
  /// tests can hand back canned `(Data, URLResponse)` pairs.
  typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  let transport: Transport

  init(transport: @escaping Transport = Self.urlSessionTransport) {
    self.transport = transport
  }

  static let urlSessionTransport: Transport = { request in
    try await URLSession.shared.data(for: request)
  }

  func generate(prompt: String, assignment: MediaAssignment) async throws -> Data {
    switch assignment.provider {
    case .minimaxToken:
      return try await MiniMaxImageAdapter(transport: transport)
        .generate(prompt: prompt, assignment: assignment)
    case .openAI:
      return try await OpenAIImageAdapter(transport: transport)
        .generate(prompt: prompt, assignment: assignment)
    case .appleFoundationModels:
      throw AgentImageGenerationError.unsupportedProvider(.appleFoundationModels)
    }
  }
}

// MARK: - Adapters

/// MiniMax's image API lives at `<baseURL>/image_generation` and
/// returns either URLs or base64 strings under a `data` envelope.
/// We always request base64 so the tool ends in one round trip;
/// fall through to URL-fetch when MiniMax decides to ignore the
/// `response_format` field (some images come back as URLs even when
/// base64 was requested).
struct MiniMaxImageAdapter: AgentImageGenerator {
  let transport: DefaultAgentImageGenerator.Transport

  func generate(prompt: String, assignment: MediaAssignment) async throws -> Data {
    let url = assignment.baseURL.appendingPathComponent("image_generation")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(assignment.apiKey)", forHTTPHeaderField: "Authorization")
    let body: [String: Any] = [
      "model": assignment.model,
      "prompt": prompt,
      "n": 1,
      "response_format": "base64",
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return try await Self.runAndExtract(transport: transport, request: request)
  }

  static func runAndExtract(
    transport: DefaultAgentImageGenerator.Transport,
    request: URLRequest
  ) async throws -> Data {
    let (data, response) = try await safelyPerform(transport: transport, request: request)
    let bodyString = String(decoding: data, as: UTF8.self)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw AgentImageGenerationError.requestFailed(
        status: http.statusCode,
        body: bodyString
      )
    }
    let parsed: Any
    do {
      parsed = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw AgentImageGenerationError.decodeFailed(error.localizedDescription)
    }
    guard let object = parsed as? [String: Any] else {
      throw AgentImageGenerationError.missingImageInResponse(body: bodyString)
    }
    if let payload = object["data"] as? [String: Any] {
      if let b64 = (payload["image_base64"] as? [String])?.first,
        let bytes = Data(base64Encoded: b64)
      {
        return bytes
      }
      if let urlString = (payload["image_urls"] as? [String])?.first,
        let imageURL = URL(string: urlString)
      {
        return try await fetch(transport: transport, url: imageURL)
      }
    }
    throw AgentImageGenerationError.missingImageInResponse(body: bodyString)
  }
}

/// OpenAI's image API (`<baseURL>/images/generations`) returns a
/// `data` array of objects carrying either `b64_json` or `url`. We
/// request `b64_json` for newer models that support the parameter;
/// for `gpt-image-1` (which forces base64), the field is present
/// regardless. URL fallback handles older `dall-e-3` paths.
struct OpenAIImageAdapter: AgentImageGenerator {
  let transport: DefaultAgentImageGenerator.Transport

  func generate(prompt: String, assignment: MediaAssignment) async throws -> Data {
    let url = assignment.baseURL.appendingPathComponent("images/generations")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(assignment.apiKey)", forHTTPHeaderField: "Authorization")
    let body: [String: Any] = [
      "model": assignment.model,
      "prompt": prompt,
      "n": 1,
      "response_format": "b64_json",
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await safelyPerform(transport: transport, request: request)
    let bodyString = String(decoding: data, as: UTF8.self)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw AgentImageGenerationError.requestFailed(
        status: http.statusCode,
        body: bodyString
      )
    }
    let parsed: Any
    do {
      parsed = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw AgentImageGenerationError.decodeFailed(error.localizedDescription)
    }
    guard let object = parsed as? [String: Any],
      let items = object["data"] as? [[String: Any]],
      let first = items.first
    else {
      throw AgentImageGenerationError.missingImageInResponse(body: bodyString)
    }
    if let b64 = first["b64_json"] as? String, let bytes = Data(base64Encoded: b64) {
      return bytes
    }
    if let urlString = first["url"] as? String, let imageURL = URL(string: urlString) {
      return try await fetch(transport: transport, url: imageURL)
    }
    throw AgentImageGenerationError.missingImageInResponse(body: bodyString)
  }
}

// MARK: - Shared helpers

private func safelyPerform(
  transport: DefaultAgentImageGenerator.Transport,
  request: URLRequest
) async throws -> (Data, URLResponse) {
  do {
    return try await transport(request)
  } catch let error as AgentImageGenerationError {
    throw error
  } catch {
    throw AgentImageGenerationError.transportFailed(error.localizedDescription)
  }
}

private func fetch(
  transport: DefaultAgentImageGenerator.Transport,
  url: URL
) async throws -> Data {
  let (data, response) = try await safelyPerform(
    transport: transport,
    request: URLRequest(url: url)
  )
  if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
    throw AgentImageGenerationError.requestFailed(
      status: http.statusCode,
      body: String(decoding: data, as: UTF8.self)
    )
  }
  return data
}
