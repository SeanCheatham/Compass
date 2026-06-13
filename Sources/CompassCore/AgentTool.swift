import Foundation

/// JSON schema for tool parameters, stored as JSON-encoded bytes so it can
/// safely cross actor boundaries without round-tripping through `[String: Any]`.
package struct AgentToolParametersSchema: Sendable, Equatable {
  package let json: Data

  package init(json: Data) {
    self.json = json
  }

  package init(_ object: Any) throws {
    self.json = try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys, .withoutEscapingSlashes]
    )
  }

  /// Builds a schema from a static JSON object literal. Invalid literals
  /// are a programmer error and trap at initialization time.
  package init(literal object: Any) {
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

package struct AgentToolSpec: Sendable, Equatable {
  package let name: String
  package let description: String
  package let parameters: AgentToolParametersSchema
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
package enum AgentToolErrorKind: String, Sendable, Equatable, Codable {
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
  /// `edit_file` line range was invalid or out of range for the current file.
  case editConflict
  /// Underlying I/O failed (permission denied, disk error, ...).
  case ioFailure
  /// RPC to the container runtime failed (container transport, framing, decode).
  case rpcFailure
  /// Bash command failed with a non-zero exit.
  case bashFailure
  /// Sub-agent delegation failed before producing a result.
  case delegateFailure
  /// Catch-all for unclassified errors thrown out of a tool.
  case unknown
}

package struct AgentToolInvocationResult: Sendable, Equatable {
  package var content: String
  package var isError: Bool
  /// Optional categorical kind for failure results. Always `nil` for
  /// success results. Pre-existing string-based failure sites keep
  /// returning `nil` until migrated; new sites should use the typed
  /// `.failure(AgentToolError)` overload.
  package var errorKind: AgentToolErrorKind?

  package static func ok(_ content: String) -> Self {
    .init(content: content, isError: false, errorKind: nil)
  }

  package static func failure(_ message: String, kind: AgentToolErrorKind? = nil) -> Self {
    .init(content: message, isError: true, errorKind: kind)
  }

  /// Typed failure: maps the tool-level error to its categorical
  /// kind and uses the localized description as the message.
  package static func failure(_ error: AgentToolError) -> Self {
    .init(
      content: error.errorDescription ?? "Tool error",
      isError: true,
      errorKind: error.kind
    )
  }
}

/// Tracks which file paths have been freshly read during an agent execution.
/// `edit_file` consults this to refuse edits against contents the model has not
/// actually seen — so edits against
/// stale or hallucinated line numbers get caught early instead of silently
/// corrupting state.
package actor AgentReadTracker {
  private var readPaths: Set<String> = []
  private var lineCounts: [String: Int] = [:]

  package func markRead(_ url: URL, lineCount: Int? = nil) {
    let path = url.standardizedFileURL.path
    readPaths.insert(path)
    if let lineCount {
      lineCounts[path] = lineCount
    }
  }

  package func wasRead(_ url: URL) -> Bool {
    readPaths.contains(url.standardizedFileURL.path)
  }

  package func lineCount(for url: URL) -> Int? {
    lineCounts[url.standardizedFileURL.path]
  }
}

/// Execution context handed to a tool at invocation time. The working
/// directory is the root the tool must scope itself to — any path that
/// escapes it is rejected. The filesystem picks how file ops are served
/// (host `FileManager` vs. container-mounted workspace); the bash runner picks
/// how shell commands are dispatched. The read tracker
/// is shared across every tool call in one execution so the mutation tools
/// can require a prior `read_file`.
package struct AgentToolContext: Sendable {
  package var workingDirectory: URL
  package var filesystem: AgentFilesystem
  package var bashRunner: AgentBashRunner
  package var readTracker: AgentReadTracker
  /// Sub-agent runner used by `AgentDelegateTool`. Nil when the host
  /// doesn't expose delegation (sub-agents themselves, or unit tests
  /// that don't need the feature). The tool surfaces this as a clean
  /// failure result rather than crashing the turn.
  var delegateRunner: AgentDelegateRunner?
  /// Directory the codemap-backed tools read entries from. The codemap
  /// is built host-side at `<workspace.compassURL>/codemap/`, but when
  /// the agent runs in the containerized Linux runtime, `workingDirectory` is the container
  /// workspace — which doesn't (and shouldn't) have its own codemap. The
  /// caller threads the host-side store path through here so
  /// `list_files`, `find_symbol`, `outline`, `summary`, and
  /// `importers_of` keep finding entries regardless of route. Defaults
  /// to `<workingDirectory>/.compass/codemap` so on-host tests and
  /// stand-alone tool invocations work without configuration.
  package var codemapStoreDirectory: URL
  /// Completed plan summaries from host-side state.json. Plan agents read
  /// these through `plan_history`; they are not writable via Plan submit.
  package var planHistoryEntries: [String]
  /// Host-side assumptions ledger. The agent may run inside a containerized Linux runtime
  /// copy, but assumptions are durable Compass state and are always written
  /// through this host URL when present.
  package var assumptionsURL: URL?
  /// Phase/session metadata attached to assumptions recorded by tools.
  package var phase: AgentPhase
  package var sessionNumber: Int?
  package init(
    workingDirectory: URL,
    filesystem: AgentFilesystem = AgentHostFilesystem(),
    bashRunner: AgentBashRunner = AgentHostBashRunner(),
    readTracker: AgentReadTracker = AgentReadTracker(),
    delegateRunner: AgentDelegateRunner? = nil,
    codemapStoreDirectory: URL? = nil,
    planHistoryEntries: [String] = [],
    assumptionsURL: URL? = nil,
    phase: AgentPhase = .plan,
    sessionNumber: Int? = nil
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
    self.assumptionsURL = assumptionsURL?.standardizedFileURL
    self.phase = phase
    self.sessionNumber = sessionNumber.flatMap { $0 > 0 ? $0 : nil }
  }

  package static func defaultCodemapDirectory(forWorkingDirectory workingDirectory: URL) -> URL {
    workingDirectory
      .appending(path: ".compass", directoryHint: .isDirectory)
      .appending(path: "codemap", directoryHint: .isDirectory)
      .standardizedFileURL
  }
}

package protocol AgentTool: Sendable {
  var spec: AgentToolSpec { get }
  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
}

package enum AgentToolError: LocalizedError, Equatable {
  case invalidArguments(String)
  case pathEscapesWorkingDirectory(String)
  case fileNotFound(String)
  case notRegularFile(String)
  case notDirectory(String)
  case binaryFile(String)
  /// Mutation attempted against a path the agent hasn't read this run.
  case readNotTracked(String)
  /// `edit_file` line-range edit failed to apply.
  case editConflict(String)
  /// I/O failure surfaced by the underlying filesystem.
  case ioFailure(String)
  /// RPC to the containerized Linux runtime failed (container transport / framing / decode).
  case rpcFailure(String)
  /// Bash command exited non-zero or could not be launched.
  case bashFailure(String)
  /// Sub-agent delegation could not complete (no runner, sub-agent threw).
  case delegateFailure(String)

  package var errorDescription: String? {
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
    case .rpcFailure(let detail): return "Runtime transport failed: \(detail)"
    case .bashFailure(let detail): return "Bash command failed: \(detail)"
    case .delegateFailure(let detail): return "Delegation failed: \(detail)"
    }
  }

  /// The categorical kind this error maps to on the result side.
  package var kind: AgentToolErrorKind {
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

package extension AgentToolContext {
  /// Resolve a possibly-relative path against the working directory. Paths
  /// that resolve outside the working directory are rejected so a buggy or
  /// adversarial tool call can't read `/etc/passwd` from a sandbox-style
  /// read-only planning or review pass.
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
  /// containerized Linux runtime) container path.
  func codemapStore() -> CodemapStore {
    CodemapStore(directory: codemapStoreDirectory)
  }
}
