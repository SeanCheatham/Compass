import Foundation

/// Generate an image from a text prompt and write the bytes to a
/// path under the working directory.
///
/// Constructed with a captured `MediaAssignment` (provider + base
/// URL + API key + model) so the tool's `invoke` does not need a
/// settings reference — `ToolRegistry.tools(for:settings:)` is the
/// place that decides whether to include the tool at all, and what
/// credentials it should run against. When the user has not
/// assigned an Image provider (`AgentRuntimeSettings.imageAssignment
/// == nil`), the tool is simply absent from the agent's palette.
struct AgentGenerateImageTool: AgentTool {
  static let toolName = "generate_image"

  struct Arguments: Codable {
    let prompt: String
    let output_path: String
  }

  let spec: AgentToolSpec
  let assignment: MediaAssignment
  let generator: AgentImageGenerator

  init(
    assignment: MediaAssignment,
    generator: AgentImageGenerator = DefaultAgentImageGenerator()
  ) {
    self.assignment = assignment
    self.generator = generator
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "required": ["prompt", "output_path"],
      "properties": [
        "prompt": [
          "type": "string",
          "description":
            "Description of the image to generate. Be specific about subject, style, lighting, and framing — the model has no context beyond this text.",
        ],
        "output_path": [
          "type": "string",
          "description":
            "Path under the working directory where the image bytes are written. Must end with .png, .jpg, .jpeg, or .webp. Intermediate directories are created automatically.",
        ],
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "Generate an image for the given prompt using the configured Image provider (\(assignment.provider.displayName), model \(assignment.model)) and write the bytes to output_path under the working directory.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure(.invalidArguments(error.localizedDescription))
    }

    let trimmedPrompt = args.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPrompt.isEmpty else {
      return .failure(.invalidArguments("prompt is empty"))
    }

    let url: URL
    do {
      url = try context.resolvePath(args.output_path)
    } catch let error as AgentToolError {
      return .failure(error)
    } catch {
      return .failure(
        .invalidArguments("path resolution failed: \(error.localizedDescription)"))
    }

    let lowered = url.pathExtension.lowercased()
    let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]
    guard allowedExtensions.contains(lowered) else {
      return .failure(
        .invalidArguments(
          "output_path must end with one of .png, .jpg, .jpeg, .webp (got \"\(args.output_path)\")"
        ))
    }

    let bytes: Data
    do {
      bytes = try await generator.generate(prompt: trimmedPrompt, assignment: assignment)
    } catch let error as AgentImageGenerationError {
      return .failure(.ioFailure(error.errorDescription ?? "image generation failed"))
    } catch {
      return .failure(.ioFailure("image generation failed: \(error.localizedDescription)"))
    }

    do {
      try await context.filesystem.writeFile(bytes, at: url)
    } catch let error as AgentFilesystemError {
      switch error {
      case .notRegularFile:
        return .failure(.notRegularFile(args.output_path))
      case .transportFailure(let detail):
        return .failure(.rpcFailure(detail))
      default:
        return .failure(.ioFailure(error.errorDescription ?? "I/O failure"))
      }
    } catch {
      return .failure(.ioFailure("write failed: \(error.localizedDescription)"))
    }

    // Mark the new file as "read" so subsequent edit_file / write_file
    // calls don't reject it. The agent just produced this content,
    // so it definitionally knows what's there.
    await context.readTracker.markRead(url)

    let relative = context.relativize(url)
    return .ok(
      "Generated image (\(bytes.count) bytes) via \(assignment.provider.displayName) and wrote to \(relative)"
    )
  }
}
