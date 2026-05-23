import Foundation

/// JSON schema for tool parameters, stored as JSON-encoded bytes so it can
/// safely cross actor boundaries and be re-emitted into any OpenAI-compatible
/// tool-calling envelope without round-tripping through `[String: Any]`.
struct AgentToolParametersSchema: Sendable, Equatable {
  let json: Data

  init(json: Data) {
    self.json = json
  }

  init(_ object: Any) throws {
    self.json = try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys, .withoutEscapingSlashes]
    )
  }
}

struct AgentToolSpec: Sendable, Equatable {
  let name: String
  let description: String
  let parameters: AgentToolParametersSchema
}

struct AgentToolInvocationResult: Sendable, Equatable {
  var content: String
  var isError: Bool

  static func ok(_ content: String) -> Self {
    .init(content: content, isError: false)
  }

  static func failure(_ message: String) -> Self {
    .init(content: message, isError: true)
  }
}

/// Execution context handed to a tool at invocation time. The working
/// directory is the root the tool must scope itself to — any path that
/// escapes it is rejected. The filesystem picks how file ops are served
/// (host `FileManager` vs. SSH into the Shared VM); the bash runner picks
/// how shell commands are dispatched (host shell vs. SSH).
struct AgentToolContext: Sendable {
  var workingDirectory: URL
  var filesystem: AgentFilesystem
  var bashRunner: AgentBashRunner

  init(
    workingDirectory: URL,
    filesystem: AgentFilesystem = AgentHostFilesystem(),
    bashRunner: AgentBashRunner = AgentHostBashRunner()
  ) {
    self.workingDirectory = workingDirectory.standardizedFileURL
    self.filesystem = filesystem
    self.bashRunner = bashRunner
  }
}

protocol AgentTool: Sendable {
  var spec: AgentToolSpec { get }
  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
}

enum AgentToolError: LocalizedError, Equatable {
  case invalidArguments(String)
  case pathEscapesWorkingDirectory(String)
  case fileNotFound(String)
  case notRegularFile(String)
  case notDirectory(String)
  case binaryFile(String)
  case ioFailure(String)

  var errorDescription: String? {
    switch self {
    case .invalidArguments(let detail): return "Invalid arguments: \(detail)"
    case .pathEscapesWorkingDirectory(let path):
      return "Path escapes the working directory: \(path)"
    case .fileNotFound(let path): return "File not found: \(path)"
    case .notRegularFile(let path): return "Not a regular file: \(path)"
    case .notDirectory(let path): return "Not a directory: \(path)"
    case .binaryFile(let path): return "Cannot read binary file: \(path)"
    case .ioFailure(let detail): return "I/O failure: \(detail)"
    }
  }
}

extension AgentToolContext {
  /// Resolve a possibly-relative path against the working directory. Paths
  /// that resolve outside the working directory are rejected so a buggy or
  /// adversarial tool call can't read `/etc/passwd` from a sandbox-style
  /// Plan/Reflect pass.
  func resolvePath(_ raw: String) throws -> URL {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw AgentToolError.invalidArguments("path is empty")
    }
    let candidate: URL
    if trimmed.hasPrefix("/") {
      candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
    } else {
      candidate = workingDirectory.appendingPathComponent(trimmed).standardizedFileURL
    }
    let root = workingDirectory.standardizedFileURL
    let rootPath = root.path
    let candidatePath = candidate.path
    guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
      throw AgentToolError.pathEscapesWorkingDirectory(raw)
    }
    return candidate
  }

  /// Convert an absolute URL back to a path relative to the working
  /// directory. Used by tools that report match results so the model sees
  /// short paths instead of `/Users/...` prefixes that change per machine.
  func relativize(_ url: URL) -> String {
    let workingPath = workingDirectory.standardizedFileURL.path
    let absolutePath = url.standardizedFileURL.path
    if absolutePath == workingPath { return "." }
    if absolutePath.hasPrefix(workingPath + "/") {
      return String(absolutePath.dropFirst(workingPath.count + 1))
    }
    return absolutePath
  }
}
