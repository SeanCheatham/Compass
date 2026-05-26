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

  /// Builds a schema from a static JSON object literal. Invalid literals
  /// are a programmer error and trap at initialization time.
  init(literal object: Any) {
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
      )
    else {
      fatalError("Invalid static AgentToolParametersSchema literal")
    }
    self.json = data
  }
}

struct AgentToolSpec: Sendable, Equatable {
  let name: String
  let description: String
  let parameters: AgentToolParametersSchema
}

/// Categorical bucket for tool failures. Surfaced alongside the
/// human-readable failure message so the executor (retry decisions),
/// UI (icons / grouping), and tests can branch on the *kind* of
/// failure without parsing strings.
///
/// Existing call sites that pass only a message keep working — `kind`
/// defaults to `nil`. New code should prefer the typed
/// `.failure(AgentToolError)` overload, which derives the kind for
/// free.
enum AgentToolErrorKind: String, Sendable, Equatable, Codable {
  /// Tool arguments JSON missing required fields or wrong types.
  case invalidArguments
  /// Path resolution escaped the working directory.
  case pathEscape
  /// File / directory the agent referenced does not exist.
  case fileNotFound
  /// Path exists but is not a regular file.
  case notRegularFile
  /// Path exists but is not a directory.
  case notDirectory
  /// File is binary / not safe to treat as text.
  case binaryFile
  /// Mutation attempted against a file the agent has not freshly
  /// read in this run (`AgentReadTracker` rejected the edit).
  case readNotTracked
  /// `edit_file` find/replace did not match the expected oldString.
  case editConflict
  /// Underlying I/O failed (permission denied, disk error, ...).
  case ioFailure
  /// RPC to the guest VM failed (vsock, framing, decode).
  case rpcFailure
  /// Bash command failed with a non-zero exit.
  case bashFailure
  /// Sub-agent delegation failed before producing a result.
  case delegateFailure
  /// Catch-all for unclassified errors thrown out of a tool.
  case unknown
}

struct AgentToolInvocationResult: Sendable, Equatable {
  var content: String
  var isError: Bool
  /// Optional categorical kind for failure results. Always `nil` for
  /// success results. Pre-existing string-based failure sites keep
  /// returning `nil` until migrated; new sites should use the typed
  /// `.failure(AgentToolError)` overload.
  var errorKind: AgentToolErrorKind?

  static func ok(_ content: String) -> Self {
    .init(content: content, isError: false, errorKind: nil)
  }

  static func failure(_ message: String, kind: AgentToolErrorKind? = nil) -> Self {
    .init(content: message, isError: true, errorKind: kind)
  }

  /// Typed failure: maps the tool-level error to its categorical
  /// kind and uses the localized description as the message.
  static func failure(_ error: AgentToolError) -> Self {
    .init(
      content: error.errorDescription ?? "Tool error",
      isError: true,
      errorKind: error.kind
    )
  }
}

/// Tracks which file paths have been freshly read during an agent execution.
/// `edit_file` and `write_file` (when overwriting) consult this to refuse
/// edits against contents the model has not actually seen — so a hallucinated
/// `oldString` or a stomped existing file gets caught early instead of
/// silently corrupting state.
actor AgentReadTracker {
  private var readPaths: Set<String> = []

  func markRead(_ url: URL) {
    readPaths.insert(url.standardizedFileURL.path)
  }

  func wasRead(_ url: URL) -> Bool {
    readPaths.contains(url.standardizedFileURL.path)
  }
}

/// Execution context handed to a tool at invocation time. The working
/// directory is the root the tool must scope itself to — any path that
/// escapes it is rejected. The filesystem picks how file ops are served
/// (host `FileManager` vs. SSH into the Shared VM); the bash runner picks
/// how shell commands are dispatched (host shell vs. SSH). The read tracker
/// is shared across every tool call in one execution so the mutation tools
/// can require a prior `read_file`.
struct AgentToolContext: Sendable {
  var workingDirectory: URL
  var filesystem: AgentFilesystem
  var bashRunner: AgentBashRunner
  var readTracker: AgentReadTracker
  /// Sub-agent runner used by `AgentDelegateTool`. Nil when the host
  /// doesn't expose delegation (sub-agents themselves, or unit tests
  /// that don't need the feature). The tool surfaces this as a clean
  /// failure result rather than crashing the turn.
  var delegateRunner: AgentDelegateRunner?
  /// Directory the codemap-backed tools read entries from. The codemap
  /// is built host-side at `<workspace.compassURL>/codemap/`, but when
  /// the agent runs in the Shared VM, `workingDirectory` is the guest
  /// worktree — which doesn't (and shouldn't) have its own codemap. The
  /// caller threads the host-side store path through here so
  /// `list_files`, `find_symbol`, `outline`, `summary`, and
  /// `importers_of` keep finding entries regardless of route. Defaults
  /// to `<workingDirectory>/.compass/codemap` so on-host tests and
  /// stand-alone tool invocations work without configuration.
  var codemapStoreDirectory: URL
  /// Completed plan summaries from host-side state.json. Plan agents read
  /// these through `plan_history`; they are not writable via submit_result.
  var planHistoryEntries: [String]
  /// Shared VM toolchain listing/installation. Nil on host-route runs.
  var toolchainService: (any SharedVMToolchainService)?

  init(
    workingDirectory: URL,
    filesystem: AgentFilesystem = AgentHostFilesystem(),
    bashRunner: AgentBashRunner = AgentHostBashRunner(),
    readTracker: AgentReadTracker = AgentReadTracker(),
    delegateRunner: AgentDelegateRunner? = nil,
    codemapStoreDirectory: URL? = nil,
    planHistoryEntries: [String] = [],
    toolchainService: (any SharedVMToolchainService)? = nil
  ) {
    let normalizedWorkingDirectory = workingDirectory.standardizedFileURL
    self.workingDirectory = normalizedWorkingDirectory
    self.filesystem = filesystem
    self.bashRunner = bashRunner
    self.readTracker = readTracker
    self.delegateRunner = delegateRunner
    self.codemapStoreDirectory =
      codemapStoreDirectory?.standardizedFileURL
      ?? Self.defaultCodemapDirectory(forWorkingDirectory: normalizedWorkingDirectory)
    self.planHistoryEntries = planHistoryEntries
    self.toolchainService = toolchainService
  }

  static func defaultCodemapDirectory(forWorkingDirectory workingDirectory: URL) -> URL {
    workingDirectory
      .appending(path: ".compass", directoryHint: .isDirectory)
      .appending(path: "codemap", directoryHint: .isDirectory)
      .standardizedFileURL
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
  /// Mutation attempted against a path the agent hasn't read this run.
  case readNotTracked(String)
  /// `edit_file` find/replace failed to match.
  case editConflict(String)
  /// I/O failure surfaced by the underlying filesystem.
  case ioFailure(String)
  /// RPC to the shared VM guest failed (vsock / framing / decode).
  case rpcFailure(String)
  /// Bash command exited non-zero or could not be launched.
  case bashFailure(String)
  /// Sub-agent delegation could not complete (no runner, sub-agent threw).
  case delegateFailure(String)

  var errorDescription: String? {
    switch self {
    case .invalidArguments(let detail): return "Invalid arguments: \(detail)"
    case .pathEscapesWorkingDirectory(let path):
      return "Path escapes the working directory: \(path)"
    case .fileNotFound(let path): return "File not found: \(path)"
    case .notRegularFile(let path): return "Not a regular file: \(path)"
    case .notDirectory(let path): return "Not a directory: \(path)"
    case .binaryFile(let path): return "Cannot read binary file: \(path)"
    case .readNotTracked(let detail): return detail
    case .editConflict(let detail): return "Edit did not apply: \(detail)"
    case .ioFailure(let detail): return "I/O failure: \(detail)"
    case .rpcFailure(let detail): return "Guest RPC failed: \(detail)"
    case .bashFailure(let detail): return "Bash command failed: \(detail)"
    case .delegateFailure(let detail): return "Delegation failed: \(detail)"
    }
  }

  /// The categorical kind this error maps to on the result side.
  var kind: AgentToolErrorKind {
    switch self {
    case .invalidArguments: return .invalidArguments
    case .pathEscapesWorkingDirectory: return .pathEscape
    case .fileNotFound: return .fileNotFound
    case .notRegularFile: return .notRegularFile
    case .notDirectory: return .notDirectory
    case .binaryFile: return .binaryFile
    case .readNotTracked: return .readNotTracked
    case .editConflict: return .editConflict
    case .ioFailure: return .ioFailure
    case .rpcFailure: return .rpcFailure
    case .bashFailure: return .bashFailure
    case .delegateFailure: return .delegateFailure
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

  /// Codemap cache directory for this run. Tools read this rather than
  /// re-deriving the path so the executor can point them at the
  /// host-side store even when `workingDirectory` is a remote (e.g.
  /// Shared VM) guest path.
  func codemapStore() -> CodemapStore {
    CodemapStore(directory: codemapStoreDirectory)
  }
}
