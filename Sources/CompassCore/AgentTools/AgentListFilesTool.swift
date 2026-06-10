import Foundation

/// Enumerate every file currently in the codemap, optionally narrowed by a
/// substring or glob-like filter on the relative path. The output is one
/// path per line with the detected language so the model can quickly find
/// candidates without paging through `glob`.
struct AgentListFilesTool: AgentTool {
  static let toolName = "list_files"
  static let maxResults = 500

  struct Arguments: Decodable {
    let filter: String?

    enum CodingKeys: String, CodingKey {
      case filter
      case query
      case search
      case path
      case directory
      case dir
      case pattern
      case glob
      case file
      case filename
      case fileName
      case fileNameSnake = "file_name"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      filter = try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .filter,
        aliases: [
          .query, .search, .path, .directory, .dir, .pattern, .glob, .file, .filename,
          .fileName, .fileNameSnake,
        ]
      )
    }
  }

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal: [
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "filter": [
          "type": "string",
          "description":
            "Optional case-insensitive substring or glob-like filter on the relative path. Omit to list every indexed file.",
        ]
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "List the repo-relative paths the codemap has indexed, with each file's detected language. Use a `filter` substring or glob-like pattern to narrow to a subdirectory or filename. Capped at 500 results.",
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
    let filter = args.filter?.trimmingCharacters(in: .whitespacesAndNewlines)
    let store = context.codemapStore()
    var entries = store.loadAllEntries()
    if let filter, !filter.isEmpty {
      entries = entries.filter { Self.path($0.relativePath, matchesFilter: filter) }
    }
    entries.sort { $0.relativePath < $1.relativePath }
    if entries.isEmpty {
      let suffix = (filter.flatMap { $0.isEmpty ? nil : " matching '\($0)'" }) ?? ""
      return .ok("(no codemap files\(suffix))")
    }

    let truncated = entries.count > Self.maxResults
    let shown = entries.prefix(Self.maxResults)
    var lines: [String] = []
    lines.append("files: \(entries.count)\(truncated ? " (truncated)" : "")")
    for entry in shown {
      let count = entry.symbols.count
      lines.append("  \(entry.relativePath)  [\(entry.language.displayName), \(count) symbol(s)]")
    }
    return .ok(lines.joined(separator: "\n"))
  }

  private static func path(_ path: String, matchesFilter filter: String) -> Bool {
    let lowercasedPath = path.lowercased()
    let lowercasedFilter = filter.lowercased()
    if lowercasedPath.contains(lowercasedFilter) {
      return true
    }

    guard filter.contains("*") || filter.contains("?") else {
      return false
    }
    if matchesGlob(lowercasedPath, pattern: lowercasedFilter) {
      return true
    }
    if !filter.contains("/") {
      return matchesGlob(lowercasedPath, pattern: "**/\(lowercasedFilter)")
    }
    return false
  }

  private static func matchesGlob(_ path: String, pattern: String) -> Bool {
    guard let regex = try? AgentGlobPattern.regex(forGlob: pattern) else {
      return false
    }
    let range = NSRange(location: 0, length: (path as NSString).length)
    return regex.firstMatch(in: path, options: [], range: range) != nil
  }
}
