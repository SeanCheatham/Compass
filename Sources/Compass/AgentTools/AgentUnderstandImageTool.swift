import Foundation

struct AgentUnderstandImageTool: AgentTool {
  static let toolName = "image_understanding"
  static let maxImageBytes = 20 * 1_024 * 1_024

  typealias ImageURLFetcher = @Sendable (URL) async throws -> (Data, String?)

  struct Arguments: Decodable {
    let prompt: String
    let imageSource: String

    enum CodingKeys: String, CodingKey {
      case prompt
      case question
      case instruction
      case imageSource = "image_source"
      case imageSourceCamel = "imageSource"
      case imagePath = "image_path"
      case imagePathCamel = "imagePath"
      case path
      case filePath = "file_path"
      case filePathCamel = "filePath"
      case url
      case imageURL = "image_url"
      case imageURLCamel = "imageUrl"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      prompt = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .prompt,
        aliases: [.question, .instruction],
        fieldName: "prompt"
      )
      imageSource = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .imageSource,
        aliases: [
          .imageSourceCamel, .imagePath, .imagePathCamel, .path, .filePath,
          .filePathCamel, .url, .imageURL, .imageURLCamel,
        ],
        fieldName: "image_source"
      )
    }
  }

  let spec: AgentToolSpec
  let assignment: CapabilityAssignment
  let understander: AgentImageUnderstander
  let fetchImageURL: ImageURLFetcher

  init(
    assignment: CapabilityAssignment,
    understander: AgentImageUnderstander = DefaultAgentImageUnderstander(),
    fetchImageURL: @escaping ImageURLFetcher = Self.defaultFetchImageURL
  ) {
    self.assignment = assignment
    self.understander = understander
    self.fetchImageURL = fetchImageURL
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["prompt", "image_source"],
      "properties": [
        "prompt": [
          "type": "string",
          "description":
            "Question or instruction describing what to inspect, extract, compare, or explain in the image.",
        ],
        "image_source": [
          "type": "string",
          "description":
            "Image path under the working directory, HTTPS URL, or data URL. Local paths may be relative or absolute but must resolve inside the working directory. Supported formats: PNG, JPEG, WebP.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Analyze an image using the configured Image Understanding provider (\(assignment.provider.displayName)). Accepts a workspace image path, HTTPS URL, or data URL and returns the provider's textual analysis.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }

    let prompt = args.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else {
      return .failure(.invalidArguments("prompt is empty"))
    }
    guard !assignment.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .failure(.invalidArguments("Image Understanding provider API key is missing"))
    }

    let imageDataURL: String
    do {
      imageDataURL = try await dataURL(for: args.imageSource, context: context)
    } catch let error as AgentToolError {
      return .failure(error)
    } catch {
      return .failure(.invalidArguments(error.localizedDescription))
    }

    do {
      let result = try await understander.understand(
        prompt: prompt,
        imageDataURL: imageDataURL,
        assignment: assignment
      )
      return .ok(result)
    } catch let error as AgentExternalServiceError {
      return .failure(.ioFailure(error.errorDescription ?? "image understanding failed"))
    } catch {
      return .failure(.ioFailure("image understanding failed: \(error.localizedDescription)"))
    }
  }

  private func dataURL(for rawSource: String, context: AgentToolContext) async throws -> String {
    var source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty else {
      throw AgentToolError.invalidArguments("image_source is empty")
    }
    if source.hasPrefix("@") {
      source.removeFirst()
      source = source.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if source.lowercased().hasPrefix("data:image/") {
      return source
    }
    if let url = URL(string: source),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    {
      let (data, contentType) = try await fetchImageURL(url)
      return try Self.dataURL(
        data: data, contentType: contentType, pathExtension: url.pathExtension)
    }

    let url = try context.resolvePath(source)
    let data: Data
    do {
      data = try await context.filesystem.readFile(at: url)
    } catch let error as AgentFilesystemError {
      switch error {
      case .notFound:
        throw AgentToolError.fileNotFound(source)
      case .notRegularFile:
        throw AgentToolError.notRegularFile(source)
      case .transportFailure(let detail):
        throw AgentToolError.rpcFailure(detail)
      default:
        throw AgentToolError.ioFailure(error.errorDescription ?? "I/O failure")
      }
    }
    await context.readTracker.markRead(url)
    return try Self.dataURL(data: data, contentType: nil, pathExtension: url.pathExtension)
  }

  static let defaultFetchImageURL: ImageURLFetcher = { url in
    let (data, response) = try await URLSession.shared.data(from: url)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw AgentToolError.ioFailure("image download failed with HTTP \(http.statusCode)")
    }
    return (data, (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"))
  }

  static func dataURL(
    data: Data,
    contentType: String?,
    pathExtension: String
  ) throws -> String {
    guard data.count <= maxImageBytes else {
      throw AgentToolError.invalidArguments(
        "image is too large (\(data.count) bytes; max \(maxImageBytes))"
      )
    }
    guard
      let mime = imageMIMEType(
        data: data,
        contentType: contentType,
        pathExtension: pathExtension
      )
    else {
      throw AgentToolError.invalidArguments("unsupported image format; use PNG, JPEG, or WebP")
    }
    return "data:\(mime);base64,\(data.base64EncodedString())"
  }

  static func imageMIMEType(
    data: Data,
    contentType: String?,
    pathExtension: String
  ) -> String? {
    if let contentType {
      let lowered = contentType.lowercased()
      if lowered.contains("image/png") { return "image/png" }
      if lowered.contains("image/jpeg") || lowered.contains("image/jpg") {
        return "image/jpeg"
      }
      if lowered.contains("image/webp") { return "image/webp" }
    }

    switch pathExtension.lowercased() {
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "webp": return "image/webp"
    default: break
    }

    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
      return "image/png"
    }
    if data.starts(with: [0xFF, 0xD8, 0xFF]) {
      return "image/jpeg"
    }
    if data.count >= 12,
      data[0..<4] == Data("RIFF".utf8),
      data[8..<12] == Data("WEBP".utf8)
    {
      return "image/webp"
    }
    return nil
  }
}
