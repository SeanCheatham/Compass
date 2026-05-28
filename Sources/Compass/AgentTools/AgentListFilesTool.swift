import Foundation

/// Enumerate every file currently in the codemap, optionally narrowed by a
/// substring or glob-like filter on the relative path. The output is one
/// path per line with the detected language so the model can quickly find
/// candidates without paging through `glob`.
struct AgentListFilesTool: AgentTool {
  static let toolName = "list_files"
  static let maxResults = 500

  struct Arguments: Codable {
    let filter: String?
  }

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal:[
      "type": "object",
      "additionalProperties": false,
      "properties": [
        "filter": [
          "type": "string",
          "description":
            "Optional case-insensitive substring filter on the relative path. Omit to list every indexed file.",
        ]
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "List the repo-relative paths the codemap has indexed, with each file's detected language. Use a `filter` substring to narrow to a subdirectory or filename pattern. Capped at 500 results.",
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
    let filter = args.filter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let store = context.codemapStore()
    var entries = store.loadAllEntries()
    if let filter, !filter.isEmpty {
      entries = entries.filter { $0.relativePath.lowercased().contains(filter) }
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
}
