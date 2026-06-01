import Foundation

enum AgentExternalServiceError: LocalizedError, Equatable {
  case unsupportedProvider(AgentProviderKind, capability: AgentCapability)
  case requestFailed(status: Int, body: String)
  case apiFailure(statusCode: Int, message: String, traceID: String?)
  case missingContent(String)
  case decodeFailed(String)
  case transportFailed(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedProvider(let provider, let capability):
      return "\(capability.displayName) is not implemented for provider \(provider.displayName)."
    case .requestFailed(let status, let body):
      return "Request failed (HTTP \(status)): \(Self.preview(body))"
    case .apiFailure(let statusCode, let message, let traceID):
      let trace = traceID.map { " Trace-Id: \($0)" } ?? ""
      return "API error \(statusCode): \(message).\(trace)"
    case .missingContent(let detail):
      return "Response did not contain usable content: \(Self.preview(detail))"
    case .decodeFailed(let detail):
      return "Response could not be decoded: \(detail)"
    case .transportFailed(let detail):
      return "Transport failed: \(detail)"
    }
  }

  private static func preview(_ body: String, limit: Int = 240) -> String {
    let collapsed = body.replacingOccurrences(of: "\n", with: " ")
    if collapsed.count <= limit { return collapsed }
    return String(collapsed.prefix(limit)) + "..."
  }
}

protocol AgentWebSearcher: Sendable {
  func search(query: String, assignment: CapabilityAssignment) async throws -> String
}

protocol AgentImageUnderstander: Sendable {
  func understand(
    prompt: String,
    imageDataURL: String,
    assignment: CapabilityAssignment
  ) async throws -> String
}

struct DefaultAgentWebSearcher: AgentWebSearcher {
  typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  let transport: Transport

  init(transport: @escaping Transport = Self.urlSessionTransport) {
    self.transport = transport
  }

  static let urlSessionTransport: Transport = { request in
    try await URLSession.shared.data(for: request)
  }

  func search(query: String, assignment: CapabilityAssignment) async throws -> String {
    switch assignment.provider {
    case .minimaxToken:
      return try await MiniMaxCodingPlanAdapter(transport: transport)
        .webSearch(query: query, assignment: assignment)
    case .appleFoundationModels, .openAI:
      throw AgentExternalServiceError.unsupportedProvider(
        assignment.provider,
        capability: .webSearch
      )
    }
  }
}

struct DefaultAgentImageUnderstander: AgentImageUnderstander {
  typealias Transport = DefaultAgentWebSearcher.Transport

  let transport: Transport

  init(transport: @escaping Transport = DefaultAgentWebSearcher.urlSessionTransport) {
    self.transport = transport
  }

  func understand(
    prompt: String,
    imageDataURL: String,
    assignment: CapabilityAssignment
  ) async throws -> String {
    switch assignment.provider {
    case .minimaxToken:
      return try await MiniMaxCodingPlanAdapter(transport: transport)
        .understandImage(prompt: prompt, imageDataURL: imageDataURL, assignment: assignment)
    case .appleFoundationModels, .openAI:
      throw AgentExternalServiceError.unsupportedProvider(
        assignment.provider,
        capability: .imageUnderstanding
      )
    }
  }
}

struct MiniMaxCodingPlanAdapter: Sendable {
  let transport: DefaultAgentWebSearcher.Transport

  func webSearch(query: String, assignment: CapabilityAssignment) async throws -> String {
    let data = try await postJSON(
      endpoint: ["coding_plan", "search"],
      body: ["q": query],
      assignment: assignment
    )
    return try Self.prettyPrintedJSON(data)
  }

  func understandImage(
    prompt: String,
    imageDataURL: String,
    assignment: CapabilityAssignment
  ) async throws -> String {
    let data = try await postJSON(
      endpoint: ["coding_plan", "vlm"],
      body: [
        "prompt": prompt,
        "image_url": imageDataURL,
      ],
      assignment: assignment
    )
    let parsed = try Self.jsonObject(from: data)
    guard let object = parsed as? [String: Any] else {
      throw AgentExternalServiceError.missingContent(String(decoding: data, as: UTF8.self))
    }
    let content =
      (object["content"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !content.isEmpty else {
      throw AgentExternalServiceError.missingContent(String(decoding: data, as: UTF8.self))
    }
    return content
  }

  private func postJSON(
    endpoint: [String],
    body: [String: Any],
    assignment: CapabilityAssignment
  ) async throws -> Data {
    let url = Self.codingPlanURL(baseURL: assignment.baseURL, endpoint: endpoint)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(assignment.apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("Compass", forHTTPHeaderField: "MM-API-Source")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await transport(request)
    } catch let error as AgentExternalServiceError {
      throw error
    } catch {
      throw AgentExternalServiceError.transportFailed(error.localizedDescription)
    }

    let bodyString = String(decoding: data, as: UTF8.self)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw AgentExternalServiceError.requestFailed(status: http.statusCode, body: bodyString)
    }

    let parsed = try Self.jsonObject(from: data)
    if let object = parsed as? [String: Any],
      let baseResp = object["base_resp"] as? [String: Any],
      let status = Self.intValue(baseResp["status_code"]),
      status != 0
    {
      let message = (baseResp["status_msg"] as? String) ?? "unknown MiniMax API failure"
      let traceID = (response as? HTTPURLResponse)?
        .value(forHTTPHeaderField: "Trace-Id")
      throw AgentExternalServiceError.apiFailure(
        statusCode: status,
        message: message,
        traceID: traceID
      )
    }

    return data
  }

  static func codingPlanURL(baseURL: URL, endpoint: [String]) -> URL {
    var url = baseURL
    let pathParts = url.path.split(separator: "/").map(String.init)
    if pathParts.last != "v1" {
      url.appendPathComponent("v1")
    }
    for component in endpoint {
      url.appendPathComponent(component)
    }
    return url
  }

  private static func prettyPrintedJSON(_ data: Data) throws -> String {
    let object = try jsonObject(from: data)
    let rendered = try JSONSerialization.data(
      withJSONObject: object,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    return String(decoding: rendered, as: UTF8.self)
  }

  private static func jsonObject(from data: Data) throws -> Any {
    do {
      return try JSONSerialization.jsonObject(with: data)
    } catch {
      throw AgentExternalServiceError.decodeFailed(error.localizedDescription)
    }
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let double = value as? Double { return Int(double) }
    if let string = value as? String { return Int(string.trimmingCharacters(in: .whitespaces)) }
    return nil
  }
}
