import Foundation

/// Return the symbol outline for a single file from the on-disk codemap.
/// Faster (and cheaper) than `read_file` when the model only needs to know
/// what a file defines, not its full contents.
struct AgentOutlineTool: AgentTool {
  static let toolName = "outline"

  struct Arguments: Codable {
    let path: String
  }

  let spec: AgentToolSpec

  init() {
    let schema = AgentToolParametersSchema(literal:[
      "type": "object",
      "additionalProperties": false,
      "required": ["path"],
      "properties": [
        "path": [
          "type": "string",
          "description":
            "Repo-relative path to the file. Must match a path that the codemap indexer has seen.",
        ]
      ],
    ])
    spec = AgentToolSpec(
      name: Self.toolName,
      description:
        "List the top-level declarations (functions, classes, methods, types, imports) in one file, drawn from the codemap. Cheap; use this before `read_file` when you only need the file's shape.",
      parameters: schema
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult
  {
    let args: Arguments
    do {
      args = try JSONDecoder().decode(Arguments.self, from: arguments)
    } catch {
      return .failure("Failed to decode arguments: \(error.localizedDescription)")
    }
    let normalized = AgentCodemapPath.normalize(
      args.path, workingDirectory: context.workingDirectory)
    let store = context.codemapStore()
    guard let entry = store.loadEntry(forRelativePath: normalized) else {
      return .failure(
        "No codemap entry for '\(normalized)'. Run the indexer or use `list_files` to discover what's been parsed."
      )
    }

    var lines: [String] = []
    lines.append("path: \(entry.relativePath)")
    lines.append("language: \(entry.language.displayName)")
    if !entry.imports.isEmpty {
      lines.append("")
      lines.append("imports:")
      for imp in entry.imports {
        lines.append("  L\(imp.line)  \(imp.raw)")
      }
    }
    if entry.symbols.isEmpty {
      lines.append("")
      lines.append("symbols: (none)")
    } else {
      lines.append("")
      lines.append("symbols:")
      for symbol in entry.symbols {
        lines.append(
          "  L\(symbol.line)-\(symbol.endLine)  \(symbol.kind.rawValue)  \(symbol.name)")
      }
    }
    return .ok(lines.joined(separator: "\n"))
  }
}
