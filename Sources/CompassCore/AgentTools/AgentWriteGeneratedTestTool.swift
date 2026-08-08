import Foundation

/// Confined write tool for health bug-hunt: only `tests/compass_gen_*.rs`.
public struct AgentWriteGeneratedTestTool: AgentTool {
  public static let toolName = "write_generated_test"

  public struct Arguments: Decodable {
    public let path: String
    public let content: String

    public enum CodingKeys: String, CodingKey {
      case path
      case filePath
      case filePathSnake = "file_path"
      case file
      case filename
      case content
      case contents
      case text
      case body
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .path,
        aliases: [.filePath, .filePathSnake, .file, .filename],
        fieldName: "path"
      )
      content = try FlexibleModelDecoder.decodeRequiredString(
        from: container,
        preferredKey: .content,
        aliases: [.contents, .text, .body],
        fieldName: "content"
      )
    }
  }

  public let spec: AgentToolSpec

  public init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["path", "content"],
      "properties": [
        "path": [
          "type": "string",
          "description":
            "Filename or path under tests/. Must become tests/compass_gen_*.rs. Production sources are refused.",
        ],
        "content": [
          "type": "string",
          "description": "Full UTF-8 contents of the generated integration test file.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Create or overwrite a health-generated integration test under tests/compass_gen_*.rs only. Do not edit production sources.",
      parameters: schema
    )
  }

  public func invoke(arguments: Data, context: AgentToolContext) async throws
    -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(agentToolDecodingErrorDescription(error)))
    }

    let fileName = HealthPaths.normalizeGeneratedTestFileName(args.path)
    let relativePath = "\(HealthPaths.generatedTestsDirectory)/\(fileName)"

    let url: URL
    do {
      url = try context.resolvePath(relativePath)
    } catch let error as AgentToolError {
      return .failure(error)
    } catch {
      return .failure(.invalidArguments("path resolution failed: \(error.localizedDescription)"))
    }

    let testsRoot = context.workingDirectory
      .appending(path: HealthPaths.generatedTestsDirectory)
      .standardizedFileURL.path
    let resolvedPath = url.standardizedFileURL.path
    guard resolvedPath == testsRoot || resolvedPath.hasPrefix(testsRoot + "/") else {
      return .failure(
        .invalidArguments(
          "Refused: health bug hunt may only write under \(HealthPaths.generatedTestsDirectory)/\(HealthPaths.generatedTestPrefix)*.rs."
        ))
    }
    guard HealthPaths.isGeneratedTestFileName(url.lastPathComponent) else {
      return .failure(
        .invalidArguments(
          "Refused: filename must be \(HealthPaths.generatedTestPrefix)*.rs."
        ))
    }

    let data = Data(args.content.utf8)
    do {
      try await context.filesystem.writeFile(data, at: url)
    } catch let error as AgentFilesystemError {
      switch error {
      case .notRegularFile:
        return .failure(.notRegularFile(relativePath))
      case .transportFailure(let detail):
        return .failure(.rpcFailure(detail))
      default:
        return .failure(.ioFailure(error.errorDescription ?? "I/O failure"))
      }
    } catch {
      return .failure(.ioFailure("write failed: \(error.localizedDescription)"))
    }

    await context.readTracker.markRead(url)
    return .ok("wrote \(relativePath) (\(data.count) bytes)")
  }
}
